import Foundation
import SwiftUI

/// Live WebSocket client for the Phase-2 battle server.
/// Lifecycle:
///   - `connect(...)` opens the socket and sends JOIN_ROOM
///   - server emits JOINED / YOUR_TURN / ROOM_UPDATE / ROOM_CLOSED
///   - `leave()` sends LEAVE, closes the socket, and resets published state
///
/// On `YOUR_TURN` we auto-reply after a short delay so round-robin rotation
/// keeps moving — real Claude integration replaces this placeholder later.
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
    private var selfId: String?
    private var selfName: String?
    private var selfProfile: String = ""
    private let claudeRunner = ClaudeRunner()
    private var replyInFlight: Bool = false

    var hasJoined: Bool { selfParticipant != nil && status == .connected }

    // MARK: - Lifecycle

    /// Open the socket in lobby-watch mode: we just subscribe to LOBBY_STATE
    /// for `roomId` and get live participant updates without joining.
    func watchLobby(serverURL: URL, roomId: String) {
        // If we're already watching the same room, nothing to do.
        if isWatchingLobby && self.roomId == roomId && task != nil { return }
        teardown()

        self.roomId = roomId
        self.status = .connecting

        let task = URLSession.shared.webSocketTask(with: serverURL)
        self.task = task
        task.resume()

        self.isWatchingLobby = true
        send(ClientWatchLobby(roomId: roomId))
        receiveLoop()
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
            self.roomId = roomId
            self.status = .connecting
            let task = URLSession.shared.webSocketTask(with: serverURL)
            self.task = task
            task.resume()
        }

        self.selfId = userId
        self.selfName = userName
        self.selfProfile = publicProfile
        self.isWatchingLobby = false

        send(ClientJoinRoom(
            roomId: roomId,
            userId: userId,
            userName: userName,
            publicProfile: publicProfile
        ))

        if !reuseSocket {
            receiveLoop()
        }
    }

    /// Politely leave the room and drop the socket. Safe to call multiple times.
    func leave() {
        if let id = selfId {
            send(ClientLeave(roomId: roomId, userId: id))
        }
        teardown()
    }

    /// Drop lobby-watch subscription without closing the app window. Used when
    /// the user navigates away from the lobby without joining.
    func unwatchLobby() {
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
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
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
                    // Don't treat a clean close after LEAVE as an error.
                    if self.task != nil {
                        print("[ws] receive failed: \(err.localizedDescription)")
                        self.status = .disconnected
                    }
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
            }
        case "ROOM_SNAPSHOT":
            if let m = try? decoder.decode(ServerRoomSnapshot.self, from: data) {
                self.participants = m.participants.map(Self.convertParticipant)
                self.selfParticipant = self.participants.first { $0.id == self.selfId }
                self.messages = m.history.map(Self.convertMessage)
                self.status = .connected
            }
        case "YOUR_TURN":
            if let m = try? decoder.decode(ServerYourTurn.self, from: data) {
                self.participants = m.participants.map(Self.convertParticipant)
                self.messages = m.history.map(Self.convertMessage)
                self.currentTurnParticipantId = self.selfId
                generateAndSendReply()
            }
        case "ROOM_UPDATE":
            if let m = try? decoder.decode(ServerRoomUpdate.self, from: data) {
                self.messages.append(Self.convertMessage(m.message))
                // Someone else spoke → our turn (if any) is over until server says so.
                if m.message.userId != self.selfId {
                    self.currentTurnParticipantId = nil
                }
            }
        case "ROOM_CLOSED":
            if let m = try? decoder.decode(ServerRoomClosed.self, from: data) {
                self.status = .roomClosed(reason: m.reason)
            }
        case "LOBBY_STATE":
            if let m = try? decoder.decode(ServerLobbyState.self, from: data) {
                self.lobbyParticipants = m.participants.map(Self.convertParticipant)
                self.lobbyIsFull = m.isFull
                // Lobby watcher is a real connection — surface status too.
                if self.isWatchingLobby && self.status == .connecting {
                    self.status = .connected
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
            timestamp: date
        )
    }

}
