import SwiftUI

/// Convenience initializer so we can paste the design's hex codes verbatim.
/// SwiftUI's `Color` has no hex initializer of its own, so this is a common
/// first thing to add. `opacity` lets us express the design's `rgba(...)` lines.
extension Color {
    init(hex: String, opacity: Double = 1) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let r, g, b: Double
        switch cleaned.count {
        case 3: // #RGB
            r = Double((value >> 8) & 0xF) / 15
            g = Double((value >> 4) & 0xF) / 15
            b = Double(value & 0xF) / 15
        default: // #RRGGBB
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

/// Tiny color-math helpers mirroring the design's `pkMix` / `pkRgba`. The mood
/// system derives an accent's ink/tint/line variants by mixing the chosen
/// accent with white/black/paper — these reproduce that exactly so colors match
/// the prototype.
enum PK {
    static func components(_ hex: String) -> (Double, Double, Double) {
        let s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let n = s.count == 3 ? s.map { "\($0)\($0)" }.joined() : s
        var v: UInt64 = 0
        Scanner(string: n).scanHexInt64(&v)
        return (Double((v >> 16) & 0xFF), Double((v >> 8) & 0xFF), Double(v & 0xFF))
    }

    /// Linear blend of two hex colors, `t` in 0…1 (0 = a, 1 = b). Returns hex.
    static func mix(_ a: String, _ b: String, _ t: Double) -> String {
        let A = components(a), B = components(b)
        func ch(_ x: Double, _ y: Double) -> Int { Int((x + (y - x) * t).rounded()) }
        return String(format: "#%02X%02X%02X", ch(A.0, B.0), ch(A.1, B.1), ch(A.2, B.2))
    }

    static func color(_ hex: String) -> Color { Color(hex: hex) }
    static func rgba(_ hex: String, _ a: Double) -> Color { Color(hex: hex, opacity: a) }

    /// Perceived-luminance test so a checkmark drawn over a swatch reads on both
    /// light and dark colors (same heuristic as the design's tweak panel).
    static func isLight(_ hex: String) -> Bool {
        let (r, g, b) = components(hex)
        return r * 299 + g * 587 + b * 114 > 148000
    }
}
