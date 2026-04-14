import SwiftUI

struct ParticipantListView: View {
    let participants: [Participant]
    let currentTurnParticipantId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader
            Divider().background(DeskRPGTheme.ink.opacity(0.3))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(participants) { participant in
                        row(for: participant)
                    }
                    if participants.isEmpty {
                        emptyState
                    }
                }
                .padding(12)
            }
        }
        .background(DeskRPGTheme.parchmentDeep)
    }

    private var sidebarHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.3.fill")
                .foregroundStyle(DeskRPGTheme.inkSoft)
            Text("참가자 \(participants.count)/5")
                .font(DeskRPGTheme.nameFont)
                .foregroundStyle(DeskRPGTheme.ink)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func row(for p: Participant) -> some View {
        let speaking = p.id == currentTurnParticipantId
        return HStack(spacing: 10) {
            CharacterAvatarView(participant: p, size: 36, isSpeaking: speaking)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.userName)
                    .font(DeskRPGTheme.nameFont)
                    .foregroundStyle(DeskRPGTheme.ink)
                Text(speaking ? "● 발언 중" : "대기")
                    .font(DeskRPGTheme.captionFont)
                    .foregroundStyle(
                        speaking ? DeskRPGTheme.accent : DeskRPGTheme.inkSoft
                    )
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(speaking ? DeskRPGTheme.parchment : .clear)
        .pixelBorder(
            color: speaking ? DeskRPGTheme.ink : DeskRPGTheme.inkSoft.opacity(0.25),
            width: speaking ? 2 : 1
        )
    }

    private var emptyState: some View {
        Text("아직 아무도 없음")
            .font(DeskRPGTheme.captionFont)
            .foregroundStyle(DeskRPGTheme.inkSoft)
            .padding()
    }
}
