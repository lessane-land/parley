import SwiftUI

/// Shows action items detected in the note (typed notes + transcript), lets the
/// user pick which to send to Reminders. Detection is a Phase 3 heuristic;
/// Phase 4 swaps in real on-device extraction.
struct ActionItemsSheet: View {
    let theme: Theme
    let detected: [String]
    let access: EventKitService.Access
    /// Reports the chosen items; returns how many reminders were written.
    let onAdd: ([String]) async -> Int

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<Int> = []
    @State private var working = false
    @State private var resultCount: Int?

    var body: some View {
        NavigationStack {
            content
                .background(theme.paperSunk)
                .navigationTitle("Action items")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(addLabel) { Task { await add() } }
                            .disabled(selected.isEmpty || working)
                    }
                }
                .onAppear { selected = Set(detected.indices) } // all on by default
        }
    }

    @ViewBuilder
    private var content: some View {
        if let resultCount {
            message("Added \(resultCount) to Reminders",
                    resultCount > 0 ? "Find them in the Reminders app." : "Nothing was written.",
                    "checkmark.circle")
        } else if detected.isEmpty {
            message("No action items found",
                    "Tip: prefix a line with “- ”, “TODO:”, or “Action:”, and it'll be picked up here.",
                    "checklist")
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(detected.enumerated()), id: \.offset) { index, item in
                        Button {
                            if selected.contains(index) { selected.remove(index) } else { selected.insert(index) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selected.contains(index) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selected.contains(index) ? theme.accent : theme.inkFaint)
                                Text(item)
                                    .font(theme.bodyFont(15))
                                    .foregroundStyle(theme.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(14)
                            .moodCard(theme)
                        }
                        .buttonStyle(.plain)
                    }

                    if access == .denied {
                        Text("Reminders access is off — enable it in Settings.")
                            .font(theme.bodyFont(12))
                            .foregroundStyle(theme.rec)
                            .padding(.top, 4)
                    }
                }
                .padding(16)
            }
        }
    }

    private var addLabel: String {
        working ? "Adding…" : "Add \(selected.count)"
    }

    private func add() async {
        working = true
        let items = detected.enumerated().filter { selected.contains($0.offset) }.map(\.element)
        resultCount = await onAdd(items)
        working = false
    }

    private func message(_ title: String, _ detail: String, _ icon: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 32)).foregroundStyle(theme.inkFaint)
            Text(title).font(theme.titleFont(18, relativeTo: .headline)).foregroundStyle(theme.ink)
            Text(detail).font(theme.bodyFont(13)).foregroundStyle(theme.inkSoft)
                .multilineTextAlignment(.center).frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
