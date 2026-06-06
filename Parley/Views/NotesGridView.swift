import SwiftUI

/// The home dashboard's main area: a grid of note cards. Tapping one opens the
/// editor; the left rail holds search/filters. "Dumb" — it shows what it's given.
struct NotesGridView: View {
    let theme: Theme
    let mood: Mood
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
                    // Pinned notes are the design's wide "feature" cards — they span
                    // the row above the regular grid (the prototype's 2-col hero).
                    if !pinnedNotes.isEmpty {
                        VStack(spacing: 14) {
                            ForEach(pinnedNotes) { cardButton($0) }
                        }
                    }
                    if !otherNotes.isEmpty {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                            ForEach(otherNotes) { cardButton($0) }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .moodPaper(theme)
    }

    private var pinnedNotes: [Note] { notes.filter(\.pinned) }
    private var otherNotes: [Note] { notes.filter { !$0.pinned } }

    /// A tappable card with the pin/delete context menu.
    private func cardButton(_ note: Note) -> some View {
        Button { onOpen(note) } label: {
            NoteCard(theme: theme, mood: mood, note: note)
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

/// A note card in the dashboard grid, matching the prototype's `.pk-card`:
/// an accent date line on top, a serif title, a snippet, and a foot of attendee
/// avatars + meta chips. A **pinned** note becomes the prototype's `.feature`
/// card, whose treatment is mood-specific (see `CardSurface`).
struct NoteCard: View {
    let theme: Theme
    let mood: Mood
    let note: Note

    /// Pinned notes render as the design's wider "feature" card.
    private var feature: Bool { note.pinned }

    /// Only the neubrutalist feature card inverts to white-on-accent.
    private var onAccent: Bool { mood == .neubrutalist && feature }

    private var snippet: String {
        note.body
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dateLine
            Text(note.title.isEmpty ? "New Note" : note.title)
                .font(theme.titleFont(feature ? 22 : 18, relativeTo: .headline))
                .tracking(theme.titleTracking)
                .textCase(theme.titleUppercase ? .uppercase : nil)
                .foregroundStyle(onAccent ? .white : theme.ink)
                .lineLimit(2)
                .padding(.bottom, 7)

            if !snippet.isEmpty {
                Text(snippet)
                    .font(theme.bodyFont(13))
                    .foregroundStyle(onAccent ? .white.opacity(0.9) : theme.inkSoft)
                    .lineLimit(feature ? 3 : 2)
            }

            Spacer(minLength: 10)
            foot
        }
        .padding(16)
        .frame(height: feature ? 220 : 190, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(CardSurface(theme: theme, mood: mood, feature: feature))
        // The prototype's `.hw-flag`: a faint accent mark for handwritten notes.
        .overlay(alignment: .topTrailing) {
            if note.drawing != nil {
                Image(systemName: "hand.draw")
                    .font(.system(size: 12))
                    .foregroundStyle((onAccent ? Color.white : theme.accent).opacity(0.7))
                    .padding(14)
            }
        }
    }

    /// The prototype's `.ct-date`: an accent-colored date on top (+ a pin marker
    /// for pinned notes).
    private var dateLine: some View {
        HStack(spacing: 7) {
            if note.pinned { Image(systemName: "pin.fill").font(.system(size: 10)) }
            Text(note.createdAt.formatted(.relative(presentation: .named)))
                .font(theme.monoFont(11, relativeTo: .caption2).weight(.semibold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(onAccent ? .white : theme.accent)
        .padding(.bottom, 9)
    }

    /// The prototype's `.foot`: attendee avatars on the left, meta chips on the right.
    private var foot: some View {
        HStack(spacing: 8) {
            if !avatars.isEmpty {
                HStack(spacing: -6) {
                    ForEach(Array(avatars.enumerated()), id: \.offset) { index, initial in
                        Text(initial)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 21, height: 21)
                            .background(Color(hex: Tag.palette[index % Tag.palette.count]), in: Circle())
                            .overlay(Circle().strokeBorder(cardFill, lineWidth: 2))
                    }
                }
            }
            Spacer(minLength: 0)
            ForEach(Array(metaItems.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 5) {
                    Image(systemName: item.icon).font(.system(size: 11))
                    Text(item.text)
                }
                .font(theme.monoFont(11, relativeTo: .caption2).weight(.semibold))
                .foregroundStyle(onAccent ? .white.opacity(0.85) : (item.accent ? theme.accent : theme.inkFaint))
            }
        }
        .lineLimit(1)
    }

    /// The surface color behind the avatars (for their ring), matching the card.
    private var cardFill: Color {
        onAccent ? theme.accent : theme.paperRaised
    }

    private var avatars: [String] {
        note.attendees.prefix(3).map { name in
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? "?" : String(trimmed.first!).uppercased()
        }
    }

    /// Meta chips (right side of the foot): recording length, action items,
    /// attachments. `accent` flags the one that should pop in the accent color.
    private var metaItems: [(icon: String, text: String, accent: Bool)] {
        var items: [(String, String, Bool)] = []
        if let duration = recordingDuration {
            items.append(("waveform", duration, true))
        } else if !note.transcript.isEmpty {
            items.append(("waveform", "Rec", true))
        }
        let actions = actionItemCount
        if actions > 0 {
            items.append(("checklist", "\(actions)", false))
        } else if note.summaryData != nil {
            items.append(("sparkles", "Summary", false))
        }
        if let attachments = note.attachments, !attachments.isEmpty {
            items.append(("paperclip", "\(attachments.count)", false))
        }
        return items
    }

    /// Recording length from the first/last finalized segment timestamps.
    private var recordingDuration: String? {
        let times = note.transcriptSegments.compactMap(\.at)
        guard let first = times.min(), let last = times.max(), last > first else { return nil }
        let seconds = Int(last.timeIntervalSince(first))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var actionItemCount: Int {
        guard let data = note.summaryData,
              let summary = try? JSONDecoder().decode(MeetingSummary.self, from: data) else { return 0 }
        return summary.actionItems.count
    }
}

/// The prototype's `.pk-card` surface, per mood — this is the piece that was wrong
/// before. Faithful to `parley-screens.css` / `parley-moods.css`:
///   • Paper / Terminal — a boxed card (paper-rec fill, edge hairline, the mood's
///     radius + shadow). Feature adds a faint accent diagonal wash + accent-line border.
///   • Swiss — **no box**: transparent with a 2px ink top rule; feature → 5px accent rule.
///   • Neubrutalist — white block, 2px ink border, hard 4px offset shadow; feature →
///     filled with the accent (blue), white text.
private struct CardSurface: ViewModifier {
    let theme: Theme
    let mood: Mood
    let feature: Bool

    func body(content: Content) -> some View {
        switch mood {
        case .swiss:
            content.overlay(alignment: .top) {
                Rectangle()
                    .fill(feature ? theme.accent : theme.ink)
                    .frame(height: feature ? 5 : 2)
            }
        default:
            let shape = RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
            let fill: Color = (mood == .neubrutalist && feature) ? theme.accent : theme.paperRaised
            let border: Color = feature
                ? (mood == .neubrutalist ? theme.edge : theme.accentLine)
                : theme.edge
            content
                .background {
                    shape.fill(fill)
                    if feature && mood != .neubrutalist {
                        // The design's 5% accent diagonal wash on a feature card.
                        shape.fill(LinearGradient(colors: [theme.accent.opacity(0.06), .clear],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
                .clipShape(shape)
                // Shadow cast by a shape behind the content (never the text).
                .background { shape.fill(fill).themeShadow(theme.shadow) }
                .overlay(shape.strokeBorder(border, lineWidth: theme.borderWidth))
        }
    }
}
