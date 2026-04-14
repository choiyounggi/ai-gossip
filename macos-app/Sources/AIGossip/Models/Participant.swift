import Foundation
import SwiftUI

/// A chat-room participant backed by a Phase-1 public profile.
struct Participant: Identifiable, Hashable {
    let id: String           // userId from the server
    let userName: String     // display name (may be the same as id)
    let publicProfile: String // raw YAML, for tooltip / details panel
    let avatarEmoji: String  // deterministic from userId
    let accentHue: Double    // 0.0 … 1.0, deterministic from userId

    init(id: String, userName: String, publicProfile: String) {
        self.id = id
        self.userName = userName
        self.publicProfile = publicProfile
        self.avatarEmoji = Self.pickEmoji(seed: id)
        self.accentHue = Self.pickHue(seed: id)
    }

    /// Color computed from the accent hue. Re-derived so themes can tweak
    /// saturation/brightness globally without touching participants.
    func accentColor(saturation: Double = 0.55, brightness: Double = 0.70) -> Color {
        Color(hue: accentHue, saturation: saturation, brightness: brightness)
    }

    private static let emojiPool: [String] = [
        "🧑‍💻", "👩‍💻", "🧙", "🧝", "🤖", "👾", "🐧", "🦊",
        "🐱", "🐼", "🦉", "🐸", "🧛", "🧚", "🧞", "🐺",
    ]

    private static func pickEmoji(seed: String) -> String {
        let hash = stableHash(seed)
        return emojiPool[Int(hash % UInt64(emojiPool.count))]
    }

    private static func pickHue(seed: String) -> Double {
        // Append a constant suffix so color derivation doesn't collide with emoji.
        let hash = stableHash(seed + "#hue")
        return Double(hash % 360) / 360.0
    }

    /// FNV-1a — deterministic across platforms. Swift's built-in `hashValue`
    /// is randomized per run, which we don't want for user color/avatar.
    private static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x100000001b3
        }
        return h
    }
}

