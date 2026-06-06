import SwiftUI

/// Holds the user's appearance choices and persists them.
///
/// `@Observable` (the modern replacement for `ObservableObject`) makes this a
/// class SwiftUI watches: any view that reads a property here re-renders when it
/// changes. We use one shared instance, injected into the environment, so every
/// scene — the main window *and* the macOS Settings window — reads/writes the
/// same state.
///
/// The customization model mirrors the design's Tweaks panel: a base **mood**
/// plus per-mood overrides (accent, highlight, paper warmth, type face), a
/// **density**, and a **handwriting** toggle. `theme` resolves all of that into
/// the concrete `Theme` tokens the views consume.
@Observable
final class ThemeManager {
    var mood: Mood {
        didSet {
            UserDefaults.standard.set(mood.rawValue, forKey: Self.moodKey)
            // Switching mood resets its dependent options to that mood's
            // defaults, so a value chosen under one mood never leaks into another
            // (matches the design's `pickMood`).
            accentHex = nil
            highlightHex = nil
            faceName = nil
        }
    }

    /// Chosen accent hex, or `nil` to use the mood's default.
    var accentHex: String? { didSet { persist(accentHex, Self.accentKey) } }
    /// Chosen highlight hex (moods that offer it), or `nil` for the default.
    var highlightHex: String? { didSet { persist(highlightHex, Self.highlightKey) } }
    /// Chosen type face name, or `nil` for the mood default.
    var faceName: String? { didSet { persist(faceName, Self.faceKey) } }
    /// Paper warmth 0…100 (paper mood only).
    var warmth: Double { didSet { UserDefaults.standard.set(warmth, forKey: Self.warmthKey) } }
    /// Whether the iPad handwriting canvas is shown.
    var handwriting: Bool { didSet { UserDefaults.standard.set(handwriting, forKey: Self.handwritingKey) } }

    /// Whether to recognize enrolled voices and auto-label them across meetings.
    var recognizeSpeakers: Bool { didSet { UserDefaults.standard.set(recognizeSpeakers, forKey: Self.recognizeSpeakersKey) } }

    /// macOS only: also capture system audio (the meeting's far side) when
    /// recording, so the transcript includes the other participants. Needs Screen
    /// Recording permission.
    var captureSystemAudio: Bool { didSet { UserDefaults.standard.set(captureSystemAudio, forKey: Self.captureSystemAudioKey) } }

    var density: Density { didSet { UserDefaults.standard.set(density.rawValue, forKey: Self.densityKey) } }

    /// Dashboard note-card size (Small / Medium / Large).
    var cardSize: CardSize { didSet { UserDefaults.standard.set(cardSize.rawValue, forKey: Self.cardSizeKey) } }
    /// Whether pinned notes show as a big wide "feature" card. Off = pinned notes
    /// sit in the grid at normal size (just styled as pinned).
    var featurePinned: Bool { didSet { UserDefaults.standard.set(featurePinned, forKey: Self.featurePinnedKey) } }

    /// Preferred transcription language as a language code ("es"), or `nil` for
    /// Automatic (follow the device's preferred languages). Not an appearance
    /// setting, but this is the app's single persisted-preferences store.
    var transcriptionLanguage: String? { didSet { persist(transcriptionLanguage, Self.languageKey) } }

    /// Note-detail layout, persisted so the arrangement sticks across notes and
    /// launches: whether the transcript leads (panels swapped) and how the space
    /// is divided (size of the leading panel, 0.2…0.8).
    var layoutSwapped: Bool { didSet { UserDefaults.standard.set(layoutSwapped, forKey: Self.layoutSwappedKey) } }
    var splitFraction: Double { didSet { UserDefaults.standard.set(splitFraction, forKey: Self.splitFractionKey) } }

    // MARK: AI & Summarize (the design's Settings ▸ AI section)

