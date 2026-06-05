import SwiftUI

/// The selectable "moods" from the design. Each maps to a complete `Theme`.
///
/// `String`-backed so we can persist the choice by `rawValue`. `CaseIterable`
/// gives us `Mood.allCases` to render the Settings list. `Identifiable` lets
/// SwiftUI's `ForEach` track them.
enum Mood: String, CaseIterable, Identifiable {
    case paper
    case terminal
    case swiss
    case neubrutalist

    var id: String { rawValue }

    var name: String {
        switch self {
        case .paper:        "Paper"
        case .terminal:     "Terminal"
        case .swiss:        "Swiss"
        case .neubrutalist: "Neubrutalist"
        }
    }

    var blurb: String {
        switch self {
        case .paper:        "Warm, calm, editorial. The default."
        case .terminal:     "Dark, monospaced, heads-down focus."
        case .swiss:        "Stark white, red accent, grid-tight."
        case .neubrutalist: "Bold blocks, hard shadows, a lime pop."
        }
    }

    // NOTE ON FONTS: the design names specific typefaces per mood — Newsreader
    // (serif), Hanken/Space Grotesk and Archivo (grotesk sans), IBM Plex Mono.
    // Those aren't system fonts. Rather than ship ~6 font families before we
    // need them, each theme below expresses the *role* (serif vs. grotesk vs.
    // mono) via `Font.Design`, which the system fonts approximate well. When you
    // want pixel-faithful type, drop the .ttf/.otf files into the app, register
    // them in Info.plist, and we swap these `Font.Design` roles for the real
    // family names — the rest of the app won't change.
    var theme: Theme {
        switch self {
        case .paper:
            Theme(
                paper:       Color(hex: "F6F2E9"),
                paperRaised: Color(hex: "FBF8F1"),
                paperSunk:   Color(hex: "EFE9DD"),
                edge:        Color(hex: "E4DCCB"),
                ink:         Color(hex: "2A2620"),
                ink2:        Color(hex: "4A443B"),
                inkSoft:     Color(hex: "6E675B"),
                inkFaint:    Color(hex: "A39A89"),
                inkGhost:    Color(hex: "C7BEAD"),
                line:        Color(hex: "2A2620", opacity: 0.10),
                accent:      Color(hex: "3E5C50"),
                accentInk:   Color(hex: "324A40"),
                accentTint:  Color(hex: "E8EEEA"),
                accentLine:  Color(hex: "3E5C50", opacity: 0.32),
                rec:         Color(hex: "B14B3A"),
                cornerRadius: 14,
                borderWidth: 1,
                shadow: ThemeShadow(color: Color(hex: "2A2620", opacity: 0.06), radius: 2, x: 0, y: 1),
                titleDesign: .serif,
                titleWeight: .semibold,
                noteDesign: .serif,
                transcriptDesign: .default,
                colorScheme: .light
            )

        case .terminal:
            Theme(
                paper:       Color(hex: "0B0E14"),
                paperRaised: Color(hex: "141A24"),
                paperSunk:   Color(hex: "0F141C"),
                edge:        Color(hex: "2A3441"),
                ink:         Color(hex: "E4EAF2"),
                ink2:        Color(hex: "C8D2E0"),
                inkSoft:     Color(hex: "8A97A8"),
                inkFaint:    Color(hex: "5C6878"),
                inkGhost:    Color(hex: "2A3441"),
                line:        Color(hex: "1F2630"),
                accent:      Color(hex: "FF9F1C"),
                accentInk:   Color(hex: "FFB84D"),
                accentTint:  Color(hex: "1C2230"),
                accentLine:  Color(hex: "FF9F1C", opacity: 0.34),
                rec:         Color(hex: "FF9F1C"),
                cornerRadius: 0,
                borderWidth: 1,
                shadow: nil,
                titleDesign: .default,
                titleWeight: .medium,
                noteDesign: .default,
                transcriptDesign: .monospaced, // IBM Plex Mono transcript
                colorScheme: .dark
            )

        case .swiss:
            Theme(
                paper:       Color(hex: "FFFFFF"),
                paperRaised: Color(hex: "FFFFFF"),
                paperSunk:   Color(hex: "F4F4F4"),
                edge:        Color(hex: "111111"),
                ink:         Color(hex: "111111"),
                ink2:        Color(hex: "1A1A1A"),
                inkSoft:     Color(hex: "555555"),
                inkFaint:    Color(hex: "8A8A8A"),
                inkGhost:    Color(hex: "C8C8C8"),
                line:        Color(hex: "111111"),
                accent:      Color(hex: "E2231A"),
                accentInk:   Color(hex: "C01810"),
                accentTint:  Color(hex: "FBE7E6"),
                accentLine:  Color(hex: "E2231A", opacity: 0.40),
                rec:         Color(hex: "E2231A"),
                cornerRadius: 0,
                borderWidth: 1,
                shadow: nil,
                titleDesign: .default,
                titleWeight: .bold,
                noteDesign: .default,
                transcriptDesign: .default,
                colorScheme: .light
            )

        case .neubrutalist:
            Theme(
                paper:       Color(hex: "F5F3EC"),
                paperRaised: Color(hex: "FFFFFF"),
                paperSunk:   Color(hex: "ECEAE0"),
                edge:        Color(hex: "1A1A1A"),
                ink:         Color(hex: "1A1A1A"),
                ink2:        Color(hex: "1A1A1A"),
                inkSoft:     Color(hex: "44423C"),
                inkFaint:    Color(hex: "6E6B60"),
                inkGhost:    Color(hex: "1A1A1A"),
                line:        Color(hex: "1A1A1A"),
                accent:      Color(hex: "2B4BF2"),
                accentInk:   Color(hex: "1E36C0"),
                accentTint:  Color(hex: "D8F000"), // the single lime highlight
                accentLine:  Color(hex: "1A1A1A"),
                rec:         Color(hex: "2B4BF2"),
                cornerRadius: 0,
                borderWidth: 2,
                shadow: ThemeShadow(color: Color(hex: "1A1A1A"), radius: 0, x: 4, y: 4),
                titleDesign: .default,
                titleWeight: .heavy,
                noteDesign: .default,
                transcriptDesign: .default,
                colorScheme: .light
            )
        }
    }
}
