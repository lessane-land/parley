import SwiftUI
import SwiftData

/// The note detail: the user's own notes (typed everywhere, handwritten on iPad)
/// alongside the live transcript. On a wide layout (iPad/Mac) they sit side by
/// side — the design's notes-|-transcript split; on iPhone they stack.
struct NoteDetailView: View {
    /// `@Bindable` makes two-way bindings (`$note.title`) to our `@Model` `Note`.
    /// Typing/drawing mutates the tracked object directly; SwiftData autosaves.
    @Bindable var note: Note

    /// When the Record CTA created this note, auto-start recording on appear.
    var autoRecord: Bool = false
    var onAutoRecordConsumed: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(ThemeManager.self) private var themeManager
    @Environment(EventKitService.self) private var eventKit

    @Query(sort: \Tag.name) private var allTags: [Tag]

    /// One transcription engine per open note. `@State` keeps it alive for the
    /// view's lifetime; the detail is rebuilt per note (via `.id`), so each note
    /// gets its own clean session.
    @State private var transcription = TranscriptionService()

    /// On-device summarizer (the Granola magic).
    @State private var summaryService = SummaryService()

    /// Recreating the canvas (via `.id`) forces a reload — used by "Clear".
    @State private var canvasID = UUID()
    @State private var showClearDrawing = false
    @State private var didAutoStart = false
    @State private var showingNewTag = false
    @State private var newTagName = ""

    /// One enum-driven sheet so multiple `.sheet`s don't fight.
    @State private var activeSheet: DetailSheet?

    private enum DetailSheet: Int, Identifiable {
        case actionItems, summary
        var id: Int { rawValue }
    }

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var hSize
    #endif

    private var theme: Theme { themeManager.theme }
    private var density: Density { themeManager.density }

    /// Side-by-side on iPad/Mac; stacked on iPhone.
    private var isWide: Bool {
        #if os(macOS)
        true
        #else
        hSize == .regular
        #endif
    }

