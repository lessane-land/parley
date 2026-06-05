import SwiftUI
import SwiftData

/// The app entry point. `@main` tells Swift this struct boots the app.
///
/// A SwiftUI `App` has no `main()` and no AppDelegate; its `body` is a tree of
/// `Scene`s (here, one `WindowGroup`). On iOS/iPadOS a `WindowGroup` is the app's
/// window; on macOS it's a document-style window the user can open more than one of.
@main
struct ParleyApp: App {
    var body: some Scene {
        WindowGroup {
            NoteListView()
        }
        // `.modelContainer(for:)` is the heart of the SwiftData setup. It:
        //   1. Builds the schema from the `Note` model,
        //   2. Creates an on-disk SQLite store (local only — no CloudKit yet),
        //   3. Injects a `ModelContext` into the SwiftUI environment so every
        //      view below can read/write via `@Query` and `@Environment(\.modelContext)`.
        // One container per app is the norm. CloudKit sync gets enabled later by
        // configuring this container — the rest of the app won't have to change.
        .modelContainer(for: Note.self)
    }
}
