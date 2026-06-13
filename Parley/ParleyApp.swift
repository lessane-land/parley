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

    /// App-level recording so the macOS menu bar can capture a meeting in the
    /// background — no window needed, and it keeps running if the window is closed.
    @State private var recorder = RecordingCoordinator()

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
                .environment(recorder)
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
                #if os(iOS)
                // The toolbar buttons follow `.tint`, but the navigation *back*
                // button follows the window's tint — set it so the back chevron
                // matches the accent like everything else (keeps swipe-to-go-back).
                .task(id: themeManager.theme.accent) {
                    AppChrome.tintWindows(themeManager.theme.accent)
                }
                #endif
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
        // window: click "New Recording" and it records in the *background* (no app
        // activation), into a fresh note. This is a separate `#if` because it
        // introduces a new scene, not a modifier.
        #if os(macOS)
        MenuBarExtra {
            // `.window` style hosts live SwiftUI (a TimelineView), so the dropdown
            // can show a running "Recording mm:ss…" timer.
            MenuBarPanel(
                recorder: recorder,
                startNew: {
                    // No NSApp.activate — capture while staying in the background.
                    recorder.startNewRecording(context: modelContainer.mainContext,
                                               themeManager: themeManager)
                },
                openApp: {
                    NSApp.activate(ignoringOtherApps: true)
                    recorder.requestOpenActiveNote()   // jump to the recording note
                }
            )
        } label: {
            // A filled, red-tinted icon signals an active background recording.
            Image(systemName: recorder.isRecording ? "waveform.circle.fill" : "waveform")
                .symbolRenderingMode(recorder.isRecording ? .multicolor : .monochrome)
        }
        .menuBarExtraStyle(.window)
        #endif
    }
}

#if os(macOS)
/// The macOS menu-bar dropdown panel. A `.window`-style `MenuBarExtra` renders this
/// live, so the recording timer actually ticks.
private struct MenuBarPanel: View {
    let recorder: RecordingCoordinator
    var startNew: () -> Void
    var openApp: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if recorder.isRecording {
                HStack(spacing: 8) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    if let started = recorder.startedAt {
                        TimelineView(.periodic(from: started, by: 1)) { _ in
                            Text("Recording \(elapsed(since: started))…")
                                .font(.headline)
                        }
                    } else {
                        Text("Recording…").font(.headline)
                    }
                }
                if let title = recorder.activeNoteTitle {
                    Text(title).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Button("Stop Recording") { recorder.stop() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            } else {
                Button("New Recording") { startNew() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }

            Divider()
            Button("Open Inkling") { openApp() }
            Button("Quit Inkling") { NSApplication.shared.terminate(nil) }
        }
        .padding(14)
        .frame(width: 250)
    }

