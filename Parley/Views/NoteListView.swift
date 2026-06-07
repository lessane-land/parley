import SwiftUI
import SwiftData

/// The home: a left **rail** (brand, search, nav, tags, Record CTA) beside a
/// **grid** of note cards. Tapping a card — or Record — pushes the editor.
struct NoteListView: View {
    @Environment(\.modelContext) private var context
    @Environment(ThemeManager.self) private var themeManager
    @Environment(EventKitService.self) private var eventKit
    @Environment(SyncMonitor.self) private var syncMonitor
    @Environment(RecordingCoordinator.self) private var recorder

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var hSize
    #endif

    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @Query(sort: \Tag.name) private var allTags: [Tag]

    /// The editor navigation stack (grid → note).
    @State private var path: [Note] = []

    @State private var searchText = ""
    @State private var scope: Scope = .all
    @State private var recordIntentID: PersistentIdentifier?

    @State private var showingSettings = false
    @State private var showingToday = false
    @State private var showingMonthCalendar = false
    @State private var showingAsk = false

    /// Tag rename: the tag being renamed + draft text.
    @State private var editingTag: Tag?
    @State private var tagDraft = ""
    /// The tag whose color is being picked (drives the swatch sheet).
    @State private var coloringTag: Tag?

    /// Width of the macOS "Ask Parley" side column (drag the divider to resize).
    @State private var askWidth: CGFloat = 380
    @State private var askDragBase: CGFloat?
    @State private var meetings: [Meeting] = []
    @State private var loadingMeetings = false

    @State private var showingReminders = false
    @State private var reminders: [ReminderItem] = []
    @State private var loadingReminders = false

    /// On-device meeting-prep generator (Foundation Models), used by the calendar.
    @State private var prepService = MeetingPrepService()

    private enum Scope: Hashable {
        case all, recent
        case tag(PersistentIdentifier)
    }

