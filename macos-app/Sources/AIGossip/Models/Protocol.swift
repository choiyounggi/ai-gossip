import Foundation

// Swift counterpart of server/src/protocol.ts. Wire format is JSON with a
// "type" discriminator; we use Codable + a two-step decode (probe type,
// then decode the matching concrete struct).

// MARK: - Shared DTOs

struct ServerParticipantDTO: Codable {
    let userId: String
    let userName: String
    let publicProfile: String
}

struct ServerChatMessageDTO: Codable {
    let userId: String
    let userName: String
    let content: String
    let timestamp: String // ISO-8601
    /// Server-assigned monotonic seq. Optional for backward compat: an older
    /// server that hasn't been restarted with the reconnect patch will omit it.
    /// Decoding to 0 keeps the live chat rendering; reconnect recovery is
    /// degraded (falls back to "replay everything"), which is still safe.
    let seq: Int

    enum CodingKeys: String, CodingKey {
        case userId, userName, content, timestamp, seq
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decode(String.self, forKey: .userId)
        userName = try c.decode(String.self, forKey: .userName)
        content = try c.decode(String.self, forKey: .content)
        timestamp = try c.decode(String.self, forKey: .timestamp)
        seq = (try? c.decode(Int.self, forKey: .seq)) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(userId, forKey: .userId)
        try c.encode(userName, forKey: .userName)
        try c.encode(content, forKey: .content)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(seq, forKey: .seq)
    }
}

// MARK: - Client → Server

struct ClientJoinRoom: Encodable {
    let type: String = "JOIN_ROOM"
    let roomId: String
    let userId: String
    let userName: String
    let publicProfile: String
    /// Reconnect hint — the server replays only messages with `seq > sinceSeq`.
    /// nil on first connect; set on every reconnect so we don't lose anything.
    let sinceSeq: Int?
}

struct ClientChatMessage: Encodable {
    let type: String = "MESSAGE"
    let roomId: String
    let userId: String
    let content: String
}

struct ClientLeave: Encodable {
    let type: String = "LEAVE"
    let roomId: String
    let userId: String
}

/// Passive subscription — start receiving LOBBY_STATE for a given room
/// without consuming a participant slot. Promoted to JOIN_ROOM when the
/// user clicks "엿듣기 시작".
struct ClientWatchLobby: Encodable {
    let type: String = "WATCH_LOBBY"
    let roomId: String
}

struct ClientUnwatchLobby: Encodable {
    let type: String = "UNWATCH_LOBBY"
    let roomId: String
}

// MARK: - Server → Client

struct ServerTypeProbe: Decodable {
    let type: String
}

struct ServerJoined: Decodable {
    let type: String
    let roomId: String
    let participants: [ServerParticipantDTO]
}

struct ServerYourTurn: Decodable {
    let type: String
    let roomId: String
    let turn: Int
    let history: [ServerChatMessageDTO]
    let participants: [ServerParticipantDTO]
}

struct ServerRoomUpdate: Decodable {
    let type: String
    let roomId: String
    let message: ServerChatMessageDTO
}

struct ServerRoomClosed: Decodable {
    let type: String
    let roomId: String
    let reason: String
}

struct ServerErrorMessage: Decodable {
    let type: String
    let reason: String
}

/// Delivered once to the joining participant so a late joiner can render
/// prior context immediately instead of waiting until their first turn.
struct ServerRoomSnapshot: Decodable {
    let type: String
    let roomId: String
    let history: [ServerChatMessageDTO]
    let participants: [ServerParticipantDTO]
}

/// Pushed to every socket that has sent WATCH_LOBBY for `roomId`,
/// whenever the participant roster changes.
struct ServerLobbyState: Decodable {
    let type: String
    let roomId: String
    let participants: [ServerParticipantDTO]
    let isFull: Bool
}
