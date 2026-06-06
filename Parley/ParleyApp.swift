import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// The app entry point. `@main` tells Swift this struct boots the app.
///
/// A SwiftUI `App` has no `main()` and no AppDelegate; its `body` is a tree of
/// `Scene`s. On iOS/iPadOS a `WindowGroup` is the app's window; on macOS it's a
/// document-style window the user can open more than one of.
@main
struct ParleyApp: App {
    /// The shared appearance state. `@State` here means the App owns this single
    /// instance for the app's lifetime; we inject it into every scene below.
    @State private var themeManager: ThemeManager

    /// Calendar + Reminders, shared so the list (meetings) and the detail
    /// (action items → reminders) use one access grant.
    @State private var eventKit = EventKitService()

    /// The SwiftData store — now CloudKit-backed for cross-device sync.
    private let modelContainer: ModelContainer

    /// Reports CloudKit sync activity to the UI.
    @State private var syncMonitor: SyncMonitor

    /// Lets the macOS menu-bar item ask the main window to start a new recording.
    @State private var recordLauncher = RecordLauncher()

    init() {
        // Register the bundled fonts before any view renders, so custom faces
        // are available on first paint. Then build the shared theme state.
        AppFonts.registerAll()
        _themeManager = State(initialValue: ThemeManager())

        let (container, cloudEnabled, reason) = Self.makeModelContainer()
        modelContainer = container
        _syncMonitor = State(initialValue: SyncMonitor(cloudEnabled: cloudEnabled, fallbackReason: reason))
    }

    /// Builds the SwiftData container with CloudKit sync (private database), and
    /// falls back to a local-only store if CloudKit isn't available — so the app
    /// always launches even before iCloud/entitlements are fully provisioned.
    /// Returns whether CloudKit actually started, for the sync indicator.
    ///
    /// SwiftData syncs via CloudKit when the model is CloudKit-compatible (all
    /// properties optional or defaulted, no unique constraints — which `Note`
    /// satisfies) and the iCloud + CloudKit entitlements are present. `.automatic`
    /// uses the container declared in the entitlements.
    private static func makeModelContainer() -> (ModelContainer, Bool, String?) {
        let schema = Schema([Note.self, Tag.self, Attachment.self, SpeakerProfile.self])
        let cloudConfig = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
        do {
            let container = try ModelContainer(for: schema, configurations: cloudConfig)
            return (container, true, nil)
        } catch {
            // CloudKit unavailable (not signed in, no entitlement yet, Simulator,
            // or a model that isn't CloudKit-compatible): keep working locally, but
            // carry the reason so the sync chip can explain instead of going quiet.
            let reason = error.localizedDescription
            let localConfig = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            let container = (try? ModelContainer(for: schema, configurations: localConfig))
                ?? (try! ModelContainer(for: schema))
            return (container, false, reason)
        }
    }

    var body: some Scene {
        WindowGroup {
            NoteListView()
                // Make the managers available to every view via the environment.
                .environment(themeManager)
                .environment(eventKit)
                .environment(syncMonitor)
                .environment(recordLauncher)
                // Tint (selection, controls) follows the mood's accent…
                .tint(themeManager.theme.accent)
                // …and the whole window goes light/dark to match the mood.
                .preferredColorScheme(themeManager.theme.colorScheme)
                // Make the app icon follow the mood: iOS swaps the bundled
                // alternate home-screen icon; macOS re-renders the live Dock icon.
                // `.task(id:)` runs at launch and again whenever the theme changes.
                .task(id: themeManager.mood) {
                    AppIcon.apply(mood: themeManager.mood)
                }
        }
        // Inject the (CloudKit-backed) container; views read it via `@Query`
        // and `@Environment(\.modelContext)`.
        .modelContainer(modelContainer)
        // Merge the toolbar into the title bar so there's no tall, empty title
        // strip above the content. Settings is the in-window slide-over (opened
        // from the toolbar), so there's no separate `Settings` window.
        // NOTE: this is a *postfix* `#if` (a conditional modifier on WindowGroup),
        // so it can only contain `.modifier` lines — a new scene can't live here.
        #if os(macOS)
        .windowToolbarStyle(.unifiedCompact)
        #endif

        // A menu-bar item so a meeting can be captured without hunting for the
        // window: click it and "New Recording" creates a note and starts recording.
        // This is a separate `#if` because it introduces a *new scene*, not a modifier.
        #if os(macOS)
        MenuBarExtra("Parley", systemImage: "waveform") {
            Button("New Recording") {
                recordLauncher.requestNewRecording()
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            Divider()
            Button("Open Parley") { NSApp.activate(ignoringOtherApps: true) }
            Button("Quit Parley") { NSApplication.shared.terminate(nil) }
        }
        #endif
    }
}

/// A tiny app-level signal so the macOS menu-bar item can ask the main window to
/// start a new recording. The menu bar lives in its own scene and can't reach the
/// note list's navigation state directly, so it bumps `requestTick`; `NoteListView`
/// observes the change and runs its normal "create note + record" flow.
@Observable
final class RecordLauncher {
    private(set) var requestTick = 0
    func requestNewRecording() { requestTick += 1 }
}

/// Switches the app icon to match the current mood.
///
/// The two platforms differ: on iOS/iPadOS the home-screen icon must be a
/// **pre-bundled** image, so we ship one alternate app icon per mood and call
/// `setAlternateIconName`. On macOS the Finder icon can't change at runtime, but
/// the **Dock** icon can — and we render it straight from `AppIconArt`, so it
/// always matches the live mood and accent (even a custom one).
enum AppIcon {
    @MainActor
    static func apply(mood: Mood) {
        #if canImport(UIKit)
        guard UIApplication.shared.supportsAlternateIcons else { return }
        // `paper` is the primary AppIcon (nil); the others are alternates whose
        // names match the appiconset names in the asset catalog.
        let name: String? = (mood == .paper) ? nil : "AppIcon\(mood.rawValue.capitalized)"
        guard UIApplication.shared.alternateIconName != name else { return }
        UIApplication.shared.setAlternateIconName(name)
        #elseif canImport(AppKit)
        // Render the live Dock icon from the same design view the Settings grid
        // uses, so it matches the artwork (and the current mood) exactly.
        let renderer = ImageRenderer(content: AppIconView(mood: mood, size: 512))
        renderer.scale = 2
        guard let cg = renderer.cgImage else { return }
        let image = NSImage(cgImage: cg, size: NSSize(width: 512, height: 512))
        NSApp.applicationIconImage = image
        // Assigning `applicationIconImage` alone often doesn't repaint the Dock —
        // set the tile's contents and force a redraw so the mood icon actually shows.
        NSApp.dockTile.contentView = NSImageView(image: image)
        NSApp.dockTile.display()
        #endif
    }
}
