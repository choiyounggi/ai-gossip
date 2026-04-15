import Foundation
import SwiftUI

/// Live WebSocket client for the Phase-2 battle server.
/// Lifecycle:
///   - `connect(...)` opens the socket and sends JOIN_ROOM
///   - server emits JOINED / YOUR_TURN / ROOM_UPDATE / ROOM_CLOSED
///   - `leave()` sends LEAVE, closes the socket, and resets published state
///
/// Network resilience:
///   - `URLSessionWebSocketTask.sendPing` runs on a timer; if it fails, we
///     tear down the socket and schedule a reconnect.
///   - Exponential backoff (1s → 2s → 4s … capped at 30s) with a cap on
///     total attempts. On reopen we re-send JOIN_ROOM with `sinceSeq` so
///     the server can replay missed messages.
@MainActor
final class RoomService: ObservableObject {
    @Published private(set) var roomId: String = ""
    @Published private(set) var participants: [Participant] = []
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var currentTurnParticipantId: String? = nil
    @Published private(set) var status: ConnectionStatus = .disconnected
    @Published private(set) var selfParticipant: Participant? = nil

    /// Passive preview of who is currently in the room — populated while the
    /// socket is in "lobby watcher" mode. Reset on teardown.
    @Published private(set) var lobbyParticipants: [Participant] = []
    @Published private(set) var lobbyIsFull: Bool = false
    @Published private(set) var isWatchingLobby: Bool = false

    private var task: URLSessionWebSocketTask?
    private var serverURL: URL?
    private var selfId: String?
    private var selfName: String?
    private var selfProfile: String = ""
    private let claudeRunner = ClaudeRunner()
    private var replyInFlight: Bool = false

    // MARK: - Reconnect state

    /// Highest seq we've observed. Sent back as `sinceSeq` on reconnect.
    private var lastSeq: Int = 0
    /// True if the user explicitly leave()'d — don't retry after that.
    private var userInitiatedClose: Bool = false
    /// How many consecutive reconnect attempts we've made since last success.
    private var reconnectAttempts: Int = 0
    /// Set while a reconnect setTimeout-equivalent is pending.
    private var reconnectTask: Task<Void, Never>?
    /// Set while the ping timer is running.
    private var pingTask: Task<Void, Never>?
    /// True once we've completed the initial JOIN_ROOM; controls whether a
    /// reopen is a "reconnect" (send sinceSeq) vs a fresh join.
    private var hasJoinedOnce: Bool = false

    private static let maxReconnectAttempts = 10
    private static let pingIntervalSeconds: UInt64 = 25

    var hasJoined: Bool {
        selfParticipant != nil && (status == .connected || status == .reconnecting)
    }

    // MARK: - Lifecycle

    /// Open the socket in lobby-watch mode: we just subscribe to LOBBY_STATE
    /// for `roomId` and get live participant updates without joining.
    func watchLobby(serverURL: URL, roomId: String) {
        // If we're already watching the same room, nothing to do.
        if isWatchingLobby && self.roomId == roomId && task != nil { return }
        teardown()

        self.serverURL = serverURL
        self.roomId = roomId
        self.status = .connecting

        openSocket()
        self.isWatchingLobby = true
        send(ClientWatchLobby(roomId: roomId))
        receiveLoop()
        startPingLoop()
    }

    func connect(
        serverURL: URL,
        roomId: String,
        userId: String,
        userName: String,
        publicProfile: String
    ) {
        // If we're already watching the same room, upgrade in place instead
        // of tearing down the socket — the server promotes the same connection.
        let reuseSocket = isWatchingLobby && self.roomId == roomId && task != nil
        if !reuseSocket {
            teardown()
            self.serverURL = serverURL
            self.roomId = roomId
            self.status = .connecting
            openSocket()
        }

        self.selfId = userId
        self.selfName = userName
        self.selfProfile = publicProfile
        self.isWatchingLobby = false

        send(ClientJoinRoom(
            roomId: roomId,
            userId: userId,
            userName: userName,
            publicProfile: publicProfile,
            sinceSeq: nil
        ))
        hasJoinedOnce = true

        if !reuseSocket {
            receiveLoop()
            startPingLoop()
        }
    }

