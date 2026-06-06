import SwiftUI
import SwiftData
import PhotosUI
import PencilKit
import Vision
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif
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
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    @Environment(EventKitService.self) private var eventKit
    @Environment(RecordingCoordinator.self) private var recorder

    @Query(sort: \Tag.name) private var allTags: [Tag]
    @Query private var speakerProfiles: [SpeakerProfile]

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

    /// Canvas (images + shapes) editing state. Shapes float on top of the drawing
    /// and are draggable any time — no separate mode.
    @State private var selectedItemID: UUID?
    /// The drawing canvas's current scroll offset, so canvas items scroll *with*
    /// the page (stored in page coords, rendered at page − scroll).
    @State private var canvasScroll: CGPoint = .zero
    @State private var showCanvasPhoto = false
    @State private var canvasPhotoItem: PhotosPickerItem?
    /// One-time per-open setup of the transcript panel visibility.
    @State private var didConfigureTranscript = false

    /// Notes ⟷ transcript layout (order + split ratio) is a persisted preference
    /// on `ThemeManager`, so the arrangement sticks across notes and launches.
    /// `dragBase` is just the fraction captured at the start of a divider drag.
    @State private var dragBase: CGFloat?

    /// Whether the transcript panel is shown. Collapsing it gives notes the full
    /// surface; a toolbar button (and the panel's chevron) toggle it.
    @State private var showTranscript = true

    /// Attachments: the photo picker / file importer presentation flags, the
    /// pending photo selections, and the attachment currently being previewed.
    @State private var showPhotoPicker = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var importingFile = false
    @State private var previewAttachment: Attachment?
    @State private var showAttachMenu = false

    /// Delete-this-note confirmation.
    @State private var showDeleteNote = false

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
        .overlay(alignment: .top) { processingBanner }
        .animation(.snappy, value: transcription.state)
        .navigationTitle(note.title.isEmpty ? "New Note" : note.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem { recordControl }
            ToolbarItem { attachControl }
            ToolbarItem { transcriptToggle }
            ToolbarItem { swapControl }
            ToolbarItem { noteMenu }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItems, maxSelectionCount: 10, matching: .images)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await addPhotos(items) }
        }
        .fileImporter(isPresented: $importingFile, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            handleFileImport(result)
        }
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
        // All the note's confirmations/alerts are bundled into one modifier. This
        // isn't just tidiness: collapsing four chained modifiers into one keeps the
        // body's modifier chain short enough for the Swift type-checker (a long
        // chain trips "unable to type-check this expression in reasonable time").
        .modifier(NoteDialogs(
            showClearDrawing: $showClearDrawing,
            showDeleteNote: $showDeleteNote,
            showingNewTag: $showingNewTag,
            newTagName: $newTagName,
            editingSpeakerID: $editingSpeakerID,
            speakerDraft: $speakerDraft,
            onClear: {
                note.drawing = nil
                note.canvasItems = []   // also remove inserted images + shapes
                selectedItemID = nil
                canvasID = UUID()
            },
            onDelete: { deleteNote() },
            onCreateTag: { createTag() },
            onSaveSpeaker: { saveSpeakerName() }
        ))
        // Auto-start recording when opened via the Record CTA.
        .task {
            // Merge any duplicate enrolled voices that synced in from another device.
            SpeakerProfile.dedupe(speakerProfiles, in: context)
            // A fresh note (no transcript yet) opens with the transcript hidden —
            // it's revealed when a recording starts. Notes that already have a
            // transcript open with it shown.
            if !didConfigureTranscript {
                didConfigureTranscript = true
                // Show the transcript if there's text, or if this note is being
                // recorded in the background (so its live text is visible).
                showTranscript = !note.transcript.isEmpty || backgroundRecordingThisNote
            }
            // Never start a local session for a note already recording in the
            // background — the menu-bar recorder owns it.
            guard !backgroundRecordingThisNote else { return }
            guard autoRecord, !didAutoStart, !transcription.isRecording else { return }
            didAutoStart = true
            onAutoRecordConsumed()
            // The very first launch needs the pushed view + audio session to settle;
            // a synchronous start here can silently no-op. Defer briefly, then retry
            // a couple of times until recording actually begins.
            for attempt in 0..<3 {
                if transcription.isRecording { break }
                try? await Task.sleep(for: .milliseconds(attempt == 0 ? 300 : 500))
                if transcription.isRecording || transcription.state == .preparing
                    || transcription.state == .downloadingModel { continue }
                toggleRecord()
            }
        }
    }

    // MARK: Pieces

    /// A non-blocking banner shown while a recording is being finalized/diarized
    /// (which now runs off the main thread, so this can actually animate).
    @ViewBuilder
    private var processingBanner: some View {
        if transcription.state == .identifyingSpeakers || transcription.state == .finishing {
            let shape = RoundedRectangle(cornerRadius: theme.cornerRadius == 0 ? 0 : 12, style: .continuous)
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(transcription.state == .identifyingSpeakers
                     ? "Processing recording · identifying speakers…"
                     : "Finishing recording…")
                    .font(theme.bodyFont(13))
                    .foregroundStyle(theme.ink)
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(theme.paperRaised, in: shape)
            .overlay(shape.strokeBorder(theme.edge, lineWidth: theme.borderWidth))
            .themeShadow(theme.shadow)
            .padding(.top, 10)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

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

            attachmentsStrip
        }
    }

    /// A horizontal strip of attachment tiles (image thumbnails / file icons).
    /// Hidden when the note has none; the paperclip toolbar menu adds them.
    @ViewBuilder
    private var attachmentsStrip: some View {
        let items = (note.attachments ?? []).sorted { $0.createdAt < $1.createdAt }
        if !items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items) { attachment in attachmentCard(attachment) }
                }
                .padding(.vertical, 2)
            }
            // Attached to the strip (not the top-level body) so it never competes
            // with the action-items sheet for presentation.
            .sheet(item: $previewAttachment) { attachment in
                AttachmentPreviewSheet(theme: theme, attachment: attachment)
            }
        }
    }

    private func attachmentCard(_ attachment: Attachment) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.cornerRadius == 0 ? 0 : 9, style: .continuous)
        // The tile is a real Button (reliable click on macOS → preview); the ✕ is a
        // *sibling* button in the ZStack, so the two don't nest and fight.
        return ZStack(alignment: .topTrailing) {
            Button { previewAttachment = attachment } label: {
                VStack(spacing: 0) {
                    ZStack {
                        if let data = attachment.data,
                           AttachmentSupport.isImage(attachment),
                           let image = AttachmentSupport.image(from: data) {
                            image.resizable().scaledToFill()
                        } else {
                            theme.paperSunk
                            Image(systemName: AttachmentSupport.icon(attachment))
                                .font(.system(size: 20))
                                .foregroundStyle(theme.accent)
                        }
                    }
                    .frame(width: 104, height: 58)
                    .clipped()

                    Text(attachment.filename.isEmpty ? "Attachment" : attachment.filename)
                        .font(theme.monoFont(9.5, relativeTo: .caption2))
                        .foregroundStyle(theme.inkSoft)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(width: 104, alignment: .leading)
                        .padding(.horizontal, 7).padding(.vertical, 5)
                }
                .frame(width: 104)
                .background(theme.paperRaised)
                .clipShape(shape)
                .overlay(shape.strokeBorder(theme.edge, lineWidth: theme.borderWidth))
                .contentShape(shape)
            }
            .buttonStyle(.plain)

            Button { removeAttachment(attachment) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 17))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(theme.paperRaised, theme.inkSoft)
            }
            .buttonStyle(.plain)
            .padding(3)
            .accessibilityLabel("Remove attachment")
        }
        .contextMenu {
            Button { previewAttachment = attachment } label: { Label("Open", systemImage: "eye") }
            Button(role: .destructive) { removeAttachment(attachment) } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    /// The paperclip control: a plain Button (so it matches the other toolbar
    /// icons in size) that offers Photo / File. A `confirmationDialog` (not a
    /// popover) dismisses *itself* before running the action, so presenting the
    /// file importer afterwards no longer races a closing popover — which is why
    /// "Add File" previously did nothing.
    private var attachControl: some View {
        Button { showAttachMenu = true } label: {
            Label("Attach", systemImage: "paperclip").labelStyle(.iconOnly)
        }
        .confirmationDialog("Add Attachment", isPresented: $showAttachMenu, titleVisibility: .visible) {
            Button("Photo") { showPhotoPicker = true }
            Button("File") { importingFile = true }
            Button("Cancel", role: .cancel) {}
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

    // MARK: Attachments

    /// Load each picked photo's bytes off the PhotosPicker item and attach it.
    private func addPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let type = item.supportedContentTypes.first
            let uti = type?.identifier ?? UTType.image.identifier
            let ext = type?.preferredFilenameExtension ?? "jpg"
            addAttachment(data: data, filename: "Photo \(Self.stamp()).\(ext)", typeIdentifier: uti)
        }
        photoItems = []
    }

    /// Read each imported file (honoring security-scoped access) and attach it.
    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { continue }
            let uti = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.identifier
                ?? UTType.data.identifier
            addAttachment(data: data, filename: url.lastPathComponent, typeIdentifier: uti)
        }
    }

    private func addAttachment(data: Data, filename: String, typeIdentifier: String) {
        let attachment = Attachment(filename: filename, typeIdentifier: typeIdentifier, data: data)
        context.insert(attachment)
        // Append on the note side; SwiftData sets the inverse (`attachment.note`).
        note.attachments = (note.attachments ?? []) + [attachment]
    }

    private func removeAttachment(_ attachment: Attachment) {
        note.attachments?.removeAll { $0.persistentModelID == attachment.persistentModelID }
        context.delete(attachment)
    }

    /// A short, filename-safe timestamp so attached photos get distinct names.
    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM-d-HHmmss"
        return f.string(from: Date())
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

    /// Per-note overflow menu — currently just Delete, which removes the note from
    /// within the detail (no need to go back to the list) and pops back.
    private var noteMenu: some View {
        Menu {
            Button(role: .destructive) { showDeleteNote = true } label: {
                Label("Delete Note", systemImage: "trash")
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
    }

    /// Delete this note and return to the list. Stops any live recording first so
    /// the session doesn't outlive the note it was writing into.
    private func deleteNote() {
        if transcription.isRecording { Task { await transcription.stop() } }
        context.delete(note)
        dismiss()
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
        #if os(iOS)
        .photosPicker(isPresented: $showCanvasPhoto, selection: $canvasPhotoItem, matching: .images)
        .onChange(of: canvasPhotoItem) { _, item in
            guard let item else { return }
            Task { await addCanvasImage(item); canvasPhotoItem = nil }
        }
        #endif
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
                DrawingCanvas(data: $note.drawing, inkColor: theme.ink, isActive: penMode == .draw,
                              recognizeShapes: true,
                              onRecognizeShape: { kind, rect in addRecognizedShape(kind, rect) },
                              onScroll: { canvasScroll = $0 })
                    .id(canvasID)
                    // Pause canvas input while a shape/image is selected, so dragging
                    // and resizing it isn't fought over by the PencilKit scroll view.
                    .allowsHitTesting(penMode == .draw && selectedItemID == nil)
            } else if let data = note.drawing {
                // iPhone (no live canvas): show the handwriting read-only.
                DrawingImageView(data: data).allowsHitTesting(false)
            }
            #else
            // macOS has no PencilKit input, but it can still *render* the synced
            // strokes — so handwriting drawn on iPad is visible on the Mac.
            if let data = note.drawing {
                DrawingImageView(data: data).allowsHitTesting(false)
            }
            #endif

            // Shapes + images float on *top* of the drawing and are draggable any
            // time (empty space passes touches through to the canvas below).
            CanvasItemsLayer(
                items: Binding(get: { note.canvasItems }, set: { note.canvasItems = $0 }),
                selectedID: $selectedItemID,
                active: itemsInteractive,
                scrollOffset: canvasScroll,
                theme: theme
            )
        }
        .padding(.leading, 16)
        .overlay(alignment: .leading) {
            // Notebook margin rule (the design's .pk-notes::before).
            Rectangle().fill(theme.accentLine).frame(width: 1)
        }
    }

    /// Typed layer accepts touches unless we're drawing on iPad.
    private var typedActive: Bool {
        !showsHandwriting || penMode == .type
    }

    /// Canvas items are movable/resizable on iPad (where the pencil canvas is) and
    /// on macOS (where there's no pencil but you can still drag/resize a pasted pic
    /// with the cursor). Previously macOS returned false, so the handles showed but
    /// did nothing — that's why "resize isn't doing anything" on the Mac.
    private var itemsInteractive: Bool {
        #if os(iOS)
        return showsHandwriting
        #else
        return true
        #endif
    }

    #if os(iOS)
    private var penModeBar: some View {
        HStack(spacing: 10) {
            penModeToggle

            insertPalette   // add an image any time — it drops onto the page

            Spacer()

            if penMode == .draw {
                Button { showClearDrawing = true } label: {
                    Label("Clear", systemImage: "eraser").font(.caption)
                }
                .tint(theme.accent)
                .disabled(note.drawing == nil && note.canvasItems.isEmpty)
            }
        }
    }

    /// A mood-styled Type/Draw switch (the system segmented control ignores the
    /// theme). Geometry follows the mood — pill on paper, square on swiss/terminal/
    /// neubrutalist — and the selected segment fills with the accent.
    private var penModeToggle: some View {
        let radius: CGFloat = theme.cornerRadius == 0 ? 0 : 9
        let outer = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return HStack(spacing: 3) {
            penSegment(.type, title: "Type", icon: "keyboard", radius: max(0, radius - 3))
            penSegment(.draw, title: "Draw", icon: "pencil.tip", radius: max(0, radius - 3))
        }
        .padding(3)
        .background(theme.paperSunk, in: outer)
        .overlay(outer.strokeBorder(theme.edge, lineWidth: theme.borderWidth))
        .fixedSize()
    }

    private func penSegment(_ mode: PenMode, title: String, icon: String, radius: CGFloat) -> some View {
        let on = penMode == mode
        let fg: Color = on ? theme.paper : theme.inkSoft
        let bg: Color = on ? theme.accent : .clear
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return Button {
            withAnimation(.snappy) { penMode = mode }
        } label: {
            Label(title, systemImage: icon)
                .font(theme.monoFont(12, relativeTo: .footnote))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(fg)
                .background(bg, in: shape)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
    }

    /// Insert or paste an image onto the page (it's then draggable/resizable).
    /// Shapes aren't inserted from a button — draw a rough rectangle or oval and it
    /// snaps to a clean, movable shape (see `ShapeRecognizer`).
    private var insertPalette: some View {
        HStack(spacing: 14) {
            Button { showCanvasPhoto = true } label: {
                Label("Add image", systemImage: "photo").labelStyle(.iconOnly)
            }
            // Paste a copied image straight onto the canvas.
            PasteButton(supportedContentTypes: [.image]) { providers in
                Task { await pasteImages(providers) }
            }
            .labelStyle(.iconOnly)
            .buttonBorderShape(.capsule)
        }
        .font(.system(size: 15))
        .tint(theme.accent)
    }

    // MARK: Canvas items (images + recognized shapes)

    /// Turn a recognized freehand shape into a clean, movable `CanvasItem` placed
    /// where it was drawn.
    private func addRecognizedShape(_ kind: CanvasItem.Kind, _ rect: CGRect) {
        let hex = themeManager.accentHex ?? themeManager.mood.config.accentDefault
        let item = CanvasItem(kind: kind,
                              x: max(0, Double(rect.minX)), y: max(0, Double(rect.minY)),
                              width: max(40, Double(rect.width)), height: max(40, Double(rect.height)),
                              colorHex: hex)
        note.canvasItems = note.canvasItems + [item]
        selectedItemID = item.id
    }

    /// Insert pasted image(s) as movable canvas items.
    private func pasteImages(_ providers: [NSItemProvider]) async {
        for provider in providers {
            guard let data = await loadImageData(provider),
                  let small = AttachmentSupport.downscaled(data, maxDimension: 1000) else { continue }
            // Drop it where the page is currently scrolled (page coords), so it
            // appears in view and stays anchored to the page afterward.
            let item = CanvasItem(kind: .image,
                                  x: Double(canvasScroll.x) + 40, y: Double(canvasScroll.y) + 40,
                                  width: 220, height: 165, imageData: small)
            note.canvasItems = note.canvasItems + [item]
            selectedItemID = item.id
        }
    }

    /// Pull image bytes out of a pasteboard item provider (first conforming type).
    private func loadImageData(_ provider: NSItemProvider) async -> Data? {
        let type = provider.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .image) == true }
            ?? UTType.image.identifier
        return await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
            provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                cont.resume(returning: data)
            }
        }
    }

    private func addCanvasImage(_ pick: PhotosPickerItem) async {
        guard let data = try? await pick.loadTransferable(type: Data.self),
              let small = AttachmentSupport.downscaled(data, maxDimension: 1000) else { return }
        let item = CanvasItem(kind: .image,
                              x: Double(canvasScroll.x) + 40, y: Double(canvasScroll.y) + 40,
                              width: 220, height: 165, imageData: small)
        note.canvasItems = note.canvasItems + [item]
        selectedItemID = item.id
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

    /// True when *this* note is the one the app-level (menu-bar) recorder is
    /// capturing in the background — so the detail reflects/controls that session
    /// instead of starting a second, local one.
    private var backgroundRecordingThisNote: Bool {
        recorder.activeNoteID == note.persistentModelID
    }

    @ViewBuilder
    private var recordControl: some View {
        if backgroundRecordingThisNote {
            // Mirror the background session: live timer + a Stop that ends it.
            HStack(spacing: 8) {
                if let startedAt = recorder.startedAt {
                    TimelineView(.periodic(from: startedAt, by: 1)) { _ in
                        HStack(spacing: 5) {
                            Circle().fill(theme.rec).frame(width: 7, height: 7)
                            Text(elapsed(since: startedAt))
                                .font(theme.monoFont(12, relativeTo: .subheadline))
                                .foregroundStyle(theme.rec)
                        }
                    }
                }
                Button { recorder.stop() } label: {
                    Image(systemName: "stop.fill")
                        .font(.caption)
                        .foregroundStyle(theme.paperRaised)
                        .padding(8)
                        .background(theme.ink, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop recording")
            }
        } else if transcription.isRecording {
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
                // FluidAudio). Hand FluidAudio the voices we've enrolled so it can
                // recognize them directly; persist the labeled segments + their
                // embeddings, then run our own match as a backstop.
                let known = speakerProfiles.map { KnownVoice(name: $0.name, embedding: $0.embedding) }
                await transcription.identifySpeakers(knownVoices: known)
                note.transcriptSegments = transcription.finalizedSegments
                mergeSpeakerEmbeddings(transcription.speakerEmbeddings)
                autoLabelKnownSpeakers()
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
                #if os(macOS)
                let captureSystem = themeManager.captureSystemAudio
                #else
                let captureSystem = false
                #endif
                await transcription.start(
                    seed: note.transcript,
                    seedSegments: seedSegments,
                    preferredLanguage: themeManager.transcriptionLanguage,
                    captureSystemAudio: captureSystem
                )
            }
        }
    }

    /// Draft a summary in the background right after a recording stops, when
    /// Settings ▸ AI ▸ Auto-summarize is on — so it's ready when the user opens it.
    private func autoSummarizeIfEnabled() async {
        guard themeManager.autoSummarize, !note.transcript.isEmpty else { return }
        let result = await summaryService.summarize(
            notes: await combinedNotesText(), transcript: note.transcript, attendees: note.attendees,
            tone: themeManager.summaryTone,
            includeDecisions: themeManager.extractDecisions,
            includeActionItems: themeManager.extractActionItems,
            includeOpenQuestions: themeManager.extractOpenQuestions,
            includeKeyQuotes: themeManager.extractKeyQuotes
        )
        if let result { note.summaryData = try? JSONEncoder().encode(result) }
    }

    /// The user's notes for summarization: typed body + any recognized handwriting.
    private func combinedNotesText() async -> String {
        var text = note.body
        if let drawing = note.drawing {
            let handwritten = await HandwritingOCR.recognize(
                drawing, languages: ocrLanguages, customWords: note.attendees)
            if !handwritten.isEmpty {
                text += (text.isEmpty ? "" : "\n") + handwritten
            }
        }
        return text
    }

    /// Preferred OCR languages, seeded from the transcription language preference
    /// (handwriting is usually in the same language the user speaks).
    private var ocrLanguages: [String] {
        if let lang = themeManager.transcriptionLanguage, !lang.isEmpty { return [lang] }
        return []
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
        let previousLabel = target.speaker
        if let current = previousLabel {
            for i in segments.indices where segments[i].speaker == current {
                segments[i].speaker = newName
            }
        } else if let i = segments.firstIndex(where: { $0.id == id }) {
            segments[i].speaker = newName
        }
        note.transcriptSegments = segments

        // Naming a speaker enrolls their voice, so we recognize them next time.
        if let newName, let previousLabel {
            enrollVoice(named: newName, fromLabel: previousLabel)
        }
    }

    // MARK: Speaker enrollment / recognition

    /// Persist this meeting's speaker embeddings onto the note, so a voice can be
    /// named (→ enrolled) any time the note is open — not only right after recording.
    private func mergeSpeakerEmbeddings(_ embeddings: [String: [Float]]) {
        guard !embeddings.isEmpty else { return }
        var merged = note.speakerEmbeddings
        for (label, vector) in embeddings { merged[label] = vector }
        note.speakerEmbeddings = merged
    }

    /// Auto-rename auto-labeled speakers ("Speaker N") to an enrolled voice when
    /// the embeddings match closely enough, re-keying the stored embeddings.
    private func autoLabelKnownSpeakers() {
        guard themeManager.recognizeSpeakers, !speakerProfiles.isEmpty else { return }
        let embeddings = note.speakerEmbeddings
        guard !embeddings.isEmpty else { return }

        var segments = note.transcriptSegments
        var stored = embeddings
        var changed = false
        for (label, vector) in embeddings {
            guard TranscriptionService.isAutoSpeakerLabel(label),
                  let match = bestProfile(for: vector) else { continue }
            for i in segments.indices where segments[i].speaker == label {
                segments[i].speaker = match.name
            }
            stored[match.name] = vector
            stored[label] = nil
            changed = true
        }
        if changed {
            note.transcriptSegments = segments
            note.speakerEmbeddings = stored
        }
    }

    /// The enrolled profile whose voice best matches `vector`, above the confidence
    /// threshold (else nil).
    private func bestProfile(for vector: [Float]) -> SpeakerProfile? {
        // Cross-recording, same-speaker cosine usually lands ~0.5–0.85 (mic and
        // room differ between meetings), so 0.5 recognizes reliably while staying
        // clear of the ~0.0–0.4 different-speaker range.
        let threshold: Float = 0.5
        var best: SpeakerProfile?
        var bestScore = threshold
        for profile in speakerProfiles {
            let score = SpeakerMatch.cosine(vector, profile.embedding)
            if score >= bestScore { best = profile; bestScore = score }
        }
        return best
    }

    /// Save or refine an enrolled voice for `name` using the embedding stored under
    /// `label`, then re-key the note's stored embedding to the name.
    private func enrollVoice(named name: String, fromLabel label: String) {
        var stored = note.speakerEmbeddings
        guard let vector = stored[label] ?? stored[name], !vector.isEmpty else { return }

        if let existing = speakerProfiles.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            existing.embedding = SpeakerMatch.averaged(existing.embedding, count: existing.sampleCount, with: vector)
            existing.sampleCount += 1
            existing.updatedAt = Date()
        } else {
            context.insert(SpeakerProfile(name: name, embedding: SpeakerMatch.normalized(vector)))
        }

        if label != name {
            stored[name] = vector
            stored[label] = nil
            note.speakerEmbeddings = stored
        }
    }
}

