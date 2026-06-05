import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

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

    /// Free-text speaker naming: the segment being named + the draft text.
    @State private var editingSpeakerID: UUID?
    @State private var speakerDraft = ""

    /// One enum-driven sheet so multiple `.sheet`s don't fight.
    @State private var activeSheet: DetailSheet?

    /// The summary is a first-class *pushed* screen (not a sheet), so it gets a
    /// real back button and sits in the note's navigation stack.
    @State private var showingSummary = false

    private enum DetailSheet: Int, Identifiable {
        case actionItems
        var id: Int { rawValue }
    }

    /// On iPad, the notes surface is either keyboard (Type) or Pencil (Draw).
    /// Defaults to **Draw** (Pencil-first). The keyboard still works for the title
    /// and other fields; tap **Type** to type into the notes body.
    @State private var penMode: PenMode = .draw
    private enum PenMode: Hashable { case type, draw }

    /// Notes ⟷ transcript layout (order + split ratio) is a persisted preference
    /// on `ThemeManager`, so the arrangement sticks across notes and launches.
    /// `dragBase` is just the fraction captured at the start of a divider drag.
    @State private var dragBase: CGFloat?

    /// Whether the transcript panel is shown. Collapsing it gives notes the full
    /// surface; a toolbar button (and the panel's chevron) toggle it.
    @State private var showTranscript = true

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
            ToolbarItem { transcriptToggle }
            ToolbarItem { swapControl }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .sheet(item: $activeSheet) { which in
            switch which {
            case .actionItems:
                ActionItemsSheet(
                    theme: theme,
                    detected: dedupe(flaggedActions + ActionItemDetector.detect(in: note.body + "\n" + note.transcript)),
                    access: eventKit.remindersAccess,
                    onAdd: { await eventKit.addReminders($0) }
                )
            }
        }
        .navigationDestination(isPresented: $showingSummary) {
            SummaryView(
                theme: theme,
                note: note,
                service: summaryService,
                onAddReminders: { await eventKit.addReminders($0) },
                onOpenNotes: { showingSummary = false },
                onOpenTranscript: {
                    showingSummary = false
                    withAnimation(.snappy) { showTranscript = true }
                }
            )
        }
        // Persist confirmed transcript text + segments as they stream in.
        .onChange(of: transcription.finalizedText) { _, newValue in
            note.transcript = newValue
        }
        .onChange(of: transcription.finalizedSegments) { _, newValue in
            note.transcriptSegments = newValue
        }
        // Don't leave a session running when switching away from this note.
        .onDisappear {
            if transcription.isRecording {
                Task {
                    await transcription.stop()
                    note.transcript = transcription.finalizedText
                    note.transcriptSegments = transcription.finalizedSegments
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
        .alert("Speaker name", isPresented: Binding(
            get: { editingSpeakerID != nil },
            set: { if !$0 { editingSpeakerID = nil } }
        )) {
            TextField("Name", text: $speakerDraft)
            Button("Save") { saveSpeakerName() }
            Button("Cancel", role: .cancel) { editingSpeakerID = nil }
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

            Button { showingSummary = true } label: {
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

    /// Notes and transcript with a draggable divider between them;
    /// `layoutSwapped` flips which one leads. Side-by-side when wide, stacked otherwise.
    @ViewBuilder
    private func splitContent(wide: Bool) -> some View {
        if showTranscript {
            splitWithTranscript(wide: wide)
        } else {
            notesColumn   // transcript collapsed → notes get the whole surface
        }
    }

    private func splitWithTranscript(wide: Bool) -> some View {
        let first = themeManager.layoutSwapped ? AnyView(transcriptPanel) : AnyView(notesColumn)
        let second = themeManager.layoutSwapped ? AnyView(notesColumn) : AnyView(transcriptPanel)

        return GeometryReader { geo in
            let total = wide ? geo.size.width : geo.size.height
            let thickness: CGFloat = 18
            let firstLen = max(0, (total - thickness) * clampedFraction)

            if wide {
                HStack(spacing: 0) {
                    first.frame(width: firstLen).frame(maxHeight: .infinity)
                    splitHandle(wide: true, total: total)
                    second.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(spacing: 0) {
                    first.frame(maxWidth: .infinity).frame(height: firstLen)
                    splitHandle(wide: false, total: total)
                    second.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private var clampedFraction: CGFloat { CGFloat(min(max(themeManager.splitFraction, 0.2), 0.8)) }

    /// The drag affordance between the two panels: drag to resize, double-tap to
    /// even it out. A horizontal bar when stacked, a vertical bar when side-by-side.
    private func splitHandle(wide: Bool, total: CGFloat) -> some View {
        ZStack {
            Rectangle().fill(Color.clear)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(theme.inkGhost)
                .frame(width: wide ? 3 : 40, height: wide ? 40 : 3)
        }
        .frame(width: wide ? 18 : nil, height: wide ? nil : 18)
        .frame(maxWidth: wide ? nil : .infinity, maxHeight: wide ? .infinity : nil)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let base = dragBase ?? clampedFraction
                    dragBase = base
                    let delta = (wide ? value.translation.width : value.translation.height) / max(total, 1)
                    themeManager.splitFraction = Double(min(max(base + delta, 0.2), 0.8))
                }
                .onEnded { _ in dragBase = nil }
        )
        .onTapGesture(count: 2) { withAnimation(.snappy) { themeManager.splitFraction = 0.5 } }
        .accessibilityLabel("Resize notes and transcript")
        #if os(macOS)
        .onHover { inside in
            if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
        }
        #endif
    }

    private var swapControl: some View {
        Button {
            // Flip the order *and* invert the fraction so each panel keeps its
            // current size after moving to the other side.
            withAnimation(.snappy) {
                themeManager.layoutSwapped.toggle()
                themeManager.splitFraction = 1 - themeManager.splitFraction
            }
        } label: {
            Label("Swap notes and transcript", systemImage: "arrow.left.arrow.right")
        }
        .accessibilityLabel("Swap notes and transcript")
    }

    /// Collapse / show the transcript panel.
    private var transcriptToggle: some View {
        Button { withAnimation(.snappy) { showTranscript.toggle() } } label: {
            Label(showTranscript ? "Hide transcript" : "Show transcript",
                  systemImage: showTranscript ? "captions.bubble.fill" : "captions.bubble")
        }
        .accessibilityLabel(showTranscript ? "Hide transcript" : "Show transcript")
    }

    /// De-duplicate strings (order-preserving, case-insensitive, drops blanks).
    private func dedupe(_ items: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for item in items {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            result.append(trimmed)
        }
        return result
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
            segments: note.transcriptSegments,
            volatile: transcription.volatileText,
            state: transcription.state,
            startedAt: transcription.startedAt,
            languageLabel: transcription.activeLanguageLabel,
            canLabelSpeakers: !transcription.isRecording,
            knownSpeakers: knownSpeakers,
            onAssignSpeaker: assignSpeaker,
            onNewSpeaker: promptNewSpeaker,
            onRenameSpeaker: renameSpeaker,
            onToggleFlag: toggleFlag,
            onCollapse: { withAnimation(.snappy) { showTranscript = false } }
        )
    }

    /// Flag/unflag a transcript line as an action item.
    private func toggleFlag(_ id: UUID) {
        var segments = note.transcriptSegments
        guard let index = segments.firstIndex(where: { $0.id == id }) else { return }
        segments[index].flagged.toggle()
        note.transcriptSegments = segments
    }

    /// Transcript lines the user flagged as action items.
    private var flaggedActions: [String] {
        note.transcriptSegments.filter(\.flagged).map(\.text)
    }

    private var typedNotes: some View {
        TextEditor(text: $note.body)
            .font(theme.bodyFont(density.bodySize))
            .foregroundStyle(theme.ink2)
            .lineSpacing(density.lineSpacing)
            .scrollContentBackground(.hidden)
            .overlay(alignment: .topLeading) {
                // Only when typing is the active mode — in Draw mode the prompt
                // is misleading (and the user asked not to see it on iPad).
                if note.body.isEmpty && typedActive {
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
                      || transcription.state == .finishing
                      || transcription.state == .identifyingSpeakers)
        }
    }

    private var recordLabel: String {
        switch transcription.state {
        case .preparing: "Starting…"
        case .downloadingModel: "Downloading…"
        case .finishing: "Stopping…"
        case .identifyingSpeakers: "Speakers…"
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
                note.transcriptSegments = transcription.finalizedSegments
                // Identify speakers from the recorded audio (no-op without
                // FluidAudio); persist the labeled segments when it finishes.
                await transcription.identifySpeakers()
                note.transcriptSegments = transcription.finalizedSegments
                await autoSummarizeIfEnabled()
            } else {
                // Reveal the transcript so the live text is visible while recording.
                withAnimation(.snappy) { showTranscript = true }
                // Seed the session with the existing transcript. Older notes have
                // flat text but no segments — wrap that as one block so resuming
                // keeps the prior content visible on the timeline.
                var seedSegments = note.transcriptSegments
                if seedSegments.isEmpty, !note.transcript.isEmpty {
                    seedSegments = [TranscriptSegment(text: note.transcript)]
                }
                await transcription.start(
                    seed: note.transcript,
                    seedSegments: seedSegments,
                    preferredLanguage: themeManager.transcriptionLanguage
                )
            }
        }
    }

    /// Draft a summary in the background right after a recording stops, when
    /// Settings ▸ AI ▸ Auto-summarize is on — so it's ready when the user opens it.
    private func autoSummarizeIfEnabled() async {
        guard themeManager.autoSummarize, !note.transcript.isEmpty else { return }
        let result = await summaryService.summarize(
            notes: note.body, transcript: note.transcript, attendees: note.attendees,
            tone: themeManager.summaryTone,
            includeDecisions: themeManager.extractDecisions,
            includeActionItems: themeManager.extractActionItems,
            includeOpenQuestions: themeManager.extractOpenQuestions,
            includeKeyQuotes: themeManager.extractKeyQuotes
        )
        if let result { note.summaryData = try? JSONEncoder().encode(result) }
    }

    /// Speaker names already used in this note (for the quick-pick menu), distinct
    /// and alphabetized.
    private var knownSpeakers: [String] {
        let names = note.transcriptSegments.compactMap(\.speaker).filter { !$0.isEmpty }
        return Array(Set(names)).sorted()
    }

    /// Assign (or clear, with `nil`) a segment's speaker by hand. On-device
    /// diarization isn't offered, so labeling is manual; gated to not-recording so
    /// it never races the live segment stream.
    private func assignSpeaker(_ id: UUID, _ name: String?) {
        guard !transcription.isRecording else { return }
        var segments = note.transcriptSegments
        guard let index = segments.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        segments[index].speaker = (trimmed?.isEmpty ?? true) ? nil : trimmed
        note.transcriptSegments = segments
    }

    /// Open the free-text prompt to name the speaker for a segment, seeded with
    /// its current name.
    private func promptNewSpeaker(_ id: UUID) {
        speakerDraft = note.transcriptSegments.first { $0.id == id }?.speaker ?? ""
        editingSpeakerID = id
    }

    /// Rename a speaker from the legend chip — opens the prompt against any line
    /// of that speaker, so saving renames the whole group.
    private func renameSpeaker(_ label: String) {
        guard let id = note.transcriptSegments.first(where: { $0.speaker == label })?.id else { return }
        promptNewSpeaker(id)
    }

    /// Commit a typed speaker name. If the line already has a label (e.g. an
    /// auto-assigned "Speaker 1"), rename *every* line that shares it — so naming
    /// a diarized speaker once applies everywhere. An unlabeled line names just
    /// itself.
    private func saveSpeakerName() {
        defer { editingSpeakerID = nil }
        guard let id = editingSpeakerID else { return }
        let trimmed = speakerDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let newName: String? = trimmed.isEmpty ? nil : trimmed

        var segments = note.transcriptSegments
        guard let target = segments.first(where: { $0.id == id }) else { return }
        if let current = target.speaker {
            for i in segments.indices where segments[i].speaker == current {
                segments[i].speaker = newName
            }
        } else if let i = segments.firstIndex(where: { $0.id == id }) {
            segments[i].speaker = newName
        }
        note.transcriptSegments = segments
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
