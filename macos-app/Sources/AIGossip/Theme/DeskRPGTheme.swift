import SwiftUI

/// Palette + typography loosely inspired by DeskRPG's warm pixel-office vibe.
/// Everything goes through this struct so we can retarget asset-based styling
/// later without touching each view.
enum DeskRPGTheme {
    // MARK: Palette — warm paper/wood tones with a single saturated accent

    static let parchment     = Color(red: 0.953, green: 0.914, blue: 0.840) // #F3E9D7
    static let parchmentDeep = Color(red: 0.910, green: 0.843, blue: 0.718) // #E8D7B7
    static let ink           = Color(red: 0.176, green: 0.137, blue: 0.094) // #2D2318
    static let inkSoft       = Color(red: 0.361, green: 0.267, blue: 0.180) // #5C442E
    static let accent        = Color(red: 0.376, green: 0.576, blue: 0.494) // #608F7E — muted game-green
    static let accentDim     = Color(red: 0.537, green: 0.447, blue: 0.322) // #8E7252 — tan accent

    // MARK: Typography — monospace for the retro-pixel feel

    static let bodyFont    = Font.system(.body,     design: .monospaced)
    static let captionFont = Font.system(.caption,  design: .monospaced)
    static let nameFont    = Font.system(.callout,  design: .monospaced).weight(.bold)
    static let headerFont  = Font.system(.title3,   design: .monospaced).weight(.bold)

    // MARK: Geometry

    static let borderWidth: CGFloat = 2
    static let dialogRadius: CGFloat = 4   // slight corner — not fully square
    static let avatarSize: CGFloat = 44
}

// MARK: - Reusable modifiers

struct PixelBorder: ViewModifier {
    var color: Color = DeskRPGTheme.ink
    var width: CGFloat = DeskRPGTheme.borderWidth
    var radius: CGFloat = DeskRPGTheme.dialogRadius
    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(color, lineWidth: width)
            )
    }
}

extension View {
    func pixelBorder(
        color: Color = DeskRPGTheme.ink,
        width: CGFloat = DeskRPGTheme.borderWidth,
        radius: CGFloat = DeskRPGTheme.dialogRadius
    ) -> some View {
        modifier(PixelBorder(color: color, width: width, radius: radius))
    }
}
