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
        let schema = Schema([Note.self, Tag.self, Attachment.self])
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
                // Tint (selection, controls) follows the mood's accent…
                .tint(themeManager.theme.accent)
                // …and the whole window goes light/dark to match the mood.
                .preferredColorScheme(themeManager.theme.colorScheme)
                // Make the app icon follow the mood: iOS swaps the bundled
                // alternate home-screen icon; macOS re-renders the live Dock icon.
                // `.task(id:)` runs at launch and again whenever the theme changes.
                .task(id: themeManager.theme) {
                    AppIcon.apply(mood: themeManager.mood, theme: themeManager.theme)
                }
        }
        // Inject the (CloudKit-backed) container; views read it via `@Query`
        // and `@Environment(\.modelContext)`.
        .modelContainer(modelContainer)
        #if os(macOS)
        // Merge the toolbar into the title bar so there's no tall, empty title
        // strip above the content. Settings is the in-window slide-over (opened
        // from the toolbar), so there's no separate `Settings` window.
        .windowToolbarStyle(.unifiedCompact)
        #endif
    }
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
    static func apply(mood: Mood, theme: Theme) {
        #if canImport(UIKit)
        guard UIApplication.shared.supportsAlternateIcons else { return }
        // `paper` is the primary AppIcon (nil); the others are alternates whose
        // names match the appiconset names in the asset catalog.
        let name: String? = (mood == .paper) ? nil : "AppIcon\(mood.rawValue.capitalized)"
        guard UIApplication.shared.alternateIconName != name else { return }
        UIApplication.shared.setAlternateIconName(name)
        #elseif canImport(AppKit)
        let renderer = ImageRenderer(content: AppIconArt(theme: theme).frame(width: 512, height: 512))
        renderer.scale = 2
        if let cg = renderer.cgImage {
            NSApp.applicationIconImage = NSImage(cgImage: cg, size: NSSize(width: 512, height: 512))
        }
        #endif
    }
}

/// The app icon drawn in SwiftUI: a rounded accent tile with the mood's title "P"
/// (matching the in-app brand mark). Used to render the macOS Dock icon live.
struct AppIconArt: View {
    let theme: Theme

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let inset = s * 0.10                    // transparent margin for the Dock
            let side = s - inset * 2
            RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)
                .fill(theme.accent)
                .frame(width: side, height: side)
                .overlay(
                    Text("P")
                        .font(theme.titleFont(side * 0.62))
                        .foregroundStyle(.white)
                )
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }
}
