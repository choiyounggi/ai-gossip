import Foundation

struct ChatMessage: Identifiable, Hashable {
    let id: UUID
    let participantId: String
    let userName: String
    let content: String
    let timestamp: Date

    init(
        id: UUID = UUID(),
        participantId: String,
        userName: String,
        content: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.participantId = participantId
        self.userName = userName
        self.content = content
        self.timestamp = timestamp
    }
}

enum ConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case roomClosed(reason: String)
}
