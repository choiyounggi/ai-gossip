import SwiftUI

/// Top-level split layout: participants on the left, conversation on the right.
/// Mimics DeskRPG's "office sidebar + center stage" arrangement without the
/// map canvas, since gossip sessions are conversation-first.
struct RootView: View {
    @EnvironmentObject private var room: RoomService
    var onLeave: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ParticipantListView(
                participants: room.participants,
                currentTurnParticipantId: room.currentTurnParticipantId
            )
            .frame(width: 240)

            Divider().background(DeskRPGTheme.ink.opacity(0.3))

            VStack(spacing: 0) {
                RoomHeaderView(
                    roomId: room.roomId,
                    participantCount: room.participants.count,
                    status: room.status,
                    onLeave: onLeave
                )
                ChatView(
                    messages: room.messages,
                    participants: room.participants
                )
            }
        }
        .background(DeskRPGTheme.parchment)
    }
}
