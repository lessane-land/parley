import CoreGraphics

/// Transcript / note text density — the design's `.density-*` variants.
/// Affects the user's note text size and line spacing. (In later phases this
/// also drives the live transcript feed.)
enum Density: String, CaseIterable, Identifiable {
    case compact
    case regular
    case comfy

    var id: String { rawValue }

    var name: String {
        switch self {
        case .compact: "Compact"
        case .regular: "Regular"
        case .comfy:   "Comfortable"
        }
    }

    /// Base text point size (from `--pk-tx-size`).
    var bodySize: CGFloat {
        switch self {
        case .compact: 14
        case .regular: 15.5
        case .comfy:   17
        }
    }

    /// SwiftUI's `lineSpacing` is *extra* space added between lines, whereas the
    /// design uses a CSS line-height multiplier (`--pk-tx-lead`). We approximate:
    /// extra ≈ size × (lead − 1).
    var lineSpacing: CGFloat {
        switch self {
        case .compact: 6
        case .regular: 8
        case .comfy:   11
        }
    }
}