// MARK: - Note dialogs

/// Bundles the note detail's confirmations and alerts into a single modifier, so
/// the main `body` keeps a short modifier chain (see the call site).
private struct NoteDialogs: ViewModifier {
    @Binding var showClearDrawing: Bool
    @Binding var showDeleteNote: Bool
    @Binding var showingNewTag: Bool
    @Binding var newTagName: String
    @Binding var editingSpeakerID: UUID?
    @Binding var speakerDraft: String
    var onClear: () -> Void
    var onDelete: () -> Void
    var onCreateTag: () -> Void
    var onSaveSpeaker: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Clear drawing?", isPresented: $showClearDrawing, titleVisibility: .visible) {
                Button("Clear", role: .destructive) { onClear() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the Pencil strokes, shapes, and inserted images on this note. Your typed text is kept.")
            }
            .confirmationDialog("Delete this note?", isPresented: $showDeleteNote, titleVisibility: .visible) {
                Button("Delete Note", role: .destructive) { onDelete() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes the note, its handwriting, and attachments.")
            }
            .alert("New Tag", isPresented: $showingNewTag) {
                TextField("Name", text: $newTagName)
                Button("Add") { onCreateTag() }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Speaker name", isPresented: Binding(
                get: { editingSpeakerID != nil },
                set: { if !$0 { editingSpeakerID = nil } }
            )) {
                TextField("Name", text: $speakerDraft)
                Button("Save") { onSaveSpeaker() }
                Button("Cancel", role: .cancel) { editingSpeakerID = nil }
            }
    }
}