    private var theme: Theme { themeManager.theme }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if showingMonthCalendar {
                    monthCalendar   // full-window calendar (iPad/Mac)
                } else {
                    home
                }
            }
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                // iPad hides the bar on the dashboard (actions live in the rail), but
                // the calendar needs it back for its Done/＋. iPhone keeps its bar.
                .toolbar(barHidden ? .hidden : .visible, for: .navigationBar)
                .toolbarBackground(theme.paper, for: .navigationBar)
                .toolbarBackground(barHidden ? .hidden : .visible, for: .navigationBar)
                .toolbar { homeToolbar }
                #endif
                .navigationDestination(for: Note.self) { note in
                    NoteDetailView(
                        note: note,
                        autoRecord: note.persistentModelID == recordIntentID,
                        onAutoRecordConsumed: { recordIntentID = nil }
                    )
                }
                .sheet(isPresented: $showingToday) {
                    CalendarSheet(
                        theme: theme,
                        meetings: meetings,
                        access: eventKit.calendarAccess,
                        isLoading: loadingMeetings,
                        onPick: openMeeting,
                        onAddEvent: { draft in
                            _ = await eventKit.addEvent(draft)
                            meetings = await eventKit.upcomingMeetings()
                        }
                    )
                    .presentationDragIndicator(.visible)
                }
                .sheet(item: $coloringTag) { tag in
                    TagColorSheet(tag: tag, theme: theme)
                        .presentationDragIndicator(.visible)
                }
                .sheet(isPresented: $showingReminders) {
                    RemindersSheet(
                        theme: theme,
                        reminders: reminders,
                        access: eventKit.remindersAccess,
                        isLoading: loadingReminders,
                        onToggle: { id, done in
                            await eventKit.setReminderCompleted(id: id, completed: done)
                        }
                    )
                    .presentationDragIndicator(.visible)
                }
                // iOS (iPad + iPhone): Ask is a sheet. On macOS it's the inline
                // column in `home` instead (the binding suppresses the sheet there).
                .sheet(isPresented: sheetAsk) {
                    NavigationStack {
                        ChatView(theme: theme)
                            .navigationTitle("Ask Parley")
                            #if os(iOS)
                            .navigationBarTitleDisplayMode(.inline)
                            #endif
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") { showingAsk = false }
                                }
                            }
                    }
                    .presentationDragIndicator(.visible)
                }
        }
        .tint(theme.accent)
        // Menu bar "Open Parley" while recording → jump to that note.
        .onChange(of: recorder.openTick) { _, _ in
            guard let id = recorder.openNoteRequest,
                  let note = notes.first(where: { $0.persistentModelID == id }) else { return }
            if path.last?.persistentModelID != id { path.append(note) }
        }
        .alert("Rename Tag", isPresented: Binding(
            get: { editingTag != nil },
            set: { if !$0 { editingTag = nil } }
        )) {
            TextField("Name", text: $tagDraft)
            Button("Save") {
                let name = tagDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if let tag = editingTag, !name.isEmpty { tag.name = name }
                editingTag = nil
            }
            Button("Cancel", role: .cancel) { editingTag = nil }
        }
        #if !os(macOS)
        // iOS: Settings is a sheet (popup). On macOS it's the slide-over instead.
        .sheet(isPresented: sheetSettings) {
            NavigationStack {
                SettingsView()
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingSettings = false }
                        }
                    }
            }
            .presentationDragIndicator(.visible)
        }
        #endif
    }

    /// Hide the navigation bar on iPad/Mac: both the dashboard (actions live in the
    /// rail) and the calendar (it carries its own header) provide their own chrome,
    /// so the system bar would only add an empty gap at the top.
    private var barHidden: Bool { isRegular }

    /// Whether to show the side rail (iPad/Mac) or a compact grid (iPhone).
    private var isRegular: Bool {
        #if os(macOS)
        true
        #else
        hSize == .regular
        #endif
    }

    /// Settings and Ask appear *aside* (slide-over / column) on macOS, and as
    /// sheets on iOS (iPad + iPhone) — the placement the design calls for.
    private var usesSidePanels: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    // Sheets present only when we're NOT using side panels (i.e. on iOS).
    private var sheetAsk: Binding<Bool> {
        Binding(get: { showingAsk && !usesSidePanels }, set: { showingAsk = $0 })
    }
    private var sheetSettings: Binding<Bool> {
        Binding(get: { showingSettings && !usesSidePanels }, set: { showingSettings = $0 })
    }

    /// The dashboard: rail + grid side by side on iPad/Mac; just the grid on
    /// iPhone (filters move to the toolbar). Opening a note pushes it full-screen.
    @ViewBuilder
    private var home: some View {
        if isRegular {
            // iPad/Mac: rail + grid, with Ask as an inline right column and Settings
            // as a right slide-over — both "aside", not modal sheets.
            HStack(spacing: 0) {
                if railFloats {
                    floatingRail
                } else {
                    rail.frame(width: 268)
                    verticalDivider
                }
                grid
                if usesSidePanels && showingAsk {
                    askResizeHandle
                    chatColumn.transition(.move(edge: .trailing))
                }
            }
            // When the rail floats (iPad), the margins around it show the mood's
            // paper + grain, so the panel reads as a card on the same canvas.
            .background { if railFloats { Color.clear.moodPaper(theme) } }
            .overlay { if usesSidePanels { settingsSlideOver } }
        } else {
            grid
                .searchable(text: $searchText)
        }
    }

    /// On iPad the rail floats as a card (cleaner top, design-accurate); on Mac it
    /// stays flush against the window edge (the look you already liked).
    private var railFloats: Bool {
        #if os(macOS)
        false
        #else
        true
        #endif
    }

    /// The rail as a floating panel: inset from the edges with the mood's card
    /// shape (border + shadow), so it sits *on* the paper rather than butting the
    /// nav bar. Each mood styles the card differently via its tokens.
    private var floatingRail: some View {
        let shape = RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
        return rail
            .frame(width: 256)
            .clipShape(shape)
            .overlay(shape.strokeBorder(theme.edge, lineWidth: theme.borderWidth))
            .themeShadow(theme.shadow)
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .padding(.vertical, 14)
    }

    private var verticalDivider: some View {
        Rectangle().fill(theme.line).frame(width: theme.borderWidth)
    }

    /// Ask Parley as an inline right column (iPad/Mac), resizable on Mac.
    private var chatColumn: some View {
        VStack(spacing: 0) {
            panelHeader("Ask Parley") { withAnimation(.snappy) { showingAsk = false } }
            ChatView(theme: theme)
        }
        .frame(width: askWidth)
        .background(theme.paperSunk)
    }

    /// Draggable divider to set the Ask column's width (drag left = wider).
    private var askResizeHandle: some View {
        ZStack {
            Rectangle().fill(theme.line).frame(width: theme.borderWidth)
            Rectangle().fill(Color.clear).frame(width: 12).contentShape(Rectangle())
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let base = askDragBase ?? askWidth
                    askDragBase = base
                    askWidth = min(max(base - value.translation.width, 320), 760)
                }
                .onEnded { _ in askDragBase = nil }
        )
        #if os(macOS)
        .onHover { inside in
            if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
        }
        #endif
        .accessibilityLabel("Resize Ask Parley")
    }

    /// Settings as a right slide-over with a dimming scrim (iPad/Mac).
    @ViewBuilder
    private var settingsSlideOver: some View {
        if showingSettings {
            ZStack(alignment: .trailing) {
                Color.black.opacity(0.34)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.snappy) { showingSettings = false } }
                    .transition(.opacity)

                VStack(spacing: 0) {
                    panelHeader("Settings") { withAnimation(.snappy) { showingSettings = false } }
                    SettingsView()
                }
                .frame(width: 392)
                .background(theme.paperRaised)
                .overlay(alignment: .leading) { verticalDivider }
                .transition(.move(edge: .trailing))
            }
        }
    }

    /// A panel header (title + close) for the side panels.
    private func panelHeader(_ title: String, close: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(theme.titleFont(20, relativeTo: .title3))
                .tracking(theme.titleTracking)
                .textCase(theme.titleUppercase ? .uppercase : nil)
                .foregroundStyle(theme.ink)
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.inkSoft)
                    .frame(width: 30, height: 30)
                    .background(theme.paperSunk, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(theme.paperRaised)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: theme.borderWidth) }
    }

    private var grid: some View {
        NotesGridView(
            theme: theme,
            mood: themeManager.mood,
            title: scopeTitle,
            notes: filteredNotes,
            onOpen: { path.append($0) },
            onDelete: deleteNote,
            onTogglePin: { note in withAnimation(.snappy) { note.pinned.toggle() } }
        )
    }

    #if os(iOS)
    // iPad/Mac: every option lives in the rail (Settings + Record at the bottom),
    // so the top bar stays empty — no top-right menu. Only iPhone, which has no
    // rail, surfaces actions in the bar (plus an overflow for the rest). On macOS
    // there's no `.toolbar` at all (this isn't compiled).
    @ToolbarContentBuilder
    private var homeToolbar: some ToolbarContent {
        if !isRegular {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button { showingSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                    Button { showingAsk = true } label: { Label("Ask Parley", systemImage: "sparkles") }
                    Button { openCalendar() } label: { Label("Calendar", systemImage: "calendar") }
                    Button { openReminders() } label: { Label("Reminders", systemImage: "checklist") }
                    Divider()
                    Picker("Filter", selection: $scope) {
                        Label("All Notes", systemImage: "tray.full").tag(Scope.all)
                        Label("Recent", systemImage: "clock").tag(Scope.recent)
                        ForEach(allTags) { tag in Text(tag.name).tag(Scope.tag(tag.persistentModelID)) }
                    }
                } label: {
                    Label("Menu", systemImage: "line.3.horizontal")
                }
            }
            ToolbarItem { Button(action: addNote) { Label("New Note", systemImage: "square.and.pencil") } }
            ToolbarItem { Button(action: createAndRecord) { Label("Record", systemImage: "mic.fill") } }
        }
    }
    #endif

    // MARK: Rail

    private var rail: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack(spacing: 9) {
                    brandMark
                    Text("Parley")
                        .font(theme.titleFont(20, relativeTo: .title3))
                        .tracking(theme.titleTracking)
                        .foregroundStyle(theme.ink)
                    Spacer()
                    // Compose a new note (sits with the brand, like Apple Notes).
                    Button { addNote() } label: {
                        Image(systemName: "square.and.pencil").font(.system(size: 17))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.accent)
                    .focusEffectDisabled()   // no stray macOS focus-ring "selected" box
                    .accessibilityLabel("New Note")
                }
                searchField
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    navRow("All Notes", "tray.full", count: notes.count, target: .all)
                    navRow("Recent", "clock", count: recentCount, target: .recent)
                    actionRow("Ask Parley", "sparkles") { withAnimation(.snappy) { showingAsk = true } }
                    actionRow("Calendar", "calendar") { openCalendar() }
                    actionRow("Reminders", "checklist") { openReminders() }

                    if !allTags.isEmpty {
                        Text("SPACES")
                            .font(theme.monoFont(10))
                            .tracking(1.4)
                            .foregroundStyle(theme.inkFaint)
                            .padding(.horizontal, 11)
                            .padding(.top, 16)
                            .padding(.bottom, 4)
                        ForEach(allTags) { tag in tagRow(tag) }
                    }
                }
                .padding(.horizontal, 8)
            }

            // Side foot (pinned to the bottom, like the design): Settings, then the
            // Record CTA. All app options live in the rail — nothing in a top menu.
            VStack(spacing: 6) {
                settingsLink
                recordCTA
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            SyncStatusChip(theme: theme, status: syncMonitor.status)
        }
        .background(theme.paperSunk)
    }

    /// A non-selectable sidebar action (Ask Parley, Calendar, …) styled like a nav
    /// row but triggering a one-off action instead of switching the filter scope.
    private func actionRow(_ label: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.cornerRadius == 0 ? 0 : 9)
        return Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon).foregroundStyle(theme.inkFaint).frame(width: 18)
                Text(label).font(theme.bodyFont(14)).foregroundStyle(theme.ink)
                Spacer()
            }
            .padding(.horizontal, 11).padding(.vertical, 9)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
    }

    /// Settings lives at the bottom of the rail (slide-over on Mac, sheet on iPad).
    private var settingsLink: some View {
        Button {
            #if os(macOS)
            withAnimation(.snappy) { showingSettings.toggle() }
            #else
            showingSettings = true
            #endif
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "gearshape").foregroundStyle(theme.inkFaint).frame(width: 18)
                Text("Settings").font(theme.bodyFont(13.5)).foregroundStyle(theme.inkSoft)
                Spacer()
            }
            .padding(.horizontal, 11).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var brandMark: some View {
        RoundedRectangle(cornerRadius: theme.cornerRadius == 0 ? 0 : 8)
            .fill(theme.accent)
            .frame(width: 30, height: 30)
            .overlay(Text("P").font(theme.titleFont(17, relativeTo: .headline)).foregroundStyle(.white))
    }

    private var searchField: some View {
        let shape = RoundedRectangle(cornerRadius: theme.cornerRadius == 0 ? 0 : 10)
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(theme.inkFaint)
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .foregroundStyle(theme.ink)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(theme.inkFaint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .font(theme.bodyFont(14))
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(theme.paperRaised, in: shape)
        .overlay(shape.strokeBorder(theme.edge, lineWidth: theme.borderWidth))
    }

    private var recordCTA: some View {
        Button { createAndRecord() } label: {
            HStack(spacing: 9) {
                Image(systemName: "mic.fill")
                Text("Record meeting").font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(theme.accent, in: RoundedRectangle(cornerRadius: theme.cornerRadius == 0 ? 0 : 12))
        }
        .buttonStyle(.plain)
    }

    private func navRow(_ label: String, _ icon: String, count: Int, target: Scope) -> some View {
        let on = scope == target
        let shape = RoundedRectangle(cornerRadius: theme.cornerRadius == 0 ? 0 : 9)
        return Button { scope = target } label: {
            HStack(spacing: 11) {
                Image(systemName: icon).foregroundStyle(on ? theme.accent : theme.inkFaint).frame(width: 18)
                Text(label).font(theme.bodyFont(14)).foregroundStyle(on ? theme.accentInk : theme.ink)
                Spacer()
                Text("\(count)").font(theme.monoFont(11)).foregroundStyle(theme.inkFaint)
            }
            .padding(.horizontal, 11).padding(.vertical, 9)
            .background(on ? theme.accentTint : Color.clear, in: shape)
        }
        .buttonStyle(.plain)
    }

    private func tagRow(_ tag: Tag) -> some View {
        let on = scope == .tag(tag.persistentModelID)
        let shape = RoundedRectangle(cornerRadius: theme.cornerRadius == 0 ? 0 : 9)
        return Button { scope = .tag(tag.persistentModelID) } label: {
            HStack(spacing: 11) {
                Circle().fill(tag.color).frame(width: 9, height: 9).frame(width: 18)
                Text(tag.name).font(theme.bodyFont(14)).foregroundStyle(on ? theme.accentInk : theme.ink).lineLimit(1)
                Spacer()
                Text("\(tag.notes?.count ?? 0)").font(theme.monoFont(11)).foregroundStyle(theme.inkFaint)
            }
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(on ? theme.accentTint : Color.clear, in: shape)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { startRenameTag(tag) } label: { Label("Rename", systemImage: "pencil") }
            // A swatch picker (sheet) instead of a text submenu — macOS menus render
            // SF Symbols monochrome, so "Color 1…8" showed no actual colors.
            Button { coloringTag = tag } label: { Label("Color…", systemImage: "paintpalette") }
            Divider()
            Button(role: .destructive) { deleteTag(tag) } label: { Label("Delete Tag", systemImage: "trash") }
        }
    }

    // MARK: Filtering

    private var scopeTitle: String {
        switch scope {
        case .all: "All Notes"
        case .recent: "Recent"
        case .tag(let id): allTags.first { $0.persistentModelID == id }?.name ?? "Tag"
        }
    }

    private var recentCutoff: Date {
        Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .distantPast
    }

    private var recentCount: Int {
        notes.filter { $0.createdAt >= recentCutoff }.count
    }

    private var filteredNotes: [Note] {
        // Pinned first, then the rest — each keeping the @Query order (newest first).
        let matched = notes.filter { matchesSearch($0) && matchesScope($0) }
        return matched.filter(\.pinned) + matched.filter { !$0.pinned }
    }

    private func matchesSearch(_ note: Note) -> Bool {
        guard !searchText.isEmpty else { return true }
        return note.title.localizedCaseInsensitiveContains(searchText)
            || note.body.localizedCaseInsensitiveContains(searchText)
            || note.transcript.localizedCaseInsensitiveContains(searchText)
    }

    private func matchesScope(_ note: Note) -> Bool {
        switch scope {
        case .all: return true
        case .recent: return note.createdAt >= recentCutoff
        case .tag(let id): return (note.tags ?? []).contains { $0.persistentModelID == id }
        }
    }

    // MARK: Actions

    private func addNote() {
        let note = Note()
        context.insert(note)
        path.append(note)
    }

    /// Compact, on-device digest of related past notes, fed to the prep model so it
    /// can ground "what to do beforehand" in real history (prior summaries lead with
    /// their overview, open questions, and any still-unfinished action items).
    static func historyText(from notes: [Note]) -> String {
        guard !notes.isEmpty else { return "" }
        return notes.map { n in
            let when = (n.startDate ?? n.createdAt).formatted(.dateTime.month().day().year())
            var detail = ""
            if let data = n.summaryData,
               let s = try? JSONDecoder().decode(MeetingSummary.self, from: data), !s.overview.isEmpty {
                detail = s.overview
                if !s.openQuestions.isEmpty {
                    detail += " Open questions: " + s.openQuestions.joined(separator: "; ") + "."
                }
                let pending = s.actionItems.filter { !$0.done }.map(\.title)
                if !pending.isEmpty {
                    detail += " Unfinished actions: " + pending.joined(separator: "; ") + "."
                }
            } else if !n.body.isEmpty {
                detail = String(n.body.prefix(300))
            } else if !n.transcript.isEmpty {
                detail = String(n.transcript.prefix(300))
            }
            let title = n.title.isEmpty ? "Untitled" : n.title
            return "• \(title) (\(when)): \(detail)"
        }
        .joined(separator: "\n")
    }

    /// Create a note dated to a given day (from the calendar's day panel) and open
    /// it. Leaving the calendar so the new note is what the user sees.
    private func createNote(on day: Date) {
        let note = Note(title: "", startDate: day)
        context.insert(note)
        showingMonthCalendar = false
        path.append(note)
    }

    private func createAndRecord() {
        let note = Note(title: "New recording")
        context.insert(note)
        recordIntentID = note.persistentModelID
        path.append(note)
    }

    private func openCalendar() {
        // iPad/Mac get the big month grid; iPhone gets the agenda sheet.
        if isRegular {
            showingMonthCalendar = true
            return
        }
        showingToday = true
        loadingMeetings = true
        Task {
            meetings = await eventKit.upcomingMeetings()
            loadingMeetings = false
        }
    }

    /// The full-window month-grid calendar (iPad/Mac). Tapping a meeting/note pushes
    /// it on top (back returns to the calendar); Done returns to the dashboard.
    private var monthCalendar: some View {
        MonthCalendarView(
            theme: theme,
            notes: notes,
            access: eventKit.calendarAccess,
            remindersAccess: eventKit.remindersAccess,
            onOpenMeeting: { meeting in openMeeting(meeting) },
            onOpenNote: { note in path.append(note) },
            loadMeetings: { start, end in await eventKit.meetings(from: start, to: end) },
            onAddEvent: { draft in _ = await eventKit.addEvent(draft) },
            onCreateNote: { day in createNote(on: day) },
            loadReminders: { start, end in await eventKit.reminders(from: start, to: end) },
            onToggleReminder: { id, done in await eventKit.setReminderCompleted(id: id, completed: done) },
            onAddReminder: { draft in _ = await eventKit.addReminders([draft]) },
            generatePrep: { meeting, related, reminderTitles in
                await prepService.generate(
                    title: meeting.title, when: meeting.start, attendees: meeting.attendees,
                    historyText: Self.historyText(from: related), reminders: reminderTitles)
            },
            prepUnavailableMessage: prepService.availabilityMessage(),
            onClose: { showingMonthCalendar = false }
        )
    }

    private func openReminders() {
        showingReminders = true
        loadingReminders = true
        Task {
            reminders = await eventKit.fetchReminders()
            loadingReminders = false
        }
    }

    private func openMeeting(_ meeting: Meeting) {
        if let existing = notes.first(where: { $0.calendarEventID == meeting.id }) {
            path.append(existing)
            return
        }
        // Meeting metadata lives in real fields now (E4), not prefilled body text,
        // so the note opens with a clean, empty notes area.
        let note = Note(
            title: meeting.title,
            calendarEventID: meeting.id,
            startDate: meeting.start,
            endDate: meeting.end,
            attendees: meeting.attendees
        )
        context.insert(note)
        path.append(note)
    }

    private func deleteNote(_ note: Note) {
        if path.last == note { path.removeLast() }
        context.delete(note)
    }

    // MARK: Tags

    private func startRenameTag(_ tag: Tag) {
        tagDraft = tag.name
        editingTag = tag
    }

    private func deleteTag(_ tag: Tag) {
        // If we're currently filtered by this tag, fall back to All Notes.
        if scope == .tag(tag.persistentModelID) { scope = .all }
        context.delete(tag)
    }
}

/// A small footer chip showing CloudKit sync status, styled to the mood.
private struct SyncStatusChip: View {
    let theme: Theme
    let status: SyncMonitor.Status

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .symbolEffect(.rotate, options: .repeating, isActive: isSyncing)
            Text(label)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(theme.monoFont(10.5, relativeTo: .caption2))
        .foregroundStyle(isError ? theme.rec : theme.inkFaint)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 8)
        .background(theme.paperSunk)
        .overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: theme.borderWidth) }
    }

    private var isSyncing: Bool { status == .syncing }
    private var isError: Bool { if case .error = status { return true }; return false }

    private var icon: String {
        switch status {
        case .localOnly: "internaldrive"
        case .idle:      "icloud"
        case .syncing:   "arrow.triangle.2.circlepath"
        case .synced:    "checkmark.icloud"
        case .error:     "exclamationmark.icloud"
        }
    }

    private var label: String {
        switch status {
        case .localOnly: "On this device"
        case .idle:      "iCloud"
        case .syncing:   "Syncing…"
        case .synced:    "Synced"
        case .error(let message): message
        }
    }
}

