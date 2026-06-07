import SwiftUI
import SwiftData

/// The wrap-up surface: generate (and re-generate) an on-device summary
/// of a note's typed notes + transcript. A first-class *pushed* screen in the
/// note's navigation stack (it relies on the host's back button). Action items
/// are checkable, carry an owner, and can be pushed to Reminders individually or
/// all at once.
struct SummaryView: View {
    let theme: Theme
    @Bindable var note: Note
    let service: SummaryService
    let onAddReminders: ([ReminderDraft]) async -> Int
    var onOpenNotes: () -> Void = {}        // jump back to the note's typed/handwritten notes
    var onOpenTranscript: () -> Void = {}   // jump back to the transcript

    @Environment(ThemeManager.self) private var themeManager
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var hSize
    #endif
    @State private var summary: MeetingSummary?
    @State private var remindedTitles: Set<String> = []
    /// Which action item's date picker popover is open (by id), if any.
    @State private var editingDueID: ActionItem.ID?
    /// Editing the wrap-up's main text in place.
    @State private var editingOverview = false

    /// Two-way binding to the summary's overview (the editable main text).
    private var overviewBinding: Binding<String> {
        Binding(
            get: { summary?.overview ?? "" },
            set: { newValue in
                guard var s = summary else { return }
                s.overview = newValue
                summary = s
                persist()
            }
        )
    }

    /// Two columns (doc + sources) when wide; stacked otherwise.
    private var isWide: Bool {
        #if os(iOS)
        hSize == .regular
        #else
        true
        #endif
    }

