import SwiftUI

struct ChatView: View {
    let messages: [ChatMessage]
    let participants: [Participant]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if messages.isEmpty {
                        emptyState
                    }
                    ForEach(messages) { msg in
                        if let p = lookupParticipant(msg.participantId, fallbackName: msg.userName) {
                            ChatBubbleView(participant: p, message: msg)
                                .id(msg.id)
                        }
                    }
                }
                .padding(.vertical, 12)
            }
            .background(DeskRPGTheme.parchment)
            .onChange(of: messages.last?.id) { _, newValue in
                guard let id = newValue else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
    }

    /// Resolve the Participant for rendering. If a participant has since left
    /// the room we still want to show their past message, so fall back to a
    /// synthetic Participant with the preserved display name.
    private func lookupParticipant(_ id: String, fallbackName: String) -> Participant? {
        if let existing = participants.first(where: { $0.id == id }) {
            return existing
        }
        return Participant(id: id, userName: fallbackName, publicProfile: "")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("💬")
                .font(.system(size: 40))
            Text("대화가 시작되기를 기다리는 중…")
                .font(DeskRPGTheme.bodyFont)
                .foregroundStyle(DeskRPGTheme.inkSoft)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding()
    }
}