// MARK: - Read-only handwriting

/// Renders a note's saved handwriting (`PKDrawing`) as a static image, for the
/// places the live `DrawingCanvas` isn't shown: **macOS** (no Pencil input) and
/// iPhone. This is what makes ink drawn on iPad visible once it syncs to the Mac.
/// `PKDrawing` rendering is available on both UIKit and AppKit, so one view serves
/// every platform.
struct DrawingImageView: View {
    let data: Data

    var body: some View {
        if let drawing = try? PKDrawing(data: data), !drawing.bounds.isNull,
           let image = render(drawing) {
            image
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func render(_ drawing: PKDrawing) -> Image? {
        // Render from the page origin (not the stroke's own bounding box) so the
        // ink keeps its position on the page instead of jumping to the corner.
        let bounds = drawing.bounds
        let rect = CGRect(x: 0, y: 0, width: max(bounds.maxX, 1), height: max(bounds.maxY, 1))
        #if canImport(UIKit)
        return Image(uiImage: drawing.image(from: rect, scale: 2))
        #elseif canImport(AppKit)
        return Image(nsImage: drawing.image(from: rect, scale: 2))
        #endif
    }
}

// MARK: - Handwriting recognition

/// Reads the text out of a saved `PKDrawing` so the on-device summary can include
/// handwritten notes (not just typed text + transcript). Renders the strokes on
/// white and runs Vision's text recognizer (which handles handwriting).
enum HandwritingOCR {
    /// - Parameters:
    ///   - languages: preferred recognition languages (BCP-47, e.g. "en-US",
    ///     "es-ES"). Setting this is the single biggest accuracy win for non-English
    ///     handwriting. Empty = let Vision auto-detect.
    ///   - customWords: domain words (attendee names, jargon) that bias recognition
    ///     so the model spells them right.
    static func recognize(_ data: Data, languages: [String] = [], customWords: [String] = []) async -> String {
        guard let cg = renderCGImage(data) else { return "" }
        return await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            // Build and run the request *inside* the background closure so the
            // non-Sendable `VNRecognizeTextRequest` never crosses a concurrency
            // boundary (which was the "capture of non-Sendable type" warning).
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                // `.accurate` + the latest revision is the configuration tuned for
                // handwriting (vs. printed text).
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                if #available(iOS 16.0, macOS 13.0, *) {
                    request.revision = VNRecognizeTextRequestRevision3
                }
                if !languages.isEmpty { request.recognitionLanguages = languages }
                if !customWords.isEmpty { request.customWords = customWords }
                do {
                    try VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
                    let lines = (request.results ?? [])
                        .compactMap { $0.topCandidates(1).first?.string }
                    cont.resume(returning: lines.joined(separator: "\n"))
                } catch {
                    cont.resume(returning: "")
                }
            }
        }
    }

    /// Render the ink dark-on-white at 3× — more pixels per stroke and high contrast
    /// both measurably help Vision read handwriting.
    private static func renderCGImage(_ data: Data) -> CGImage? {
        guard let drawing = try? PKDrawing(data: data), !drawing.bounds.isNull else { return nil }
        let b = drawing.bounds
        let rect = CGRect(x: 0, y: 0, width: max(b.maxX, 1), height: max(b.maxY, 1))
        #if canImport(UIKit)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: rect.size, format: format).image { ctx in
            UIColor.white.setFill(); ctx.fill(rect)
            drawing.image(from: rect, scale: 3).draw(in: rect)
        }
        return image.cgImage
        #elseif canImport(AppKit)
        // Compose the strokes over a white background so Vision isn't reading ink
        // on transparency.
        let target = NSImage(size: rect.size)
        target.lockFocus()
        NSColor.white.setFill(); rect.fill()
        drawing.image(from: rect, scale: 3).draw(in: rect)
        target.unlockFocus()
        return target.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        return nil
        #endif
    }
}

