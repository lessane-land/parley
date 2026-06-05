import SwiftUI
import SwiftData

/// The app entry point. `@main` tells Swift this struct boots the app.
///
/// A SwiftUI `App` has no `main()` and no AppDelegate; its `body` is a tree of
/// `Scene`s. On iOS/iPadOS a `WindowGroup` is the app's window; on macOS it's a
/// document-style window the user can open more than one of.
@main
struct ParleyApp: App {
    /// The shared appearance state. `@State` here means the App owns this single
    /// instance for the app's lifetime; we inject it into every scene below.
    @State private var themeManager = ThemeManager()

    var body: some Scene {
        WindowGroup {
            NoteListView()
                // Make the manager available to every view via the environment.
                .environment(themeManager)
                // Tint (selection, controls) follows the mood's accent…
                .tint(themeManager.theme.accent)
                // …and the whole window goes light/dark to match the mood.
                .preferredColorScheme(themeManager.theme.colorScheme)
        }
        // `.modelContainer(for:)` is the heart of the SwiftData setup. It builds
        // the schema from `Note`, opens a local on-disk store (no CloudKit yet),
        // and injects a `ModelContext` into the environment for `@Query` and
        // `@Environment(\.modelContext)`. CloudKit later is a change *here only*.
        .modelContainer(for: Note.self)

        #if os(macOS)
        // On macOS, preferences live under the app menu (Parley ▸ Settings…, Cmd-,)
        // via the dedicated `Settings` scene — not a sheet. Same `themeManager`
        // instance, so changes here update the main window live.
        Settings {
            SettingsView()
                .environment(themeManager)
                .tint(themeManager.theme.accent)
                .preferredColorScheme(themeManager.theme.colorScheme)
                .frame(width: 460, height: 560)
        }
        #endif
    }
}
