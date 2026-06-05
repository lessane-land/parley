import SwiftUI

/// The "Granola magic" surface: generate (and re-generate) an on-device summary
/// of a note's typed notes + transcript. Action items are checkable, carry an
/// owner, and can be pushed to Reminders individually or all at once.
struct SummaryView: View {
    let theme: Theme
    @Bindable var note: Note
    let service: SummaryService
    let onAddReminders: ([String]) async -> Int

    @Environment(\.dismiss) private var dismiss
    @State private var summary: MeetingSummary?
    @State private var remindedTitles: Set<String> = []

    var body: some View {
        NavigationStack {
            content
                .background(theme.paperSunk)
                .navigationTitle("Summary")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
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
                    section("Decisions", icon: "checkmark.seal") { bullets(summary.decisions) }
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
        let result = await service.summarize(notes: note.body, transcript: note.transcript, attendees: note.attendees)
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