// MARK: - Canvas items (images + shapes)

/// The images-and-shapes layer floating on top of the handwriting page. Items
/// render read-only on Mac/iPhone; on iPad they can be tapped to select, dragged
/// to move, resized from the corner handle, and deleted — at any time, no mode.
private struct CanvasItemsLayer: View {
    @Binding var items: [CanvasItem]
    @Binding var selectedID: UUID?
    let active: Bool
    /// The drawing canvas's scroll offset. Items are stored in page coords and
    /// rendered at (page − scroll), so they scroll *with* the ink.
    var scrollOffset: CGPoint = .zero
    let theme: Theme

    @State private var dragID: UUID?
    @State private var dragOffset: CGSize = .zero
    @State private var resizeID: UUID?
    @State private var resizeOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topLeading) {
            // While an item is selected, a full-area catcher takes taps on empty
            // space to deselect — and, paired with the canvas being disabled during
            // selection, it stops those taps from drawing underneath.
            if selectedID != nil {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { selectedID = nil }
            }
            ForEach(items) { item in itemView(item) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(active)
    }

    private func size(of item: CanvasItem) -> CGSize {
        var w = item.width, h = item.height
        if resizeID == item.id { w += resizeOffset.width; h += resizeOffset.height }
        return CGSize(width: max(40, w), height: max(40, h))
    }
    private func origin(of item: CanvasItem) -> CGPoint {
        var x = item.x, y = item.y
        if dragID == item.id { x += dragOffset.width; y += dragOffset.height }
        return CGPoint(x: max(0, x), y: max(0, y))
    }

    private func itemView(_ item: CanvasItem) -> some View {
        let s = size(of: item)
        let o = origin(of: item)
        let selected = active && selectedID == item.id
        // When selected, pad the interactive frame so the corner handles sit
        // *inside* the hittable area. Previously they hung half outside the item's
        // frame and were nearly impossible to grab — which is why resizing "didn't
        // work". `pad` is 0 when unselected so the halo never blocks drawing nearby.
        // `pad` expands the hit area so the corner handles sit inside it. Handles
        // are anchored with `.overlay(alignment:)` (not `.position`) so they always
        // land on the item's corners regardless of size — the previous `.position`
        // approach made the container greedy and the handles drifted off the item.
        let pad: CGFloat = selected ? 20 : 0
        return content(item, size: s)
            .frame(width: s.width, height: s.height)
            .overlay {
                if selected {
                    Rectangle()
                        .strokeBorder(theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                }
            }
            .padding(pad)
            .overlay(alignment: .topLeading) { if selected { deleteHandle(item) } }
            .overlay(alignment: .bottomTrailing) { if selected { resizeHandle(item) } }
            .contentShape(Rectangle())
            // page coords − scroll offset, so the item scrolls with the ink.
            .offset(x: o.x - pad - scrollOffset.x, y: o.y - pad - scrollOffset.y)
            .onTapGesture { selectedID = item.id }
            // Move is a normal gesture so the resize handle's *high-priority* gesture
            // wins when you grab the corner (otherwise the whole item just moved).
            .gesture(moveGesture(item))
    }

    @ViewBuilder
    private func content(_ item: CanvasItem, size: CGSize) -> some View {
        switch item.kind {
        case .image:
            Group {
                if let data = item.imageData, let img = AttachmentSupport.image(from: data) {
                    img.resizable().scaledToFill()
                } else {
                    theme.paperSunk
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .rectangle:
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color(hex: item.colorHex), lineWidth: 3)
                .frame(width: size.width, height: size.height)
        case .ellipse:
            Ellipse().stroke(Color(hex: item.colorHex), lineWidth: 3)
                .frame(width: size.width, height: size.height)
        case .line:
            CanvasLine().stroke(Color(hex: item.colorHex), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: size.width, height: size.height)
        case .arrow:
            CanvasArrow().stroke(Color(hex: item.colorHex), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .frame(width: size.width, height: size.height)
        }
    }

    /// Delete control — shown at the content's top-left corner (inside the padded
    /// hit frame so it's easy to tap).
    private func deleteHandle(_ item: CanvasItem) -> some View {
        Button {
            items.removeAll { $0.id == item.id }
            selectedID = nil
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 24))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, theme.rec)
        }
        .buttonStyle(.plain)
    }

    /// Resize control — at the content's bottom-right corner. A big, fully-hittable
    /// target with a high-priority drag so it beats the move gesture.
    private func resizeHandle(_ item: CanvasItem) -> some View {
        Circle().fill(theme.accent)
            .frame(width: 28, height: 28)
            .overlay(Image(systemName: "arrow.down.right.and.arrow.up.left")
                .font(.system(size: 11, weight: .bold)).foregroundStyle(.white))
            .highPriorityGesture(resizeGesture(item))
    }

    private func moveGesture(_ item: CanvasItem) -> some Gesture {
        DragGesture()
            .onChanged { v in selectedID = item.id; dragID = item.id; dragOffset = v.translation }
            .onEnded { v in
                if let i = items.firstIndex(where: { $0.id == item.id }) {
                    items[i].x = max(0, items[i].x + v.translation.width)
                    items[i].y = max(0, items[i].y + v.translation.height)
                }
                dragID = nil; dragOffset = .zero
            }
    }

    private func resizeGesture(_ item: CanvasItem) -> some Gesture {
        DragGesture()
            .onChanged { v in resizeID = item.id; resizeOffset = v.translation }
            .onEnded { v in
                if let i = items.firstIndex(where: { $0.id == item.id }) {
                    items[i].width = max(40, items[i].width + v.translation.width)
                    items[i].height = max(40, items[i].height + v.translation.height)
                }
                resizeID = nil; resizeOffset = .zero
            }
    }
}