    var body: some View {
        content
            .background(theme.paperSunk)
            .navigationTitle("Wrap-up")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if let summary {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: shareText(summary)) { Label("Share", systemImage: "square.and.arrow.up") }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button { Task { await generate() } } label: {
                            Label("Regenerate", systemImage: "arrow.clockwise")
                        }
                        .disabled(service.state == .working)
                    }
                }
            }
            .onAppear {
                if let data = note.summaryData {
                    summary = try? JSONDecoder().decode(MeetingSummary.self, from: data)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch service.state {
        case .working:
            centered {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Wrapping up on device…")
                        .font(theme.bodyFont(14))
                        .foregroundStyle(theme.inkSoft)
                }
            }
        case .unavailable(let reason):
            message("Wrap-up unavailable", reason, "sparkles.slash")
        case .idle:
            if let summary {
                summaryBody(summary)
            } else {
                emptyPrompt
            }
        }
    }

    private var emptyPrompt: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles").font(.system(size: 34)).foregroundStyle(theme.accent)
            Text("Wrap up on device")
                .font(theme.titleFont(20, relativeTo: .title3))
                .foregroundStyle(theme.ink)
            Text("Merge your notes, photos, and the transcript into a structured wrap-up — decisions, action items, and open questions — entirely on device.")
                .font(theme.bodyFont(14))
                .foregroundStyle(theme.inkSoft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button { Task { await generate() } } label: {
                Label("Generate wrap-up", systemImage: "sparkles")
                    .font(.headline)
                    .padding(.horizontal, 18).padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: Summary document (the design's two-column layout)

    private func summaryBody(_ summary: MeetingSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                summaryHeader
                if isWide {
                    HStack(alignment: .top, spacing: 26) {
                        docColumn(summary).frame(maxWidth: .infinity, alignment: .leading)
                        sidebar(summary).frame(width: 300)
                    }
                } else {
                    docColumn(summary).frame(maxWidth: .infinity, alignment: .leading)
                    sidebar(summary).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
        }
    }

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(note.title.isEmpty ? "Untitled" : note.title)
                .font(theme.titleFont(26, relativeTo: .title))
                .tracking(theme.titleTracking)
                .textCase(theme.titleUppercase ? .uppercase : nil)
                .foregroundStyle(theme.ink)
            HStack(spacing: 8) {
                Text((note.startDate ?? note.createdAt), format: .dateTime.weekday().month().day())
                if !note.attendees.isEmpty {
                    Text("·")
                    Text("\(note.attendees.count) people")
                }
            }
            .font(theme.monoFont(11))
            .foregroundStyle(theme.inkFaint)
            Label("Wrapped up on device", systemImage: "sparkles")
                .font(theme.monoFont(10, relativeTo: .caption2))
                .foregroundStyle(theme.accentInk)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(theme.accentTint, in: Capsule())
        }
    }

    // MARK: Doc column

    @ViewBuilder
    private func docColumn(_ summary: MeetingSummary) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Wrap-up", systemImage: "sparkles")
                        .font(theme.monoFont(11)).tracking(1.4).foregroundStyle(theme.accentInk)
                    Spacer()
                    Button { withAnimation(.snappy) { editingOverview.toggle() } } label: {
                        Label(editingOverview ? "Done" : "Edit",
                              systemImage: editingOverview ? "checkmark" : "pencil")
                            .font(theme.bodyFont(12).weight(.semibold))
                            .foregroundStyle(theme.accentInk)
                    }
                    .buttonStyle(.plain)
                }
                if editingOverview {
                    let shape = RoundedRectangle(cornerRadius: theme.cornerRadius == 0 ? 0 : 10)
                    TextEditor(text: overviewBinding)
                        .font(theme.titleFont(21, relativeTo: .title3))
                        .foregroundStyle(theme.ink)
                        .lineSpacing(3)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 140)
                        .padding(10)
                        .background(theme.paperRaised, in: shape)
                        .overlay(shape.strokeBorder(theme.accentLine, lineWidth: max(1, theme.borderWidth)))
                } else if !summary.overview.isEmpty {
                    Text(summary.overview)
                        .font(theme.titleFont(21, relativeTo: .title3))
                        .foregroundStyle(theme.ink)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .onTapGesture { withAnimation(.snappy) { editingOverview = true } }
                } else {
                    Text("Tap Edit to write the wrap-up yourself…")
                        .font(theme.bodyFont(14)).italic().foregroundStyle(theme.inkFaint)
                        .onTapGesture { withAnimation(.snappy) { editingOverview = true } }
                }
            }
            if !summary.decisions.isEmpty { decisionsSection(summary.decisions) }
            if !summary.actionItems.isEmpty { actionItemsSection(summary) }
            if !summary.openQuestions.isEmpty { openQuestionsSection(summary.openQuestions) }
        }
    }

    private func decisionsSection(_ decisions: [Decision]) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionHeader("Decisions", count: decisions.count)
            ForEach(decisions) { decision in
                HStack(alignment: .top, spacing: 10) {
                    decisionMark
                    VStack(alignment: .leading, spacing: 3) {
                        Text(decision.text)
                            .font(theme.bodyFont(15)).foregroundStyle(theme.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                        if !decision.rationale.isEmpty {
                            Text(decision.rationale)
                                .font(theme.bodyFont(12.5)).foregroundStyle(theme.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func actionItemsSection(_ summary: MeetingSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Action items", count: summary.actionItems.count)
            ForEach(summary.actionItems) { item in actionRow(item) }
            Button { Task { await remind(summary.actionItems) } } label: {
                Label("Send all to Reminders", systemImage: "plus.circle")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(theme.accent)
            .padding(.top, 2)
        }
    }

    private func actionRow(_ item: ActionItem) -> some View {
        HStack(spacing: 10) {
            Button { toggleDone(item) } label: { checkbox(item.done) }.buttonStyle(.plain)
            Text(item.title)
                .font(theme.bodyFont(14))
                .foregroundStyle(item.done ? theme.inkFaint : theme.ink2)
                .strikethrough(item.done)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !item.owner.isEmpty { avatar(item.owner, size: 22) }
            dueChip(item)
            remindButton(item)
        }
        .padding(12)
        .moodCard(theme)
    }

    /// A tappable due chip: shows the user-set date if any, else the model's text
    /// hint, else a "Due" affordance. Tapping opens a date picker to set/clear it.
    private func dueChip(_ item: ActionItem) -> some View {
        let hasDate = item.dueDate != nil
        let label = item.dueDate.map { $0.formatted(.dateTime.month(.abbreviated).day()) }
            ?? (item.due.flatMap { $0.isEmpty ? nil : $0 } ?? "Due")
        return Button { editingDueID = item.id } label: {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                Text(label)
            }
            .font(theme.monoFont(10, relativeTo: .caption2))
            .foregroundStyle(hasDate ? theme.accentInk : theme.inkSoft)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(hasDate ? theme.accentTint : theme.paperSunk, in: Capsule())
            .overlay(Capsule().strokeBorder(hasDate ? theme.accentLine : theme.edge, lineWidth: theme.borderWidth))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hasDate ? "Change due date" : "Set due date")
        .popover(isPresented: Binding(
            get: { editingDueID == item.id },
            set: { if !$0 && editingDueID == item.id { editingDueID = nil } }
        )) { duePicker(item) }
    }

    private func duePicker(_ item: ActionItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DUE DATE").font(theme.monoFont(11)).tracking(1.4).foregroundStyle(theme.inkSoft)
            DatePicker("Due", selection: Binding(
                get: { item.dueDate ?? Calendar.current.startOfDay(for: Date()) },
                set: { setDue(item, $0) }
            ), displayedComponents: [.date])
            .datePickerStyle(.graphical)
            .labelsHidden()
            .tint(theme.accent)
            HStack {
                if item.dueDate != nil {
                    Button(role: .destructive) { setDue(item, nil); editingDueID = nil } label: { Text("Clear") }
                }
                Spacer()
                Button { editingDueID = nil } label: { Text("Done").font(.subheadline.weight(.semibold)) }
            }
        }
        .padding(16)
        .frame(width: 300)
        .background(theme.paperRaised)
    }

    private func remindButton(_ item: ActionItem) -> some View {
        let added = remindedTitles.contains(item.title)
        return Button { Task { await remind([item]) } } label: {
            Image(systemName: added ? "checkmark.circle.fill" : "bell.badge.plus")
                .font(.system(size: 16))
                .foregroundStyle(added ? theme.accent : theme.inkSoft)
        }
        .buttonStyle(.plain)
        .disabled(added)
        .accessibilityLabel(added ? "Added to Reminders" : "Add to Reminders")
    }

    private func openQuestionsSection(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Open questions", count: items.count)
            bullets(items)
        }
    }

    // MARK: Sidebar (sources + key moments)

    @ViewBuilder
    private func sidebar(_ summary: MeetingSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sideHeader("Sources")
            sourceRow(icon: "pencil", title: "My notes", subtitle: notesSubtitle, action: onOpenNotes)
            sourceRow(icon: "waveform", title: "Full transcript", subtitle: transcriptSubtitle, action: onOpenTranscript)
            if !summary.keyQuotes.isEmpty {
                sideHeader("Key moments").padding(.top, 6)
                ForEach(summary.keyQuotes) { quoteRow($0) }
            }
            Label("Generated on this device · no cloud, no account", systemImage: "bolt.fill")
                .font(theme.bodyFont(10.5)).foregroundStyle(theme.inkFaint)
                .padding(.top, 8)
        }
    }

    private func sourceRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .foregroundStyle(theme.accentInk)
                    .frame(width: 32, height: 32)
                    .background(theme.accentTint, in: RoundedRectangle(cornerRadius: theme.cornerRadius == 0 ? 0 : 8, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(theme.bodyFont(13).weight(.semibold)).foregroundStyle(theme.ink)
                    Text(subtitle).font(theme.bodyFont(11)).foregroundStyle(theme.inkFaint)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.inkFaint)
            }
            .padding(11)
            .moodCard(theme)
        }
        .buttonStyle(.plain)
    }

    private func quoteRow(_ quote: KeyQuote) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Capsule().fill(theme.accent).frame(width: 2.5)
            VStack(alignment: .leading, spacing: 5) {
                Text("“\(quote.text)”")
                    .font(theme.bodyFont(13)).italic().foregroundStyle(theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                if !quote.speaker.isEmpty {
                    HStack(spacing: 6) {
                        avatar(quote.speaker, size: 16)
                        Text(quote.speaker).font(theme.monoFont(10, relativeTo: .caption2)).foregroundStyle(theme.inkSoft)
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Small pieces

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(theme.titleFont(16, relativeTo: .headline))
                .tracking(theme.titleTracking)
                .textCase(theme.titleUppercase ? .uppercase : nil)
                .foregroundStyle(theme.ink)
            Text("\(count)")
                .font(theme.monoFont(10.5, relativeTo: .caption2)).foregroundStyle(theme.inkSoft)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(theme.paperRaised, in: Capsule())
                .overlay(Capsule().strokeBorder(theme.edge, lineWidth: theme.borderWidth))
        }
    }

    private func sideHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(theme.monoFont(10.5)).tracking(1.4).foregroundStyle(theme.inkFaint)
    }

    private var decisionMark: some View {
        let shape = RoundedRectangle(cornerRadius: theme.cornerRadius == 0 ? 0 : 5, style: .continuous)
        return shape.fill(theme.accentTint)
            .frame(width: 20, height: 20)
            .overlay(shape.strokeBorder(theme.accent, lineWidth: 1.5))
            .overlay(Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(theme.accentInk))
            .padding(.top, 1)
    }

    private func checkbox(_ done: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.cornerRadius == 0 ? 0 : 5, style: .continuous)
        return shape.fill(done ? theme.accent : Color.clear)
            .frame(width: 20, height: 20)
            .overlay(shape.strokeBorder(done ? theme.accent : theme.inkGhost, lineWidth: 1.8))
            .overlay { if done { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white) } }
    }

    private func avatar(_ name: String, size: CGFloat) -> some View {
        Text(Self.initials(name))
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(theme.accent, in: Circle())
    }

    private var notesSubtitle: String {
        var parts: [String] = []
        if !note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append("Typed") }
        if note.drawing != nil { parts.append("handwritten") }
        return parts.isEmpty ? "Empty" : parts.joined(separator: " + ")
    }

    private var transcriptSubtitle: String {
        guard !note.transcript.isEmpty else { return "No transcript" }
        let words = note.transcript.split(whereSeparator: { $0 == " " || $0.isNewline }).count
        let speakers = Set(note.transcriptSegments.compactMap(\.speaker)).count
        return speakers > 0 ? "\(words) words · \(speakers) speakers" : "\(words) words"
    }

    static func initials(_ name: String) -> String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return (letters.isEmpty ? String(name.prefix(1)) : letters).uppercased()
    }

    private func shareText(_ summary: MeetingSummary) -> String {
        var lines: [String] = [note.title.isEmpty ? "Wrap-up" : note.title, ""]
        if !summary.overview.isEmpty { lines.append(summary.overview); lines.append("") }
        if !summary.decisions.isEmpty {
            lines.append("DECISIONS")
            lines.append(contentsOf: summary.decisions.map { "• \($0.text)" })
            lines.append("")
        }
        if !summary.actionItems.isEmpty {
            lines.append("ACTION ITEMS")
            lines.append(contentsOf: summary.actionItems.map { item in
                let dueText = item.dueDate.map { $0.formatted(date: .abbreviated, time: .omitted) }
                    ?? item.due.flatMap { $0.isEmpty ? nil : $0 }
                return "□ \(item.title)"
                    + (item.owner.isEmpty ? "" : " — \(item.owner)")
                    + (dueText.map { " (\($0))" } ?? "")
            })
            lines.append("")
        }
        if !summary.openQuestions.isEmpty {
            lines.append("OPEN QUESTIONS")
            lines.append(contentsOf: summary.openQuestions.map { "• \($0)" })
        }
        return lines.joined(separator: "\n")
    }

    private func bullets(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(theme.accent).frame(width: 5, height: 5).padding(.top, 7)
                    Text(item).font(theme.bodyFont(15)).foregroundStyle(theme.ink2)
                }
            }
        }
    }

    private func centered<V: View>(@ViewBuilder _ inner: () -> V) -> some View {
        inner().frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func message(_ title: String, _ detail: String, _ icon: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 32)).foregroundStyle(theme.inkFaint)
            Text(title).font(theme.titleFont(18, relativeTo: .headline)).foregroundStyle(theme.ink)
            Text(detail).font(theme.bodyFont(13)).foregroundStyle(theme.inkSoft)
                .multilineTextAlignment(.center).frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: Actions

    private func generate() async {
        remindedTitles = []
        // Include recognized handwriting so the summary reads pen notes too.
        let languages = (themeManager.transcriptionLanguage?.isEmpty == false)
            ? [themeManager.transcriptionLanguage!] : []
        var notesText = note.body
        if let drawing = note.drawing {
            let handwritten = await HandwritingOCR.recognize(
                drawing, languages: languages, customWords: note.attendees)
            if !handwritten.isEmpty { notesText += (notesText.isEmpty ? "" : "\n") + handwritten }
        }
        // Fold in text recognized from attached photos/scans too.
        for attachment in (note.attachments ?? []) where AttachmentSupport.isImage(attachment) {
            var ocr = attachment.ocrText ?? ""
            if ocr.isEmpty, let data = attachment.data {
                ocr = await HandwritingOCR.recognizeImage(data, languages: languages, customWords: note.attendees)
                if !ocr.isEmpty { attachment.ocrText = ocr }
            }
            if !ocr.isEmpty { notesText += (notesText.isEmpty ? "" : "\n") + ocr }
        }
        // Meeting = more than one speaker (or attendee); otherwise it's just notes.
        let speakers = Set(note.transcriptSegments.compactMap(\.speaker).filter { !$0.isEmpty })
        let isMeeting = speakers.count >= 2 || note.attendees.count >= 2
        let result = await service.summarize(
            notes: notesText, transcript: note.transcript, attendees: note.attendees,
            isMeeting: isMeeting,
            tone: themeManager.summaryTone,
            includeDecisions: themeManager.extractDecisions,
            includeActionItems: themeManager.extractActionItems,
            includeOpenQuestions: themeManager.extractOpenQuestions,
            includeKeyQuotes: themeManager.extractKeyQuotes
        )
        if let result {
            summary = result
            persist()
        }
    }

    private func toggleDone(_ item: ActionItem) {
        guard var current = summary,
              let index = current.actionItems.firstIndex(where: { $0.id == item.id }) else { return }
        current.actionItems[index].done.toggle()
        summary = current
        persist()
    }

    private func setDue(_ item: ActionItem, _ date: Date?) {
        guard var current = summary,
              let index = current.actionItems.firstIndex(where: { $0.id == item.id }) else { return }
        current.actionItems[index].dueDate = date
        summary = current
        persist()
    }

    private func remind(_ items: [ActionItem]) async {
        let drafts = items.map { ReminderDraft(title: $0.title, due: $0.dueDate) }
        let count = await onAddReminders(drafts)
        if count > 0 { remindedTitles.formUnion(items.map(\.title)) }
    }

    private func persist() {
        note.summaryData = try? JSONEncoder().encode(summary)
    }
}

