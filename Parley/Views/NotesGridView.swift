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
    /// Whether the freeform board is offered here (iPad/Mac only — not iPhone).
    var allowsBoard: Bool = false

    @Environment(ThemeManager.self) private var themeManager

    private var boardActive: Bool { allowsBoard && themeManager.freeformBoard }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: themeManager.cardSize.columnMin), spacing: 14)]
    }

    /// Notes shown in the flowing grid. When pinned cards are *not* a hero, they go
    /// in the grid too (at normal size, still styled as pinned).
    private var gridNotes: [Note] { themeManager.featurePinned ? otherNotes : notes }

    var body: some View {
        @Bindable var manager = themeManager
        return Group {
            if boardActive && !notes.isEmpty {
                // Freeform board: arrange/resize cards yourself (positions sync).
                VStack(alignment: .leading, spacing: 0) {
                    dashboardHeader(manager)
                        .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)
                    NotesBoardView(
                        notes: notes, theme: theme, mood: mood, size: manager.cardSize,
                        onOpen: onOpen, onDelete: onDelete, onTogglePin: onTogglePin)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        dashboardHeader(manager)

                        if notes.isEmpty {
                            emptyState
                        } else {
                            // Pinned notes become the wide "feature" hero only when
                            // enabled; its size follows the card-size setting.
                            if manager.featurePinned && !pinnedNotes.isEmpty {
                                VStack(spacing: 14) {
                                    ForEach(pinnedNotes) { note in
                                        cardButton(note, hero: true)
                                            .frame(maxWidth: manager.cardSize.columnMin * 2 + 14, alignment: .leading)
                                    }
                                }
                            }
                            if !gridNotes.isEmpty {
                                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                                    ForEach(gridNotes) { cardButton($0, hero: false) }
                                }
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .moodPaper(theme)
    }

    /// The "All Notes" title + count, with the config control on the right.
    private func dashboardHeader(_ manager: ThemeManager) -> some View {
        HStack(alignment: .firstTextBaseline) {
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
            Spacer()
            dashboardConfig(manager)
        }
    }

    /// Dashboard controls: card size + whether pinned shows as a big hero.
    private func dashboardConfig(_ manager: ThemeManager) -> some View {
        @Bindable var manager = manager
        let shape = RoundedRectangle(cornerRadius: theme.cornerRadius == 0 ? 0 : 9, style: .continuous)
        return Menu {
            Picker("Card size", selection: $manager.cardSize) {
                ForEach(CardSize.allCases) { Label($0.name, systemImage: $0.icon).tag($0) }
            }
            .disabled(boardActive)
            Toggle("Big pinned card", isOn: $manager.featurePinned)
                .disabled(boardActive)
            if allowsBoard {
                Divider()
                Toggle("Freeform board", isOn: $manager.freeformBoard)
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(9)
                .background(theme.accent, in: shape)
                .overlay(shape.strokeBorder(theme.accentLine, lineWidth: theme.borderWidth))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    private var pinnedNotes: [Note] { notes.filter(\.pinned) }
    private var otherNotes: [Note] { notes.filter { !$0.pinned } }

    /// A tappable card with the pin/delete context menu. `hero` = the big wide
    /// feature layout (only for pinned notes when "Big pinned card" is on).
    private func cardButton(_ note: Note, hero: Bool) -> some View {
        Button { onOpen(note) } label: {
            NoteCard(theme: theme, mood: mood, note: note, size: themeManager.cardSize, hero: hero)
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
    /// Drives the card's height (Small/Medium/Large).
    var size: CardSize = .regular
    /// The big wide "feature" layout (taller, bigger title, 3-line snippet).
    var hero: Bool = false
    /// Fill the parent's size instead of using a fixed height (freeform board).
    var fill: Bool = false

    /// Pinned notes get the feature *styling* (mood-specific fill/border).
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
                .font(theme.titleFont(hero ? 22 : 18, relativeTo: .headline))
                .tracking(theme.titleTracking)
                .textCase(theme.titleUppercase ? .uppercase : nil)
                .foregroundStyle(onAccent ? .white : theme.ink)
                .lineLimit(2)
                .padding(.bottom, 7)

            if !snippet.isEmpty {
                Text(snippet)
                    .font(theme.bodyFont(13))
                    .foregroundStyle(onAccent ? .white.opacity(0.9) : theme.inkSoft)
                    .lineLimit(hero ? 3 : 2)
            }

            Spacer(minLength: 10)
            foot
        }
        .padding(16)
        .modifier(CardFrame(fill: fill, height: hero ? size.featureHeight : size.cardHeight))
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
/// Card height: a fixed height in the grid, or fill-the-parent on the freeform board.
private struct CardFrame: ViewModifier {
    let fill: Bool
    let height: CGFloat
    func body(content: Content) -> some View {
        if fill {
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            content
                .frame(height: height, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

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

// MARK: - Freeform board

/// The dashboard as a freeform board: each note card sits at its own position and
/// size (drag to move, corner grip to resize), persisted on the note so the layout
/// **syncs** across devices. Notes without a saved position are auto-placed in a
/// grid until you move them.
private struct NotesBoardView: View {
    let notes: [Note]
    let theme: Theme
    let mood: Mood
    let size: CardSize
    let onOpen: (Note) -> Void
    let onDelete: (Note) -> Void
    let onTogglePin: (Note) -> Void

    @State private var dragID: UUID?
    @State private var dragOffset: CGSize = .zero
    @State private var resizeID: UUID?
    @State private var resizeOffset: CGSize = .zero

    private let columnsPerRow = 3
    private let gap: CGFloat = 16
    private let margin: CGFloat = 20
    private var cellW: CGFloat { size.columnMin }
    private var cellH: CGFloat { size.cardHeight }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                    boardCard(note, index: index)
                }
            }
            .frame(width: boardWidth, height: boardHeight, alignment: .topLeading)
        }
        // While moving/resizing a card, the board itself doesn't scroll — that's
        // what stops the drag-vs-scroll fight. Scrolling resumes on empty space.
        .scrollDisabled(dragID != nil || resizeID != nil)
    }

    // MARK: Layout math

    private func defaultPos(_ index: Int) -> CGPoint {
        let col = index % columnsPerRow
        let row = index / columnsPerRow
        return CGPoint(x: margin + CGFloat(col) * (cellW + gap),
                       y: margin + CGFloat(row) * (cellH + gap))
    }

    private func origin(_ note: Note, _ index: Int) -> CGPoint {
        var x = note.boardX.map { CGFloat($0) } ?? defaultPos(index).x
        var y = note.boardY.map { CGFloat($0) } ?? defaultPos(index).y
        if dragID == note.id { x += dragOffset.width; y += dragOffset.height }
        return CGPoint(x: max(0, x), y: max(0, y))
    }

    private func cardSize(_ note: Note) -> CGSize {
        var w = note.boardW.map { CGFloat($0) } ?? cellW
        var h = note.boardH.map { CGFloat($0) } ?? cellH
        if resizeID == note.id { w += resizeOffset.width; h += resizeOffset.height }
        return CGSize(width: max(160, w), height: max(120, h))
    }

    private var boardWidth: CGFloat {
        var maxX: CGFloat = 700
        for (i, n) in notes.enumerated() { maxX = max(maxX, origin(n, i).x + cardSize(n).width) }
        return maxX + margin
    }
    private var boardHeight: CGFloat {
        var maxY: CGFloat = 500
        for (i, n) in notes.enumerated() { maxY = max(maxY, origin(n, i).y + cardSize(n).height) }
        return maxY + margin + 80
    }

    // MARK: Card

    private func boardCard(_ note: Note, index: Int) -> some View {
        let p = origin(note, index)
        let s = cardSize(note)
        let dragging = dragID == note.id || resizeID == note.id
        return NoteCard(theme: theme, mood: mood, note: note, size: size, hero: false, fill: true)
            .frame(width: s.width, height: s.height)
            // A clearer, bigger corner grip with a generous hit area.
            .overlay(alignment: .bottomTrailing) { resizeGrip(note) }
            // Lift the card slightly while being manipulated (clear feedback).
            .shadow(color: .black.opacity(dragging ? 0.18 : 0), radius: dragging ? 10 : 0, y: dragging ? 5 : 0)
            .contentShape(Rectangle())
            .offset(x: p.x, y: p.y)
            // Tap opens; a drag (high-priority, so it beats the board scroll) moves.
            .onTapGesture { onOpen(note) }
            .highPriorityGesture(moveGesture(note, index))
            .contextMenu {
                Button { onTogglePin(note) } label: {
                    Label(note.pinned ? "Unpin" : "Pin", systemImage: note.pinned ? "pin.slash" : "pin")
                }
                Button(role: .destructive) { onDelete(note) } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    /// The corner resize grip — large, with a padded hit area and its own
    /// high-priority gesture so it wins over the move.
    private func resizeGrip(_ note: Note) -> some View {
        Circle()
            .fill(theme.accent)
            .frame(width: 30, height: 30)
            .overlay(Image(systemName: "arrow.down.right.and.arrow.up.left")
                .font(.system(size: 12, weight: .bold)).foregroundStyle(.white))
            .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1.5))
            .padding(10)                       // enlarges the touch target
            .contentShape(Rectangle())
            .highPriorityGesture(resizeGesture(note))
    }

    private func moveGesture(_ note: Note, _ index: Int) -> some Gesture {
        DragGesture()
            .onChanged { v in dragID = note.id; dragOffset = v.translation }
            .onEnded { v in
                let baseX = note.boardX.map { CGFloat($0) } ?? defaultPos(index).x
                let baseY = note.boardY.map { CGFloat($0) } ?? defaultPos(index).y
                // Fine snapping only — freeform first, with a light tidy-up. Cards can
                // go all the way to the top (0), so there's no invisible ceiling.
                withAnimation(.snappy(duration: 0.12)) {
                    note.boardX = Double(snap(baseX + v.translation.width))
                    note.boardY = Double(snap(baseY + v.translation.height))
                }
                dragID = nil; dragOffset = .zero
            }
    }

    private func resizeGesture(_ note: Note) -> some Gesture {
        DragGesture()
            .onChanged { v in resizeID = note.id; resizeOffset = v.translation }
            .onEnded { v in
                let baseW = note.boardW.map { CGFloat($0) } ?? cellW
                let baseH = note.boardH.map { CGFloat($0) } ?? cellH
                withAnimation(.snappy(duration: 0.12)) {
                    note.boardW = Double(max(160, snap(baseW + v.translation.width)))
                    note.boardH = Double(max(120, snap(baseH + v.translation.height)))
                }
                resizeID = nil; resizeOffset = .zero
            }
    }

    /// Snap to a fine 20-pt grid (clamped ≥ 0) — light alignment, full freedom.
    private func snap(_ value: CGFloat) -> CGFloat {
        let grid: CGFloat = 20
        return max(0, (value / grid).rounded() * grid)
    }
}