    /// Politely leave the room and drop the socket. Safe to call multiple times.
    func leave() {
        userInitiatedClose = true
        if let id = selfId {
            send(ClientLeave(roomId: roomId, userId: id))
        }
        teardown()
    }

    /// Drop lobby-watch subscription without closing the app window. Used when
    /// the user navigates away from the lobby without joining.
    func unwatchLobby() {
        userInitiatedClose = true
        if isWatchingLobby {
            send(ClientUnwatchLobby(roomId: roomId))
        }
        teardown()
    }

    /// Terminate the active claude subprocess + socket. Called from
    /// `applicationWillTerminate` so subprocesses don't outlive the GUI.
    func shutdown() {
        if selfId != nil {
            leave()
        } else if isWatchingLobby {
            unwatchLobby()
        } else {
            teardown()
        }
        Task { await claudeRunner.cancelActive() }
    }

    private func teardown() {
        reconnectTask?.cancel()
        reconnectTask = nil
        pingTask?.cancel()
        pingTask = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        serverURL = nil
        selfId = nil
        selfName = nil
        selfProfile = ""
        selfParticipant = nil
        participants = []
        messages = []
        currentTurnParticipantId = nil
        replyInFlight = false
        isWatchingLobby = false
        lobbyParticipants = []
        lobbyIsFull = false
        status = .disconnected
        lastSeq = 0
        reconnectAttempts = 0
        hasJoinedOnce = false
        userInitiatedClose = false
    }

    // MARK: - Socket open / reconnect

    private func openSocket() {
        guard let url = serverURL else { return }
        let task = URLSession.shared.webSocketTask(with: url)
        self.task = task
        task.resume()
    }