// MARK: - Ask Parley (chat)

/// The design's "Ask Parley" companion: a chat that answers questions about all
/// your notes, **entirely on device**. Grounds the model in your notes, shows
/// the sources it leaned on, and offers a few starter prompts.
struct ChatView: View {
    let theme: Theme
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]

    @State private var service = AskService()
    @State private var input = ""
    @State private var didStart = false

    private let suggestions = ["Open action items", "What's still undecided?", "Wrap up this week"]

    var body: some View {
        VStack(spacing: 0) {
            subtitleStrip
            feed
            composer
        }
        .background(theme.paperSunk)
        .onAppear {
            guard !didStart else { return }
            didStart = true
            service.start(context: buildContext())
        }
    }

    private var subtitleStrip: some View {
        HStack(spacing: 7) {
            Image(systemName: "sparkles").foregroundStyle(theme.accent)
            Text("Across all your notes · on device")
                .font(theme.monoFont(11)).foregroundStyle(theme.inkFaint)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: theme.borderWidth) }
    }

    // MARK: Feed

    private var feed: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if service.messages.isEmpty { emptyState }
                    ForEach(service.messages) { bubble($0) }
                    if service.state == .thinking { thinkingRow }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(16)
            }
            .onChange(of: service.messages.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if case .unavailable(let reason) = service.state {
            message("Ask Parley unavailable", reason, "sparkles.slash")
        } else {
            message("Ask about your meetings",
                    "Try a prompt below, or ask anything — answers come only from your notes, on this device.",
                    "bubble.left.and.text.bubble.right")
        }
    }

    private func message(_ title: String, _ detail: String, _ icon: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 30)).foregroundStyle(theme.accent)
            Text(title).font(theme.titleFont(17, relativeTo: .headline)).foregroundStyle(theme.ink)
            Text(detail).font(theme.bodyFont(13)).foregroundStyle(theme.inkSoft)
                .multilineTextAlignment(.center).frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private func bubble(_ msg: ChatMessage) -> some View {
        let isUser = msg.role == .user
        return HStack(spacing: 0) {
            if isUser { Spacer(minLength: 44) }
            VStack(alignment: .leading, spacing: 9) {
                Text(msg.text)
                    .font(theme.bodyFont(13))
                    .foregroundStyle(isUser ? Color.white : theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                if !msg.sources.isEmpty { citeList(msg.sources) }
            }
            .padding(.horizontal, 13).padding(.vertical, 10)
            .background(isUser ? theme.accent : theme.paperRaised, in: bubbleShape(isUser: isUser))
            .overlay {
                if !isUser { bubbleShape(isUser: false).strokeBorder(theme.edge, lineWidth: theme.borderWidth) }
            }
            if !isUser { Spacer(minLength: 44) }
        }
    }

    private func bubbleShape(isUser: Bool) -> UnevenRoundedRectangle {
        let r: CGFloat = theme.cornerRadius == 0 ? 0 : 13
        let small: CGFloat = theme.cornerRadius == 0 ? 0 : 4
        return UnevenRoundedRectangle(
            topLeadingRadius: r,
            bottomLeadingRadius: isUser ? r : small,
            bottomTrailingRadius: isUser ? small : r,
            topTrailingRadius: r,
            style: .continuous
        )
    }

    private func citeList(_ sources: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(sources, id: \.self) { src in
                Label(src, systemImage: "doc.text")
                    .font(theme.monoFont(10, relativeTo: .caption2))
                    .foregroundStyle(theme.accentInk)
                    .lineLimit(1)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(theme.accentTint, in: Capsule())
                    .overlay(Capsule().strokeBorder(theme.accentLine, lineWidth: theme.borderWidth))
            }
        }
    }

    private var thinkingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Thinking…").font(theme.bodyFont(12)).foregroundStyle(theme.inkFaint)
            Spacer()
        }
    }

    // MARK: Composer

    private var composer: some View {
        VStack(spacing: 10) {
            if service.isReady {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(suggestions, id: \.self) { prompt in
                            Button { send(prompt) } label: {
                                Text(prompt)
                                    .font(theme.bodyFont(12).weight(.semibold))
                                    .foregroundStyle(theme.inkSoft)
                                    .padding(.horizontal, 11).padding(.vertical, 6)
                                    .background(theme.paperRaised, in: Capsule())
                                    .overlay(Capsule().strokeBorder(theme.edge, lineWidth: theme.borderWidth))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            inputRow
            HStack(spacing: 7) {
                Image(systemName: "bolt.fill").foregroundStyle(theme.accent)
                Text("Answers stay on this device").font(theme.bodyFont(11)).foregroundStyle(theme.inkFaint)
                Spacer()
            }
        }
        .padding(16)
        .background(theme.paperRaised)
        .overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: theme.borderWidth) }
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField("Ask about your notes…", text: $input)
                .textFieldStyle(.plain)
                .font(theme.bodyFont(13))
                .padding(.horizontal, 14).frame(height: 42)
                .background(theme.paper, in: fieldShape)
                .overlay(fieldShape.strokeBorder(theme.edge, lineWidth: theme.borderWidth))
                .onSubmit { send(input) }
                .disabled(!service.isReady)

            Button { send(input) } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(theme.accent, in: fieldShape)
            }
            .buttonStyle(.plain)
            .disabled(!service.isReady || input.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var fieldShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.cornerRadius == 0 ? 0 : 11, style: .continuous)
    }

    // MARK: Actions

    private func send(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        input = ""
        Task { await service.ask(q) }
    }

    /// Fold a capped slice of the notes into a grounding corpus (kept small to fit
    /// the on-device model's context window).
    private func buildContext() -> String {
        notes.prefix(12).map { note in
            var parts = ["NOTE: \(note.title.isEmpty ? "Untitled note" : note.title)"]
            let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { parts.append("Notes: " + String(body.prefix(400))) }
            let transcript = note.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !transcript.isEmpty { parts.append("Transcript: " + String(transcript.prefix(600))) }
            return parts.joined(separator: "\n")
        }
        .joined(separator: "\n\n---\n\n")
    }
}