    /// Draft a summary automatically the moment a recording stops.
    var autoSummarize: Bool { didSet { UserDefaults.standard.set(autoSummarize, forKey: Self.autoSummarizeKey) } }
    /// How terse/verbose the generated summary should be.
    var summaryTone: SummaryTone { didSet { UserDefaults.standard.set(summaryTone.rawValue, forKey: Self.summaryToneKey) } }
    /// Which structured pieces the summary should always pull out.
    var extractDecisions: Bool { didSet { UserDefaults.standard.set(extractDecisions, forKey: Self.extractDecisionsKey) } }
    var extractActionItems: Bool { didSet { UserDefaults.standard.set(extractActionItems, forKey: Self.extractActionItemsKey) } }
    var extractOpenQuestions: Bool { didSet { UserDefaults.standard.set(extractOpenQuestions, forKey: Self.extractOpenQuestionsKey) } }
    var extractKeyQuotes: Bool { didSet { UserDefaults.standard.set(extractKeyQuotes, forKey: Self.extractKeyQuotesKey) } }

    /// The fully resolved tokens for the current mood + overrides. Views read
    /// `themeManager.theme`.
    var theme: Theme {
        var t = mood.theme
        let cfg = mood.config

        // — Type face —
        let face = faceName ?? cfg.faceDefault
        let fonts = faceFonts(face)
        t.titleFontName = fonts.title
        if cfg.faceAffectsBody { t.bodyFontName = fonts.body }

        // — Paper warmth (paper mood): cool off-white → cream —
        var paperHex: String? = nil
        if cfg.hasWarmth {
            let p = PK.mix("#F8F4EC", "#F1E3C4", warmth / 100)
            paperHex = p
            t.paper = PK.color(p)
            t.paperRaised = PK.color(PK.mix(p, "#FFFFFF", 0.42))
            t.paperSunk = PK.color(PK.mix(p, "#5A5036", 0.07))
            t.edge = PK.color(PK.mix(p, "#5A5036", 0.16))
        }

        // — Accent family (mood-aware derivation) —
        let accent = accentHex ?? cfg.accentDefault
        let highlight = highlightHex ?? cfg.highlightDefault ?? accent
        t.accent = PK.color(accent)
        t.rec = PK.color(accent)
        t.accentLine = PK.rgba(accent, 0.34)
        switch mood {
        case .terminal:
            t.accentInk = PK.color(PK.mix(accent, "#FFFFFF", 0.22))
            t.accentTint = PK.color(PK.mix("#141A24", accent, 0.16))
        case .neubrutalist:
            t.accentInk = PK.color(PK.mix(accent, "#000000", 0.18))
            t.accentTint = PK.color(highlight)     // the single loud highlight
            t.accentLine = PK.color("#1A1A1A")     // borders stay black
        case .swiss:
            t.accentInk = PK.color(PK.mix(accent, "#000000", 0.16))
            t.accentTint = PK.color(PK.mix("#FFFFFF", accent, 0.10))
        case .paper:
            let base = paperHex ?? "#F4EFE6"
            t.accentInk = PK.color(PK.mix(accent, "#1A1812", 0.28))
            t.accentTint = PK.color(PK.mix(base, accent, 0.13))
        }
        return t
    }

    // MARK: Persistence

    private static let moodKey = "parley.mood"
    private static let accentKey = "parley.accent"
    private static let highlightKey = "parley.highlight"
    private static let faceKey = "parley.face"
    private static let warmthKey = "parley.warmth"
    private static let handwritingKey = "parley.handwriting"
    private static let recognizeSpeakersKey = "parley.recognizeSpeakers"
    private static let captureSystemAudioKey = "parley.captureSystemAudio"
    private static let cardSizeKey = "parley.cardSize"
    private static let featurePinnedKey = "parley.featurePinned"
    private static let densityKey = "parley.density"
    private static let languageKey = "parley.transcriptionLanguage"
    private static let layoutSwappedKey = "parley.layoutSwapped"
    private static let splitFractionKey = "parley.splitFraction"
    private static let autoSummarizeKey = "parley.autoSummarize"
    private static let summaryToneKey = "parley.summaryTone"
    private static let extractDecisionsKey = "parley.extractDecisions"
    private static let extractActionItemsKey = "parley.extractActionItems"
    private static let extractOpenQuestionsKey = "parley.extractOpenQuestions"
    private static let extractKeyQuotesKey = "parley.extractKeyQuotes"

