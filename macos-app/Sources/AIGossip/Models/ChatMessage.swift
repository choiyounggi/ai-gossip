import Foundation

struct ChatMessage: Identifiable, Hashable {
    let id: UUID
    let participantId: String
    let userName: String
    let content: String
    let timestamp: Date
    /// Server-assigned monotonic seq (0 for locally-constructed/placeholder msgs).
    /// Used to deduplicate after reconnect replays.
    let seq: Int

    init(
        id: UUID = UUID(),
        participantId: String,
        userName: String,
        content: String,
        timestamp: Date = Date(),
        seq: Int = 0
    ) {
        self.id = id
        self.participantId = participantId
        self.userName = userName
        self.content = content
        self.timestamp = timestamp
        self.seq = seq
    }
}

enum ConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case roomClosed(reason: String)
}
