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

    /// On iPad, the notes surface is either keyboard (Type) or Pencil (Draw).
    @State private var penMode: PenMode = .type
    private enum PenMode: Hashable { case type, draw }

    private var theme: Theme { themeManager.theme }
    private var density: Density { themeManager.density }

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
        GeometryReader { proxy in
            // Side-by-side when wider than tall (landscape / Mac); stacked when
            // taller than wide (iPad portrait / iPhone) — note on top, transcript
            // below, a horizontal cut across the screen.
            let wide = proxy.size.width >= proxy.size.height

            VStack(alignment: .leading, spacing: 12) {
                header

                Rectangle()
                    .fill(theme.line)
                    .frame(height: theme.borderWidth)

                splitContent(wide: wide)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .moodPaper(theme)
        }
        .navigationTitle(note.title.isEmpty ? "New Note" : note.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem { recordControl }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
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

            meetingMeta

            tagsRow
        }
    }

    /// Meeting metadata, read from the note's real fields (E4) rather than parsed
    /// out of the body. Shown only for notes that came from a calendar event.
    @ViewBuilder
    private var meetingMeta: some View {
        if let start = note.startDate {
            HStack(spacing: 8) {
                Label {
                    if let end = note.endDate {
                        Text("\(start, format: .dateTime.hour().minute()) – \(end, format: .dateTime.hour().minute())")
                    } else {
                        Text(start, format: .dateTime.hour().minute())
                    }
                } icon: {
                    Image(systemName: "clock")
                }

                if !note.attendees.isEmpty {
                    Text("·").foregroundStyle(theme.inkFaint)
                    Label(note.attendees.joined(separator: ", "), systemImage: "person.2")
                        .lineLimit(1)
                }

                Text("·").foregroundStyle(theme.inkFaint)
                Label("Calendar", systemImage: "calendar")
            }
            .font(theme.monoFont(11))
            .foregroundStyle(theme.inkSoft)
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

    /// The design's bottom action bar: a quiet hint on the left, the Action
    /// items + Summarize CTAs on the right.
    private var bottomBar: some View {
        HStack(spacing: 12) {
            Label("Your notes + the transcript merge into a summary", systemImage: "wand.and.stars")
                .font(theme.bodyFont(12))
                .foregroundStyle(theme.inkFaint)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            Button { activeSheet = .actionItems } label: {
                Label("Action items", systemImage: "checklist")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.bordered)
            .tint(theme.accent)

            Button { activeSheet = .summary } label: {
                Label("Summarize", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(theme.paperRaised)
        .overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: theme.borderWidth) }
    }

    @ViewBuilder
    private func splitContent(wide: Bool) -> some View {
        if wide {
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

    private var notesColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            #if os(iOS)
            if showsHandwriting { penModeBar }
            #endif
            notesSurface
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// One surface: typed notes with the Pencil canvas overlaid. The active mode
    /// owns touches (the other layer is hit-test-transparent), so on iPad you
    /// type *and* draw on the same page — the design's unified notes canvas.
    private var notesSurface: some View {
        ZStack(alignment: .topLeading) {
            typedNotes
                .allowsHitTesting(typedActive)

            #if os(iOS)
            if showsHandwriting {
                DrawingCanvas(data: $note.drawing, inkColor: theme.ink, isActive: penMode == .draw)
                    .id(canvasID)
                    .allowsHitTesting(penMode == .draw)
            }
            #endif
        }
        .padding(.leading, 16)
        .overlay(alignment: .leading) {
            // Notebook margin rule (the design's .pk-notes::before).
            Rectangle().fill(theme.accentLine).frame(width: 1)
        }
    }

    /// Typed layer accepts touches unless we're actively drawing on iPad.
    private var typedActive: Bool {
        !showsHandwriting || penMode == .type
    }

    #if os(iOS)
    private var penModeBar: some View {
        HStack(spacing: 10) {
            Picker("Input", selection: $penMode) {
                Label("Type", systemImage: "keyboard").tag(PenMode.type)
                Label("Draw", systemImage: "pencil.tip").tag(PenMode.draw)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Spacer()

            if penMode == .draw {
                Button { showClearDrawing = true } label: {
                    Label("Clear", systemImage: "eraser").font(.caption)
                }
                .tint(theme.accent)
                .disabled(note.drawing == nil)
            }
        }
    }
    #endif

    private var transcriptPanel: some View {
        TranscriptPanel(
            theme: theme,
            density: density,
            text: note.transcript,
            volatile: transcription.volatileText,
            state: transcription.state,
            startedAt: transcription.startedAt
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

    // MARK: Top-bar record control (the design's REC pill + circular stop)

    @ViewBuilder
    private var recordControl: some View {
        if transcription.isRecording {
            HStack(spacing: 8) {
                if let startedAt = transcription.startedAt {
                    TimelineView(.periodic(from: startedAt, by: 1)) { _ in
                        HStack(spacing: 5) {
                            Circle().fill(theme.rec).frame(width: 7, height: 7)
                            Text(elapsed(since: startedAt))
                                .font(theme.monoFont(12, relativeTo: .subheadline))
                                .foregroundStyle(theme.rec)
                        }
                    }
                }
                Button { toggleRecord() } label: {
                    Image(systemName: "stop.fill")
                        .font(.caption)
                        .foregroundStyle(theme.paperRaised)
                        .padding(8)
                        .background(theme.ink, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop recording")
            }
        } else {
            Button { toggleRecord() } label: {
                Label(recordLabel, systemImage: "mic.fill")
            }
            .disabled(transcription.state == .preparing
                      || transcription.state == .downloadingModel
                      || transcription.state == .finishing)
        }
    }

    private var recordLabel: String {
        switch transcription.state {
        case .preparing: "Starting…"
        case .downloadingModel: "Downloading…"
        case .finishing: "Stopping…"
        default: "Record"
        }
    }

    private func elapsed(since start: Date) -> String {
        let s = max(0, Int(Date().timeIntervalSince(start)))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

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
