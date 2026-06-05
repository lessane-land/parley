import SwiftUI

/// The "Granola magic" surface: generate (and re-generate) an on-device summary
/// of a note's typed notes + transcript, and send its action items to Reminders.
struct SummaryView: View {
    let theme: Theme
    @Bindable var note: Note
    let service: SummaryService
    let onAddReminders: ([String]) async -> Int

    @Environment(\.dismiss) private var dismiss
    @State private var summary: MeetingSummary?
    @State private var remindersAdded: Int?

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
                    section("Overview", icon: "text.alignleft") {
                        Text(summary.overview)
                            .font(theme.bodyFont(15))
                            .foregroundStyle(theme.ink2)
                    }
                }
                if !summary.decisions.isEmpty {
                    section("Decisions", icon: "checkmark.seal") {
                        bullets(summary.decisions)
                    }
                }
                if !summary.actionItems.isEmpty {
                    section("Action items", icon: "checklist") {
                        VStack(alignment: .leading, spacing: 10) {
                            bullets(summary.actionItems)
                            Button { Task { await addReminders(summary.actionItems) } } label: {
                                Label(remindersAdded.map { "Added \($0) to Reminders" } ?? "Send to Reminders",
                                      systemImage: remindersAdded == nil ? "plus.circle" : "checkmark.circle")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .tint(theme.accent)
                            .disabled(remindersAdded != nil)
                        }
                    }
                }
                if !summary.openQuestions.isEmpty {
                    section("Open questions", icon: "questionmark.circle") {
                        bullets(summary.openQuestions)
                    }
                }
            }
            .padding(16)
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
        remindersAdded = nil
        let result = await service.summarize(notes: note.body, transcript: note.transcript)
        if let result {
            summary = result
            note.summaryData = try? JSONEncoder().encode(result)
        }
    }

    private func addReminders(_ items: [String]) async {
        remindersAdded = await onAddReminders(items)
    }
}