    /// Handwriting is an iPad feature (and respects the Settings toggle).
    private var showsHandwriting: Bool {
        guard themeManager.handwriting else { return false }
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad
        #else
        return false
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Rectangle()
                .fill(theme.line)
                .frame(height: theme.borderWidth)

            if isWide {
                HStack(alignment: .top, spacing: 16) {
                    notesColumn.frame(maxWidth: .infinity, maxHeight: .infinity)
                    transcriptPanel.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(spacing: 16) {
                    notesColumn.frame(maxWidth: .infinity, maxHeight: .infinity)
                    transcriptPanel.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.paper)
        .navigationTitle(note.title.isEmpty ? "New Note" : note.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem {
                Button { activeSheet = .summary } label: {
                    Label("Summarize", systemImage: "sparkles")
                }
            }
            ToolbarItem {
                Button { activeSheet = .actionItems } label: {
                    Label("Action Items", systemImage: "checklist")
                }
            }
        }
        .sheet(item: $activeSheet) { which in
            switch which {
            case .actionItems:
                ActionItemsSheet(
                    theme: theme,
                    detected: ActionItemDetector.detect(in: note.body + "\n" + note.transcript),
                    access: eventKit.remindersAccess,
                    onAdd: { await eventKit.addReminders($0) }
                )
            case .summary:
                SummaryView(
                    theme: theme,
                    note: note,
                    service: summaryService,
                    onAddReminders: { await eventKit.addReminders($0) }
                )
            }
        }
        // Persist confirmed transcript text as it streams in.
        .onChange(of: transcription.finalizedText) { _, newValue in
            note.transcript = newValue
        }
        // Don't leave a session running when switching away from this note.
        .onDisappear {
            if transcription.isRecording {
                Task {
                    await transcription.stop()
                    note.transcript = transcription.finalizedText
                }
            }
        }
        .confirmationDialog("Clear handwriting?", isPresented: $showClearDrawing, titleVisibility: .visible) {
            Button("Clear", role: .destructive) {
                note.drawing = nil
                canvasID = UUID()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the Pencil strokes on this note. Your typed text is kept.")
        }
        .alert("New Tag", isPresented: $showingNewTag) {
            TextField("Name", text: $newTagName)
            Button("Add") { createTag() }
            Button("Cancel", role: .cancel) {}
        }
        // Auto-start recording when opened via the Record CTA.
        .onAppear {
            if autoRecord, !didAutoStart, !transcription.isRecording {
                didAutoStart = true
                onAutoRecordConsumed()
                toggleRecord()
            }
        }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Title", text: $note.title)
                .font(theme.titleFont(26, relativeTo: .title))
                .tracking(theme.titleTracking)
                .foregroundStyle(theme.ink)
                .textFieldStyle(.plain)

            Text(note.createdAt, format: .dateTime.weekday().month().day().hour().minute())
                .font(theme.monoFont(11))
                .foregroundStyle(theme.inkFaint)

            tagsRow
        }
    }

    private var tagsRow: some View {
        HStack(spacing: 6) {
            ForEach(note.tags ?? []) { tag in
                HStack(spacing: 4) {
                    Circle().fill(tag.color).frame(width: 6, height: 6)
                    Text(tag.name).font(theme.monoFont(10, relativeTo: .caption2))
                }
                .foregroundStyle(theme.inkSoft)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(theme.paperRaised, in: Capsule())
                .overlay(Capsule().strokeBorder(theme.edge, lineWidth: theme.borderWidth))
            }

            Menu {
                ForEach(allTags) { tag in
                    Button { toggle(tag) } label: {
                        if isAssigned(tag) { Label(tag.name, systemImage: "checkmark") } else { Text(tag.name) }
                    }
                }
                if !allTags.isEmpty { Divider() }
                Button { newTagName = ""; showingNewTag = true } label: { Label("New Tag…", systemImage: "plus") }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "tag")
                    Text("Tag")
                }
                .font(theme.bodyFont(12))
                .foregroundStyle(theme.accentInk)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(theme.accentTint, in: Capsule())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
    }

    private func isAssigned(_ tag: Tag) -> Bool {
        (note.tags ?? []).contains { $0.persistentModelID == tag.persistentModelID }
    }

    private func toggle(_ tag: Tag) {
        var tags = note.tags ?? []
        if let index = tags.firstIndex(where: { $0.persistentModelID == tag.persistentModelID }) {
            tags.remove(at: index)
        } else {
            tags.append(tag)
        }
        note.tags = tags
    }

    private func createTag() {
        let name = newTagName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let color = Tag.palette[allTags.count % Tag.palette.count]
        let tag = Tag(name: name, colorHex: color)
        context.insert(tag)
        toggle(tag)
    }

    private var notesColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            typedNotes
                .padding(.leading, 16)
                .overlay(alignment: .leading) {
                    // Notebook margin rule (the design's .pk-notes::before).
                    Rectangle().fill(theme.accentLine).frame(width: 1)
                }
                .frame(maxHeight: showsHandwriting ? 220 : .infinity)

            #if os(iOS)
            if showsHandwriting {
                handwriting
            }
            #endif
        }
    }

    private var transcriptPanel: some View {
        TranscriptPanel(
            theme: theme,
            density: density,
            text: note.transcript,
            volatile: transcription.volatileText,
            state: transcription.state,
            startedAt: transcription.startedAt,
            onToggleRecord: toggleRecord
        )
    }

    private var typedNotes: some View {
        TextEditor(text: $note.body)
            .font(theme.bodyFont(density.bodySize))
            .foregroundStyle(theme.ink2)
            .lineSpacing(density.lineSpacing)
            .scrollContentBackground(.hidden)
            .overlay(alignment: .topLeading) {
                if note.body.isEmpty {
                    Text("Start typing your notes…")
                        .font(theme.bodyFont(density.bodySize))
                        .foregroundStyle(theme.inkFaint)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
    }

    #if os(iOS)
    private var handwriting: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("HANDWRITING")
                    .font(theme.monoFont(11))
                    .tracking(1.2)
                    .foregroundStyle(theme.inkFaint)
                Spacer()
                Button {
                    showClearDrawing = true
                } label: {
                    Label("Clear", systemImage: "eraser")
                        .font(.caption)
                }
                .tint(theme.accent)
                .disabled(note.drawing == nil)
            }

            DrawingCanvas(data: $note.drawing, inkColor: theme.ink)
                .id(canvasID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .moodCard(theme)
        }
    }
    #endif

    private func toggleRecord() {
        Task {
            if transcription.isRecording {
                await transcription.stop()
                note.transcript = transcription.finalizedText
            } else {
                await transcription.start(seed: note.transcript, preferredLanguage: themeManager.transcriptionLanguage)
            }
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Note.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let note = Note(title: "Kickoff sync", body: "Discussed Phase 0 scope.")
    container.mainContext.insert(note)
    return NavigationStack {
        NoteDetailView(note: note)
    }
    .modelContainer(container)
    .environment(ThemeManager())
    .environment(EventKitService())
}
