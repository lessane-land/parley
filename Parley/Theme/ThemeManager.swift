import SwiftUI

/// Holds the user's appearance choices and persists them.
///
/// `@Observable` (the modern replacement for `ObservableObject`) makes this a
/// class SwiftUI watches: any view that reads `mood` or `density` automatically
/// re-renders when they change. We use a single shared instance, injected into
/// the environment, so every scene — the main window *and* the macOS Settings
/// window — reads and writes the same state.
///
/// Why a manager instead of `@AppStorage`? `@AppStorage` is a per-view property
/// wrapper; it doesn't share cleanly across multiple scenes. A small `@Observable`
/// model that mirrors `UserDefaults` does, and keeps persistence in one place.
@Observable
final class ThemeManager {
    var mood: Mood {
        didSet { UserDefaults.standard.set(mood.rawValue, forKey: Self.moodKey) }
    }

    var density: Density {
        didSet { UserDefaults.standard.set(density.rawValue, forKey: Self.densityKey) }
    }

    /// The resolved tokens for the current mood. Views read `themeManager.theme`.
    var theme: Theme { mood.theme }

    private static let moodKey = "parley.mood"
    private static let densityKey = "parley.density"

    init() {
        let defaults = UserDefaults.standard
        // Note: assigning in `init` does not trigger the `didSet` observers above,
        // so we don't write the defaults back on first launch — exactly what we want.
        mood = Mood(rawValue: defaults.string(forKey: Self.moodKey) ?? "") ?? .paper
        density = Density(rawValue: defaults.string(forKey: Self.densityKey) ?? "") ?? .regular
    }
}
