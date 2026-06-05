import SwiftUI
import SwiftData

/// The "Granola magic" surface: generate (and re-generate) an on-device summary
/// of a note's typed notes + transcript. A first-class *pushed* screen in the
/// note's navigation stack (it relies on the host's back button). Action items
/// are checkable, carry an owner, and can be pushed to Reminders individually or
/// all at once.
struct SummaryView: View {
    let theme: Theme
    @Bindable var note: Note
    let service: SummaryService
    let onAddReminders: ([String]) async -> Int

    @Environment(ThemeManager.self) private var themeManager
    @State private var summary: MeetingSummary?
    @State private var remindedTitles: Set<String> = []

    var body: some View {
        content
            .background(theme.paperSunk)
            .navigationTitle("Summary")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if summary != nil {
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
                    Text("Summarizing on device…")
                        .font(theme.bodyFont(14))
                        .foregroundStyle(theme.inkSoft)
                }
            }
        case .unavailable(let reason):
            message("Summary unavailable", reason, "sparkles.slash")
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
            Text("Granola magic")
                .font(theme.titleFont(20, relativeTo: .title3))
                .foregroundStyle(theme.ink)
            Text("Merge your notes and the transcript into a structured summary — decisions, action items, and open questions — entirely on device.")
                .font(theme.bodyFont(14))
                .foregroundStyle(theme.inkSoft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button { Task { await generate() } } label: {
                Label("Generate summary", systemImage: "sparkles")
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

    private func summaryBody(_ summary: MeetingSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !summary.overview.isEmpty {
                    // Lede — larger, no card, the way the design opens a summary.
                    Text(summary.overview)
                        .font(theme.titleFont(20, relativeTo: .title3))
                        .foregroundStyle(theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !summary.decisions.isEmpty {
                    section("Decisions", icon: "checkmark.seal") { decisionsView(summary.decisions) }
                }

                if !summary.actionItems.isEmpty {
                    section("Action items", icon: "checklist") { actionItemsView(summary) }
                }

                if !summary.openQuestions.isEmpty {
                    section("Open questions", icon: "questionmark.circle") { bullets(summary.openQuestions) }
                }
            }
            .padding(16)
        }
    }

    private func actionItemsView(_ summary: MeetingSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(summary.actionItems) { item in
                HStack(alignment: .top, spacing: 10) {
                    Button { toggleDone(item) } label: {
                        Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(item.done ? theme.accent : theme.inkFaint)
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(theme.bodyFont(15))
                            .foregroundStyle(item.done ? theme.inkFaint : theme.ink2)
                            .strikethrough(item.done)
                        if !item.owner.isEmpty {
                            Label(item.owner, systemImage: "person")
                                .font(theme.monoFont(10.5, relativeTo: .caption2))
                                .foregroundStyle(theme.accentInk)
                        }
                    }

                    Spacer(minLength: 8)

                    Button { Task { await remind([item.title]) } } label: {
                        Image(systemName: remindedTitles.contains(item.title) ? "checkmark.circle" : "bell.badge.plus")
                            .foregroundStyle(theme.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(remindedTitles.contains(item.title))
                    .accessibilityLabel("Add to Reminders")
                }
            }

            Divider().overlay(theme.line)

            Button { Task { await remind(summary.actionItems.map(\.title)) } } label: {
                Label("Send all to Reminders", systemImage: "plus.circle")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(theme.accent)
        }
    }

    private func decisionsView(_ decisions: [Decision]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(decisions) { decision in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.subheadline)
                        .foregroundStyle(theme.accent)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(decision.text)
                            .font(theme.bodyFont(15))
                            .foregroundStyle(theme.ink2)
                        if !decision.rationale.isEmpty {
                            Text(decision.rationale)
                                .font(theme.bodyFont(13))
                                .foregroundStyle(theme.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    // MARK: Building blocks

    private func section<V: View>(_ title: String, icon: String, @ViewBuilder _ inner: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(theme.monoFont(11))
                .tracking(1.2)
                .foregroundStyle(theme.inkSoft)
            inner()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moodCard(theme)
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
        let result = await service.summarize(
            notes: note.body, transcript: note.transcript, attendees: note.attendees,
            tone: themeManager.summaryTone,
            includeDecisions: themeManager.extractDecisions,
            includeActionItems: themeManager.extractActionItems,
            includeOpenQuestions: themeManager.extractOpenQuestions
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

    private func remind(_ titles: [String]) async {
        let count = await onAddReminders(titles)
        if count > 0 { remindedTitles.formUnion(titles) }
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

    private let suggestions = ["Open action items", "What's still undecided?", "Summarize this week"]

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