/// A diagonal line spanning its frame (top-left → bottom-right).
private struct CanvasLine: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        return p
    }
}

/// An arrow (bottom-left → top-right) with a small head.
private struct CanvasArrow: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let start = CGPoint(x: r.minX, y: r.maxY)
        let end = CGPoint(x: r.maxX, y: r.minY)
        p.move(to: start); p.addLine(to: end)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let head = min(r.width, r.height) * 0.28
        for delta in [CGFloat.pi * 0.82, -CGFloat.pi * 0.82] {
            p.move(to: end)
            p.addLine(to: CGPoint(x: end.x + cos(angle + delta) * head,
                                  y: end.y + sin(angle + delta) * head))
        }
        return p
    }
}

// MARK: - Attachment helpers + preview

/// Cross-platform helpers for rendering attachments — kept in one place so the
/// strip tiles and the preview sheet agree on icons, thumbnails, and temp files.
enum AttachmentSupport {
    /// Whether this attachment is an image we can render a thumbnail/preview for.
    static func isImage(_ attachment: Attachment) -> Bool {
        UTType(attachment.typeIdentifier)?.conforms(to: .image) ?? false
    }

    /// Build a SwiftUI `Image` from raw bytes, using the platform's image type.
    static func image(from data: Data) -> Image? {
        #if canImport(UIKit)
        if let ui = UIImage(data: data) { return Image(uiImage: ui) }
        #elseif canImport(AppKit)
        if let ns = NSImage(data: data) { return Image(nsImage: ns) }
        #endif
        return nil
    }