    private func persist(_ value: String?, _ key: String) {
        let d = UserDefaults.standard
        if let value { d.set(value, forKey: key) } else { d.removeObject(forKey: key) }
    }

    init() {
        let d = UserDefaults.standard
        // Assigning in `init` does not fire the `didSet` observers, so we don't
        // write defaults back on first launch.
        mood = Mood(rawValue: d.string(forKey: Self.moodKey) ?? "") ?? .paper
        accentHex = d.string(forKey: Self.accentKey)
        highlightHex = d.string(forKey: Self.highlightKey)
        faceName = d.string(forKey: Self.faceKey)
        warmth = d.object(forKey: Self.warmthKey) as? Double ?? 38
        handwriting = d.object(forKey: Self.handwritingKey) as? Bool ?? true
        recognizeSpeakers = d.object(forKey: Self.recognizeSpeakersKey) as? Bool ?? true
        captureSystemAudio = d.object(forKey: Self.captureSystemAudioKey) as? Bool ?? true
        density = Density(rawValue: d.string(forKey: Self.densityKey) ?? "") ?? .regular
        cardSize = CardSize(rawValue: d.string(forKey: Self.cardSizeKey) ?? "") ?? .regular
        featurePinned = d.object(forKey: Self.featurePinnedKey) as? Bool ?? true
        transcriptionLanguage = d.string(forKey: Self.languageKey)
        layoutSwapped = d.object(forKey: Self.layoutSwappedKey) as? Bool ?? false
        splitFraction = d.object(forKey: Self.splitFractionKey) as? Double ?? 0.5
        autoSummarize = d.object(forKey: Self.autoSummarizeKey) as? Bool ?? true
        summaryTone = SummaryTone(rawValue: d.string(forKey: Self.summaryToneKey) ?? "") ?? .balanced
        extractDecisions = d.object(forKey: Self.extractDecisionsKey) as? Bool ?? true
        extractActionItems = d.object(forKey: Self.extractActionItemsKey) as? Bool ?? true
        extractOpenQuestions = d.object(forKey: Self.extractOpenQuestionsKey) as? Bool ?? true
        extractKeyQuotes = d.object(forKey: Self.extractKeyQuotesKey) as? Bool ?? false
    }
}

/// How verbose the on-device summary should be (Settings ▸ AI ▸ Summary tone).
enum SummaryTone: String, CaseIterable, Identifiable {
    case brief, balanced, detailed
    var id: String { rawValue }
    var name: String { rawValue.capitalized }

    /// A line folded into the model instructions.
    var guidance: String {
        switch self {
        case .brief: "Be very concise — short phrases, only the essentials."
        case .balanced: "Be concise but complete."
        case .detailed: "Be thorough; capture nuance and context."
        }
    }
}

/// Dashboard note-card size. Drives the grid's column width and each card's height
/// so the user can make cards smaller or larger.
enum CardSize: String, CaseIterable, Identifiable {
    case compact, regular, large
    var id: String { rawValue }

    var name: String {
        switch self {
        case .compact: "Small"
        case .regular: "Medium"
        case .large:   "Large"
        }
    }

    /// SF Symbol for the size control.
    var icon: String {
        switch self {
        case .compact: "square.grid.3x3"
        case .regular: "square.grid.2x2"
        case .large:   "square"
        }
    }

    /// Minimum grid column width (adaptive columns).
    var columnMin: CGFloat {
        switch self {
        case .compact: 190
        case .regular: 240
        case .large:   300
        }
    }

    /// Standard card height.
    var cardHeight: CGFloat {
        switch self {
        case .compact: 150
        case .regular: 188
        case .large:   240
        }
    }

    /// Pinned ("feature") card height — a bit taller.
    var featureHeight: CGFloat {
        switch self {
        case .compact: 170
        case .regular: 210
        case .large:   270
        }
    }
}
