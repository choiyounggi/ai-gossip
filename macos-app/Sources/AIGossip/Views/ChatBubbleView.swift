import SwiftUI

/// RPG-dialog-style speech bubble: avatar column on the left, name tag on top
/// of the content box with a thick border. Kept intentionally boxy (small
/// corner radius) to preserve the pixel-game feel.
struct ChatBubbleView: View {
    let participant: Participant
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CharacterAvatarView(participant: participant, size: 40)
            bubble
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 0) {
            nameTag
            content
        }
        .pixelBorder(color: DeskRPGTheme.ink, width: DeskRPGTheme.borderWidth)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var nameTag: some View {
        HStack(spacing: 6) {
            Text(message.userName)
                .font(DeskRPGTheme.nameFont)
                .foregroundStyle(.white)
            Text(Self.timeFormatter.string(from: message.timestamp))
                .font(DeskRPGTheme.captionFont)
                .foregroundStyle(.white.opacity(0.8))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(participant.accentColor(saturation: 0.60, brightness: 0.45))
    }

    private var content: some View {
        Text(message.content)
            .font(DeskRPGTheme.bodyFont)
            .foregroundStyle(DeskRPGTheme.ink)
            .textSelection(.enabled)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DeskRPGTheme.parchment)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
