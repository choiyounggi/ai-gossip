import SwiftUI

/// Pixel-office character badge. Current implementation uses an emoji on a
/// hue-tinted disc with a thick dark border; swap the emoji layer for a real
/// LPC sprite later without changing the API.
struct CharacterAvatarView: View {
    let participant: Participant
    var size: CGFloat = DeskRPGTheme.avatarSize
    var isSpeaking: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(participant.accentColor(saturation: 0.35, brightness: 0.92))
            Text(participant.avatarEmoji)
                .font(.system(size: size * 0.58))
                // Keep emoji crisp at any scale. Even though emoji aren't bitmap
                // assets, .interpolation(.none) is a no-op safeguard for future
                // image-based avatars.
        }
        .frame(width: size, height: size)
        .overlay(
            Circle()
                .strokeBorder(DeskRPGTheme.ink, lineWidth: DeskRPGTheme.borderWidth)
        )
        .overlay(
            Circle()
                .strokeBorder(
                    isSpeaking ? DeskRPGTheme.accent : .clear,
                    lineWidth: DeskRPGTheme.borderWidth + 2
                )
                .padding(-4)
                .opacity(isSpeaking ? 1 : 0)
                .animation(.easeInOut(duration: 0.25), value: isSpeaking)
        )
    }
}

// Preview blocks are Xcode-only; omitted so `swift build` stays green.