    /// Downscale image bytes so a photo dropped on the page stays small enough to
    /// live inline in the note's JSON (and sync cheaply). Returns JPEG data.
    static func downscaled(_ data: Data, maxDimension: CGFloat) -> Data? {
        #if canImport(UIKit)
        guard let ui = UIImage(data: data) else { return nil }
        let longest = max(ui.size.width, ui.size.height)
        guard longest > maxDimension else { return ui.jpegData(compressionQuality: 0.7) ?? data }
        let scale = maxDimension / longest
        let target = CGSize(width: ui.size.width * scale, height: ui.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in ui.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: 0.7)
        #else
        return data   // canvas image insertion is an iPad feature; no resize needed elsewhere
        #endif
    }

    /// An SF Symbol that suits the attachment's type.
    static func icon(_ attachment: Attachment) -> String {
        guard let type = UTType(attachment.typeIdentifier) else { return "doc" }
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .pdf) { return "doc.richtext" }
        if type.conforms(to: .movie) || type.conforms(to: .audiovisualContent) { return "film" }
        if type.conforms(to: .audio) { return "waveform" }
        if type.conforms(to: .spreadsheet) { return "tablecells" }
        if type.conforms(to: .archive) { return "doc.zipper" }
        if type.conforms(to: .text) { return "doc.text" }
        return "doc"
    }

    /// Write the bytes to a temp file (named like the attachment) so it can be
    /// shared/opened in another app. Returns nil if there's nothing to write.
    static func writeTemp(_ attachment: Attachment) -> URL? {
        guard let data = attachment.data else { return nil }
        let name = attachment.filename.isEmpty ? attachment.id.uuidString : attachment.filename
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do { try data.write(to: url); return url } catch { return nil }
    }
}