    private func handleSocketFailure(_ err: Error) {
        // Already tore down (leave/unwatch) — nothing to do.
        if task == nil || userInitiatedClose { return }
        print("[ws] receive failed: \(err.localizedDescription)")
        // Drop the dead socket and try again.
        task?.cancel(with: .abnormalClosure, reason: nil)
        task = nil
        pingTask?.cancel()
        pingTask = nil
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard !userInitiatedClose else { return }
        guard serverURL != nil else { return }
        // Don't pile up reconnect tasks; if one's pending, let it run.
        if reconnectTask != nil { return }

        reconnectAttempts += 1
        if reconnectAttempts > Self.maxReconnectAttempts {
            print("[ws] giving up after \(Self.maxReconnectAttempts) attempts")
            self.status = .roomClosed(reason: "연결이 끊어졌습니다")
            return
        }

        let delaySeconds = min(30, 1 << (reconnectAttempts - 1))
        self.status = .reconnecting
        print("[ws] reconnecting in \(delaySeconds)s (attempt \(reconnectAttempts))")

        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds) * 1_000_000_000)
            guard let self = self else { return }
            self.reconnectTask = nil
            if self.userInitiatedClose { return }
            self.openSocket()
            self.resendJoinAfterReconnect()
            self.receiveLoop()
            self.startPingLoop()
        }
    }

    private func resendJoinAfterReconnect() {
        // Lobby-watcher re-subscribe path.
        if isWatchingLobby {
            send(ClientWatchLobby(roomId: roomId))
            return
        }
        // Participant resume path — hand over lastSeq so the server replays
        // missed ROOM_UPDATEs via ROOM_SNAPSHOT.
        guard let myId = selfId, let myName = selfName, hasJoinedOnce else { return }
        send(ClientJoinRoom(
            roomId: roomId,
            userId: myId,
            userName: myName,
            publicProfile: selfProfile,
            sinceSeq: lastSeq
        ))
    }

    // MARK: - Heartbeat

    /// Kick off a recurring ping. URLSessionWebSocketTask's sendPing calls
    /// the completion with an error if the socket is dead, which is our
    /// signal to reconnect even when receive() hasn't surfaced the drop yet
    /// (WiFi handoff, laptop sleep, etc.).
    private func startPingLoop() {
        pingTask?.cancel()
        pingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(
                    nanoseconds: Self.pingIntervalSeconds * 1_000_000_000,
                )
                guard let self = self, let task = self.task else { return }
                if Task.isCancelled { return }
                task.sendPing { [weak self] error in
                    Task { @MainActor [weak self] in
                        guard let self = self, let error = error else { return }
                        print("[ws] ping failed: \(error.localizedDescription)")
                        self.handleSocketFailure(error)
                    }
                }
            }
        }
    }

    // MARK: - Incoming

    private func receiveLoop() {
        task?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch result {
                case .success(.string(let text)):
                    self.handleServerMessage(text)
                    self.receiveLoop()
                case .success(.data(let data)):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleServerMessage(text)
                    }
                    self.receiveLoop()
                case .success:
                    self.receiveLoop()
                case .failure(let err):
                    self.handleSocketFailure(err)
                }
            }
        }
    }

    private func handleServerMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        let decoder = JSONDecoder()
        guard let probe = try? decoder.decode(ServerTypeProbe.self, from: data) else {
            print("[ws] unknown frame: \(text)")
            return
        }

        switch probe.type {
        case "JOINED":
            if let m = try? decoder.decode(ServerJoined.self, from: data) {
                self.participants = m.participants.map(Self.convertParticipant)
                self.selfParticipant = self.participants.first { $0.id == self.selfId }
                self.status = .connected
                self.reconnectAttempts = 0
            } else {
                print("[ws] decode JOINED failed: \(text)")
            }
        case "ROOM_SNAPSHOT":
            if let m = try? decoder.decode(ServerRoomSnapshot.self, from: data) {
                self.participants = m.participants.map(Self.convertParticipant)
                self.selfParticipant = self.participants.first { $0.id == self.selfId }

                // Two flavors of snapshot:
                //   1. Late-joiner: full recent window, all seqs new to us
                //   2. Reconnect: only msgs with seq > sinceSeq
                // When the server supports seq, dedup by lastSeq. When seq is
                // 0 across the board (old server), fall back to "replace if
                // local empty, else skip" — safer than double-appending.
                let maxSeq = m.history.map(\.seq).max() ?? 0
                if maxSeq > 0 {
                    let fresh = m.history
                        .filter { $0.seq > self.lastSeq }
                        .map(Self.convertMessage)
                    if self.messages.isEmpty {
                        self.messages = fresh
                    } else {
                        self.messages.append(contentsOf: fresh)
                    }
                    if maxSeq > self.lastSeq { self.lastSeq = maxSeq }
                } else if self.messages.isEmpty {
                    self.messages = m.history.map(Self.convertMessage)
                }

                self.status = .connected
                self.reconnectAttempts = 0
            } else {
                print("[ws] decode ROOM_SNAPSHOT failed: \(text)")
            }
        case "YOUR_TURN":
            if let m = try? decoder.decode(ServerYourTurn.self, from: data) {
                self.participants = m.participants.map(Self.convertParticipant)
                if let maxSeq = m.history.map(\.seq).max(), maxSeq > self.lastSeq {
                    self.lastSeq = maxSeq
                }
                // First-time join: adopt the server's window. Otherwise leave
                // our local ROOM_UPDATE-built history alone.
                if self.messages.isEmpty {
                    self.messages = m.history.map(Self.convertMessage)
                }
                self.currentTurnParticipantId = self.selfId
                generateAndSendReply()
            } else {
                print("[ws] decode YOUR_TURN failed: \(text)")
            }
        case "ROOM_UPDATE":
            if let m = try? decoder.decode(ServerRoomUpdate.self, from: data) {
                // Always append live updates. When seq is present, update
                // lastSeq so a later reconnect can ask "give me what's new
                // since this point" — but don't GATE the append on seq,
                // otherwise an older seq-less server drops every message.
                self.messages.append(Self.convertMessage(m.message))
                if m.message.seq > self.lastSeq {
                    self.lastSeq = m.message.seq
                }
                // Someone else spoke → our turn (if any) is over until server says so.
                if m.message.userId != self.selfId {
                    self.currentTurnParticipantId = nil
                }
            } else {
                print("[ws] decode ROOM_UPDATE failed: \(text)")
            }
        case "ROOM_CLOSED":
            if let m = try? decoder.decode(ServerRoomClosed.self, from: data) {
                self.userInitiatedClose = true // stop reconnecting
                // Defensive cleanup: an older server may close the room without
                // emitting a final JOINED, leaving the departed user stuck in
                // our list. Trim to just our own participant so the sidebar
                // matches reality when we show the "종료" state.
                if let me = self.selfParticipant {
                    self.participants = [me]
                } else {
                    self.participants = []
                }
                self.currentTurnParticipantId = nil
                self.status = .roomClosed(reason: m.reason)
            } else {
                print("[ws] decode ROOM_CLOSED failed: \(text)")
            }
        case "LOBBY_STATE":
            if let m = try? decoder.decode(ServerLobbyState.self, from: data) {
                self.lobbyParticipants = m.participants.map(Self.convertParticipant)
                self.lobbyIsFull = m.isFull
                // Lobby watcher is a real connection — surface status too.
                if self.isWatchingLobby
                    && (self.status == .connecting || self.status == .reconnecting)
                {
                    self.status = .connected
                    self.reconnectAttempts = 0
                }
            }
        case "ERROR":
            if let m = try? decoder.decode(ServerErrorMessage.self, from: data) {
                print("[ws] server error: \(m.reason)")
            }
        default:
            print("[ws] unhandled type: \(probe.type)")
        }
    }

    private func generateAndSendReply() {
        guard !replyInFlight,
              let myId = selfId,
              let myName = selfName else { return }
        replyInFlight = true

        // Capture the inputs now — by the time we come back from the actor hop,
        // `messages` may have grown with ROOM_UPDATEs from others.
        let prompt = PromptBuilder.buildTurnPrompt(
            selfId: myId,
            selfName: myName,
            selfPublicProfile: selfProfile,
            participants: participants,
            history: messages
        )
        let roomIdSnapshot = roomId

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let content: String
            do {
                content = try await self.claudeRunner.run(prompt: prompt)
            } catch {
                print("[room] claude failed: \(error.localizedDescription)")
                content = "(응답 생성 실패, 다음 턴으로 넘깁니다)"
            }

            defer { self.replyInFlight = false }
            // Guard against LEAVE during generation.
            guard self.currentTurnParticipantId == myId else { return }

            self.send(ClientChatMessage(
                roomId: roomIdSnapshot,
                userId: myId,
                content: content.isEmpty ? "(응답 비어있음)" : content
            ))
            self.currentTurnParticipantId = nil
        }
    }

    // MARK: - Outgoing

    private func send<T: Encodable>(_ msg: T) {
        guard let task = task else { return }
        do {
            let data = try JSONEncoder().encode(msg)
            guard let str = String(data: data, encoding: .utf8) else { return }
            task.send(.string(str)) { err in
                if let err = err {
                    print("[ws] send failed: \(err.localizedDescription)")
                }
            }
        } catch {
            print("[ws] encode failed: \(error)")
        }
    }

    // MARK: - Conversions

    private static func convertParticipant(_ dto: ServerParticipantDTO) -> Participant {
        Participant(
            id: dto.userId,
            userName: dto.userName,
            publicProfile: dto.publicProfile
        )
    }

    private static func convertMessage(_ dto: ServerChatMessageDTO) -> ChatMessage {
        let date = ISO8601DateFormatter().date(from: dto.timestamp) ?? Date()
        return ChatMessage(
            participantId: dto.userId,
            userName: dto.userName,
            content: dto.content,
            timestamp: date,
            seq: dto.seq
        )
    }

}
