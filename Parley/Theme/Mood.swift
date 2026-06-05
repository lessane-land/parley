import SwiftUI

/// The selectable "moods" from the design. Each maps to a complete `Theme`.
///
/// `String`-backed so we can persist the choice by `rawValue`. `CaseIterable`
/// gives us `Mood.allCases` to render the Settings list. `Identifiable` lets
/// SwiftUI's `ForEach` track them.
///
/// The fonts named below are the real typefaces from the design, bundled and
/// registered at launch (see AppFonts / Parley/Fonts). We reference each weight
/// by its exact PostScript name so the right face is always used.
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

    var theme: Theme {
        switch self {
        case .paper:
            // Editorial paper: Newsreader serif headings + body, forest accent.
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
                grid: ThemeGrid.none,
                titleFontName: "Newsreader-SemiBold",
                bodyFontName:  "Newsreader-Regular",
                monoFontName:  "IBMPlexMono-Regular",
                titleTracking: -0.3,
                titleUppercase: false,
                colorScheme: .light
            )

        case .terminal:
            // Engineered terminal: Space Grotesk + IBM Plex Mono, amber on near-black.
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
                grid: ThemeGrid.squares(64),
                titleFontName: "SpaceGrotesk-Medium",
                bodyFontName:  "SpaceGrotesk-Regular",
                monoFontName:  "IBMPlexMono-Regular", // IBM Plex Mono transcript/labels
                titleTracking: 0.2,
                titleUppercase: false,
                colorScheme: .dark
            )

        case .swiss:
            // Swiss international: Archivo neo-grotesque, signal red, uppercase heads.
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
                grid: ThemeGrid.columns(6),
                titleFontName: "Archivo-Bold",
                bodyFontName:  "Archivo-Regular",
                monoFontName:  "IBMPlexMono-Regular",
                titleTracking: -0.5,
                titleUppercase: true,
                colorScheme: .light
            )

        case .neubrutalist:
            // Neubrutalist: Archivo ExtraBold heads + Space Grotesk body, blue + lime.
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
                grid: ThemeGrid.none,
                titleFontName: "Archivo-ExtraBold",
                bodyFontName:  "SpaceGrotesk-Regular",
                monoFontName:  "IBMPlexMono-Regular",
                titleTracking: -0.3,
                titleUppercase: false,
                colorScheme: .light
            )
        }
    }

    /// The customization options each mood offers — straight from the design's
    /// per-mood config (`PK_MOODS`). These drive the Settings controls.
    var config: MoodConfig {
        switch self {
        case .paper:
            MoodConfig(
                accents: ["#3E5C50", "#8B3A2F", "#C75B39", "#27406B"], accentDefault: "#3E5C50",
                highlights: nil, highlightDefault: nil,
                hasWarmth: true,
                faceLabel: "Note serif",
                faceOptions: ["Newsreader", "Fraunces", "Source Serif 4", "Spectral"],
                faceDefault: "Newsreader", faceAffectsBody: true
            )
        case .terminal:
            MoodConfig(
                accents: ["#FF9F1C", "#36E08B", "#54C7FF", "#FF5C4D"], accentDefault: "#FF9F1C",
                highlights: nil, highlightDefault: nil,
                hasWarmth: false,
                faceLabel: "Interface face",
                faceOptions: ["Space Grotesk", "IBM Plex Mono"], faceDefault: "Space Grotesk", faceAffectsBody: true
            )
        case .swiss:
            MoodConfig(
                accents: ["#E2231A", "#0A5FFF", "#111111", "#FF6A00"], accentDefault: "#E2231A",
                highlights: nil, highlightDefault: nil,
                hasWarmth: false,
                faceLabel: "Grotesque",
                faceOptions: ["Archivo", "Inter"], faceDefault: "Archivo", faceAffectsBody: true
            )
        case .neubrutalist:
            MoodConfig(
                accents: ["#2B4BF2", "#FF4FA3", "#FF6A1A", "#16A34A"], accentDefault: "#2B4BF2",
                highlights: ["#D8F000", "#FFE600", "#00E5FF", "#FF4FA3"], highlightDefault: "#D8F000",
                hasWarmth: false,
                faceLabel: "Display face",
                // Only the bundled faces are offered; the display face changes the
                // title only (the neubrutalist body stays Space Grotesk).
                faceOptions: ["Archivo Black", "Space Grotesk", "Archivo"], faceDefault: "Archivo Black", faceAffectsBody: false
            )
        }
    }
}

/// The set of customization options a mood exposes in Settings.
struct MoodConfig {
    let accents: [String]
    let accentDefault: String
    let highlights: [String]?       // only some moods (neubrutalist)
    let highlightDefault: String?
    let hasWarmth: Bool             // paper offers a warmth slider
    let faceLabel: String
    let faceOptions: [String]
    let faceDefault: String
    let faceAffectsBody: Bool       // does the face change body text too, or title only?
}

/// Maps a design face name to the bundled PostScript names for title + body.
func faceFonts(_ face: String) -> (title: String, body: String) {
    switch face {
    case "Newsreader":      return ("Newsreader-SemiBold", "Newsreader-Regular")
    case "Fraunces":        return ("Fraunces-SemiBold", "Fraunces-Regular")
    case "Source Serif 4":  return ("SourceSerif4-SemiBold", "SourceSerif4-Regular")
    case "Spectral":        return ("Spectral-SemiBold", "Spectral-Regular")
    case "Space Grotesk":   return ("SpaceGrotesk-Medium", "SpaceGrotesk-Regular")
    case "IBM Plex Mono":   return ("IBMPlexMono-Medium", "IBMPlexMono-Regular")
    case "Archivo":         return ("Archivo-Bold", "Archivo-Regular")
    case "Archivo Black":   return ("Archivo-ExtraBold", "Archivo-Regular")
    case "Inter":           return ("Inter-Bold", "Inter-Regular")
    default:                return ("Newsreader-SemiBold", "Newsreader-Regular")
    }
}