/// A simple, cross-platform preview: large image for pictures, an icon + Share
/// for other files (so the user can open them in another app). No QuickLook
/// dependency, so it builds the same on iOS, iPadOS, and macOS.
private struct AttachmentPreviewSheet: View {
    let theme: Theme
    let attachment: Attachment

    @Environment(\.dismiss) private var dismiss
    @State private var shareURL: URL?

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.paperSunk)
                .navigationTitle(attachment.filename.isEmpty ? "Attachment" : attachment.filename)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                    if let shareURL {
                        #if os(macOS)
                        ToolbarItem {
                            Button { NSWorkspace.shared.open(shareURL) } label: {
                                Label("Open", systemImage: "arrow.up.forward.app")
                            }
                        }
                        #endif
                        ToolbarItem { ShareLink(item: shareURL) }
                    }
                }
                .onAppear { shareURL = AttachmentSupport.writeTemp(attachment) }
        }
        #if os(macOS)
        .frame(minWidth: 540, minHeight: 440)   // a real window, not a tiny sheet
        #endif
    }

    @ViewBuilder
    private var content: some View {
        if let data = attachment.data,
           AttachmentSupport.isImage(attachment),
           let image = AttachmentSupport.image(from: data) {
            // Fit to the window — rendering at the photo's full native size in an
            // unbounded scroll view overflows CoreGraphics (blank image).
            image
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(12)
        } else {
            VStack(spacing: 14) {
                Image(systemName: AttachmentSupport.icon(attachment))
                    .font(.system(size: 48)).foregroundStyle(theme.accent)
                Text(attachment.filename.isEmpty ? "Attachment" : attachment.filename)
                    .font(theme.bodyFont(15)).foregroundStyle(theme.ink)
                    .multilineTextAlignment(.center)
                if let shareURL {
                    #if os(macOS)
                    Button { NSWorkspace.shared.open(shareURL) } label: {
                        Label("Open in default app", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.borderedProminent).tint(theme.accent)
                    #else
                    ShareLink(item: shareURL) {
                        Label("Open / Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent).tint(theme.accent)
                    #endif
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Note.self, SpeakerProfile.self,
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
    .environment(RecordingCoordinator())
}