    private func elapsed(since start: Date) -> String {
        let s = max(0, Int(Date().timeIntervalSince(start)))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
#endif

/// App-level recording that runs independently of any window, so the macOS menu
/// bar can start capturing a meeting in the background. It owns one transcription
/// session, writes the live transcript onto a note as it streams, and on stop runs
/// speaker ID + (optional) auto-summary — the same finishing steps the in-note
/// recorder does. The note is created in the shared store, so when the user opens
/// the app later the meeting is just there, transcribed.
@MainActor
@Observable
final class RecordingCoordinator {
    private let transcription = TranscriptionService()
    private let summaryService = SummaryService()

    /// The note currently being recorded into (nil when idle). The view layer reads
    /// `activeNoteID` to show a live indicator / route Stop for that note.
    private(set) var activeNoteID: PersistentIdentifier?

    /// Bumped (with the note id) when the menu bar asks the window to jump to the
    /// note that's recording. `NoteListView` observes `openTick` and navigates.
    private(set) var openNoteRequest: PersistentIdentifier?
    private(set) var openTick = 0

    /// Ask the main window to open the active (or most recent) recording note.
    func requestOpenActiveNote() {
        openNoteRequest = activeNoteID
        openTick += 1
    }
    private var activeNote: Note?
    private var context: ModelContext?
    private var themeManager: ThemeManager?
    private var persistTask: Task<Void, Never>?

    var isRecording: Bool { transcription.isRecording }
    var startedAt: Date? { transcription.startedAt }
    var state: TranscriptionService.State { transcription.state }
    var activeNoteTitle: String? {
        activeNote.map { $0.title.isEmpty ? "New recording" : $0.title }
    }

    /// Create a note and begin recording into it in the background.
    func startNewRecording(context: ModelContext, themeManager: ThemeManager) {
        guard !isRecording else { return }
        self.context = context
        self.themeManager = themeManager

        let note = Note(title: "New recording")
        context.insert(note)
        try? context.save()
        activeNote = note
        activeNoteID = note.persistentModelID

        Task {
            #if os(macOS)
            let captureSystem = themeManager.captureSystemAudio
            #else
            let captureSystem = false
            #endif
            await transcription.start(seed: "", seedSegments: [],
                                      preferredLanguage: themeManager.transcriptionLanguage,
                                      captureSystemAudio: captureSystem)
            startPersisting(into: note)
        }
    }

    /// Stop the background session and run the finishing steps.
    func stop() {
        guard isRecording || state == .finishing else { return }
        Task { await finish() }
    }

    /// Switch the language of the in-progress background recording (see
    /// `TranscriptionService.changeLanguage`). Also remembers the new preference.
    func changeLanguage(to preferred: String?) async {
        themeManager?.transcriptionLanguage = preferred
        await transcription.changeLanguage(to: preferred)
    }

    /// The locale the background session is currently transcribing in, if any.
    var activeLocale: Locale? { transcription.activeLocale }

    /// Mirror the streaming transcript onto the note every second, so an open
    /// detail view (and the store) reflect progress even while in the background.
    private func startPersisting(into note: Note) {
        persistTask?.cancel()
        persistTask = Task { @MainActor in
            while transcription.isRecording {
                note.transcript = transcription.finalizedText
                note.transcriptSegments = transcription.finalizedSegments
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func finish() async {
        persistTask?.cancel(); persistTask = nil
        guard let note = activeNote else { return }

        await transcription.stop()
        note.transcript = transcription.finalizedText
        note.transcriptSegments = transcription.finalizedSegments

        // Speaker ID — hand over enrolled voices so they're recognized by name.
        let profiles: [SpeakerProfile] = context.flatMap {
            try? $0.fetch(FetchDescriptor<SpeakerProfile>())
        } ?? []
        let known = profiles.map { KnownVoice(name: $0.name, embedding: $0.embedding) }
        await transcription.identifySpeakers(knownVoices: known)
        note.transcriptSegments = transcription.finalizedSegments
        var merged = note.speakerEmbeddings
        for (label, vector) in transcription.speakerEmbeddings { merged[label] = vector }
        note.speakerEmbeddings = merged

        // Optional auto-summary, matching the in-note behavior.
        if let tm = themeManager, tm.autoSummarize, !note.transcript.isEmpty {
            let result = await summaryService.summarize(
                notes: note.body, transcript: note.transcript, attendees: note.attendees,
                tone: tm.summaryTone,
                includeDecisions: tm.extractDecisions,
                includeActionItems: tm.extractActionItems,
                includeOpenQuestions: tm.extractOpenQuestions,
                includeKeyQuotes: tm.extractKeyQuotes)
            if let result { note.summaryData = try? JSONEncoder().encode(result) }
        }

        try? context?.save()
        activeNote = nil
        activeNoteID = nil
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
        //
        // Apple's macOS icon grid sits the body in ~80% of the tile (824/1024)
        // with a transparent margin + soft shadow; render the art at that inset so
        // Inkling is the same size as every other Dock icon instead of edge-to-edge.
        let tile = 512.0
        let body = tile * 0.805
        let content = AppIconView(mood: mood, size: body)
            .shadow(color: .black.opacity(0.22), radius: 11, x: 0, y: 7)
            .frame(width: tile, height: tile)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let cg = renderer.cgImage else { return }
        let image = NSImage(cgImage: cg, size: NSSize(width: tile, height: tile))
        NSApp.applicationIconImage = image
        // Assigning `applicationIconImage` alone often doesn't repaint the Dock —
        // set the tile's contents and force a redraw so the mood icon actually shows.
        NSApp.dockTile.contentView = NSImageView(image: image)
        NSApp.dockTile.display()
        #endif
    }
}

#if os(iOS)
/// Tints the app's windows with the accent so system chrome that follows the
/// *window* tint (notably the navigation back button) matches the rest of the UI.
enum AppChrome {
    @MainActor
    static func tintWindows(_ color: Color) {
        let ui = UIColor(color)
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows { window.tintColor = ui }
        }
    }
}
#endif
