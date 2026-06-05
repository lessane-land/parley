import SwiftUI

/// The home dashboard's main area: a grid of note cards. Tapping one opens the
/// editor; the left rail holds search/filters. "Dumb" — it shows what it's given.
struct NotesGridView: View {
    let theme: Theme
    let title: String
    let notes: [Note]
    let onOpen: (Note) -> Void
    let onDelete: (Note) -> Void
    let onTogglePin: (Note) -> Void

    private var columns: [GridItem] { [GridItem(.adaptive(minimum: 240), spacing: 14)] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(theme.titleFont(30, relativeTo: .largeTitle))
                        .tracking(theme.titleTracking)
                        .textCase(theme.titleUppercase ? .uppercase : nil)
                        .foregroundStyle(theme.ink)
                    Text("\(notes.count) note\(notes.count == 1 ? "" : "s")")
                        .font(theme.monoFont(12))
                        .foregroundStyle(theme.inkFaint)
                }

                if notes.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                        ForEach(notes) { note in
                            Button { onOpen(note) } label: {
                                NoteCard(theme: theme, note: note)
                            }
                            .buttonStyle(.plain)
                            // Long-press (iPad) / right-click (Mac) → actions.
                            .contextMenu {
                                Button { onTogglePin(note) } label: {
                                    Label(note.pinned ? "Unpin" : "Pin",
                                          systemImage: note.pinned ? "pin.slash" : "pin")
                                }
                                Button(role: .destructive) { onDelete(note) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .moodPaper(theme)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "note.text").font(.system(size: 40)).foregroundStyle(theme.accent)
            Text("Nothing here yet")
                .font(theme.titleFont(20, relativeTo: .title3))
                .foregroundStyle(theme.ink)
            Text("Record a meeting or create a note to get started.")
                .font(theme.bodyFont(14))
                .foregroundStyle(theme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 70)
    }
}

/// A note card in the dashboard grid: title, snippet, tags, date — uniform height.
struct NoteCard: View {
    let theme: Theme
    let note: Note

    private var snippet: String {
        note.body
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? ""
    }

    /// Small status chips derived from the note's content.
    private var metaItems: [(icon: String, text: String)] {
        var items: [(String, String)] = []
        if let start = note.startDate {
            items.append(("clock", start.formatted(date: .omitted, time: .shortened)))
        }
        if !note.transcript.isEmpty { items.append(("waveform", "Recorded")) }
        if note.summaryData != nil { items.append(("sparkles", "Summary")) }
        if !note.attendees.isEmpty { items.append(("person.2", "\(note.attendees.count)")) }
        if let attachments = note.attachments, !attachments.isEmpty {
            items.append(("paperclip", "\(attachments.count)"))
        }
        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 6) {
                Text(note.title.isEmpty ? "New Note" : note.title)
                    .font(theme.titleFont(18, relativeTo: .headline))
                    .tracking(theme.titleTracking)
                    .textCase(theme.titleUppercase ? .uppercase : nil)
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if note.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.accent)
                }
            }

            if !snippet.isEmpty {
                Text(snippet)
                    .font(theme.bodyFont(13))
                    .foregroundStyle(theme.inkSoft)
                    .lineLimit(3)
            }

            Spacer(minLength: 0)

            if !metaItems.isEmpty {
                HStack(spacing: 9) {
                    ForEach(Array(metaItems.enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 3) {
                            Image(systemName: item.icon).font(.system(size: 9))
                            Text(item.text)
                        }
                        .font(theme.monoFont(9.5, relativeTo: .caption2))
                        .foregroundStyle(theme.inkSoft)
                    }
                }
                .lineLimit(1)
            }

            if let tags = note.tags, !tags.isEmpty {
                HStack(spacing: 5) {
                    ForEach(Array(tags.prefix(3))) { tag in
                        HStack(spacing: 4) {
                            Circle().fill(tag.color).frame(width: 6, height: 6)
                            Text(tag.name).font(theme.monoFont(9.5, relativeTo: .caption2))
                        }
                        .foregroundStyle(theme.inkSoft)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(theme.paperSunk, in: Capsule())
                    }
                }
            }

            Text(note.createdAt, format: .dateTime.month().day().hour().minute())
                .font(theme.monoFont(10.5, relativeTo: .caption2))
                .foregroundStyle(theme.inkFaint)
        }
        .padding(16)
        .frame(height: 192, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moodCard(theme)
        .overlay {
            // Pinned notes read differently in the dashboard.
            if note.pinned {
                RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                    .strokeBorder(theme.accent, lineWidth: 2)
            }
        }
    }
}