/// A color picker for a tag: the **current mood's** palette first (so tags match
/// the look you're in), a curated extra row, and a full custom `ColorPicker`.
/// Visible, tappable swatches that work on both iOS and macOS.
private struct TagColorSheet: View {
    let tag: Tag
    let theme: Theme
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 54), spacing: 14)]

    /// The active mood's accent options (+ highlight, if it has one).
    private var moodColors: [String] {
        let cfg = themeManager.mood.config
        return cfg.accents + (cfg.highlights ?? [])
    }

    /// A broader curated set drawn from *every* mood's accents, minus the mood
    /// ones already shown, so there's variety without clashing.
    private var moreColors: [String] {
        let moodSet = Set(moodColors.map { $0.uppercased() })
        var seen = moodSet
        var result: [String] = []
        for mood in Mood.allCases {
            for hex in mood.config.accents {
                let key = hex.uppercased()
                if seen.insert(key).inserted { result.append(hex) }
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    swatchSection("\(themeManager.mood.name) colors", moodColors)
                    swatchSection("More", moreColors)

                    Divider().overlay(theme.edge)

                    ColorPicker(selection: customBinding, supportsOpacity: false) {
                        Text("Custom color")
                            .font(theme.bodyFont(13).weight(.semibold))
                            .foregroundStyle(theme.ink)
                    }
                    .padding(.horizontal, 2)
                }
                .padding(20)
            }
            .background(theme.paperSunk)
            .navigationTitle("Tag Color")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 340, minHeight: 320)
        #endif
    }

    /// Two-way bridge between the stored hex and SwiftUI's `Color` for the picker.
    private var customBinding: Binding<Color> {
        Binding(
            get: { Color(hex: tag.colorHex) },
            set: { if let hex = $0.toHex() { tag.colorHex = hex } }
        )
    }

    private func swatchSection(_ title: String, _ colors: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(theme.monoFont(10))
                .tracking(1.4)
                .foregroundStyle(theme.inkFaint)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, hex in
                    swatch(hex)
                }
            }
        }
    }

    private func swatch(_ hex: String) -> some View {
        let selected = hex.uppercased() == tag.colorHex.uppercased()
        // Contrast the checkmark against the swatch so it reads on light colors too.
        let mark: Color = PK.isLight(hex) ? .black : .white
        return Button {
            tag.colorHex = hex
        } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 48, height: 48)
                .overlay(Circle().strokeBorder(selected ? theme.ink : theme.edge,
                                               lineWidth: selected ? 3 : 1))
                .overlay {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(mark)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selected ? "Selected color" : "Color")
    }
}

#Preview {
    NoteListView()
        .modelContainer(for: Note.self, inMemory: true)
        .environment(ThemeManager())
        .environment(EventKitService())
        .environment(SyncMonitor(cloudEnabled: false))
        .environment(RecordingCoordinator())
}
