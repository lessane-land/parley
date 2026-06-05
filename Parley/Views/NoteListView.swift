import SwiftUI
import SwiftData

/// The home screen: a sidebar (brand, search, Record CTA, All/Recent/tag filters)
/// listing note cards, with the editor in the detail pane.
struct NoteListView: View {
    @Environment(\.modelContext) private var context
    @Environment(ThemeManager.self) private var themeManager
    @Environment(EventKitService.self) private var eventKit
    @Environment(SyncMonitor.self) private var syncMonitor

    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @Query(sort: \Tag.name) private var allTags: [Tag]

    @State private var selection: Note?
    @State private var showingSettings = false

    // Today's-meetings sheet
    @State private var showingToday = false
    @State private var meetings: [Meeting] = []
    @State private var loadingMeetings = false

    // Sidebar filtering
    @State private var searchText = ""
    @State private var scope: Scope = .all

    /// Set when the Record CTA makes a note, so the detail auto-starts recording.
    @State private var recordIntentID: PersistentIdentifier?

    private enum Scope: Equatable {
        case all, recent
        case tag(PersistentIdentifier)
    }

    private var theme: Theme { themeManager.theme }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(filteredNotes) { note in
                    NoteRow(note: note, theme: theme, selected: note == selection)
                        .tag(note)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
                }
                .onDelete(perform: deleteNotes)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(theme.paperSunk)
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem {
                    Button(action: addNote) {
                        Label("New Note", systemImage: "square.and.pencil")
                    }
                }
                ToolbarItem {
                    Button { openToday() } label: {
                        Label("Today's Meetings", systemImage: "calendar")
                    }
                }
                #if !os(macOS)
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: {
                        Label("Settings", systemImage: "slider.horizontal.3")
                    }
                }
                #endif
            }
            .safeAreaInset(edge: .top) { sidebarHeader }
            .overlay { emptyOverlay }
            .sheet(isPresented: $showingToday) {
                TodayMeetingsSheet(
                    theme: theme,
                    meetings: meetings,
                    access: eventKit.calendarAccess,
                    isLoading: loadingMeetings,
                    onPick: createNote(from:)
                )
            }
            .safeAreaInset(edge: .bottom) {
                SyncStatusChip(theme: theme, status: syncMonitor.status)
            }
        } detail: {
            if let selection {
                NoteDetailView(
                    note: selection,
                    autoRecord: selection.persistentModelID == recordIntentID,
                    onAutoRecordConsumed: { recordIntentID = nil }
                )
                .id(selection.id)
            } else {
                ThemedEmptyState(
                    theme: theme,
                    icon: "sidebar.left",
                    title: "No Note Selected",
                    message: "Select a note from the list, or create a new one."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.paper)
            }
        }
        .tint(theme.accent)
        #if !os(macOS)
        .sheet(isPresented: $showingSettings) {
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
        }
        #endif
    }

    // MARK: Sidebar header

    private var sidebarHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 9) {
                brandMark
                Text("Parley")
                    .font(theme.titleFont(20, relativeTo: .title3))
                    .tracking(theme.titleTracking)
                    .foregroundStyle(theme.ink)
                Spacer()
            }
            searchField
            recordCTA
            filterChips
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(theme.paperSunk)
    }

    private var brandMark: some View {
        RoundedRectangle(cornerRadius: theme.cornerRadius == 0 ? 0 : 8)
            .fill(theme.accent)
            .frame(width: 30, height: 30)
            .overlay(
                Text("P")
                    .font(theme.titleFont(17, relativeTo: .headline))
                    .foregroundStyle(.white)
            )
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

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(theme: theme, label: "All", count: notes.count, isOn: scope == .all) { scope = .all }
                FilterChip(theme: theme, label: "Recent", count: recentCount, isOn: scope == .recent) { scope = .recent }
                ForEach(allTags) { tag in
                    FilterChip(theme: theme, label: tag.name, count: tag.notes?.count ?? 0, color: tag.color,
                               isOn: scope == .tag(tag.persistentModelID)) {
                        scope = .tag(tag.persistentModelID)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    private var emptyOverlay: some View {
        if notes.isEmpty {
            ThemedEmptyState(theme: theme, icon: "note.text", title: "No Notes",
                             message: "Tap Record, or the compose button, to start your first note.")
        } else if filteredNotes.isEmpty {
            ThemedEmptyState(theme: theme, icon: "magnifyingglass", title: "No matches",
                             message: "Nothing matches your search or filter.")
        }
    }

    // MARK: Filtering

    private var recentCutoff: Date {
        Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .distantPast
    }

    private var recentCount: Int {
        notes.filter { $0.createdAt >= recentCutoff }.count
    }

    private var filteredNotes: [Note] {
        notes.filter { matchesSearch($0) && matchesScope($0) }
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
        selection = note
    }

    private func createAndRecord() {
        let note = Note(title: "New recording")
        context.insert(note)
        selection = note
        recordIntentID = note.persistentModelID
    }

    private func openToday() {
        showingToday = true
        loadingMeetings = true
        Task {
            meetings = await eventKit.todaysMeetings()
            loadingMeetings = false
        }
    }

    private func createNote(from meeting: Meeting) {
        if let existing = notes.first(where: { $0.calendarEventID == meeting.id }) {
            selection = existing
            return
        }
        let note = Note(
            title: meeting.title,
            body: meetingHeader(meeting),
            createdAt: meeting.start,
            calendarEventID: meeting.id
        )
        context.insert(note)
        selection = note
    }

    private func meetingHeader(_ meeting: Meeting) -> String {
        let time = meeting.start.formatted(date: .omitted, time: .shortened)
            + "–" + meeting.end.formatted(date: .omitted, time: .shortened)
        var lines = [time]
        if !meeting.attendees.isEmpty {
            lines.append("With: " + meeting.attendees.joined(separator: ", "))
        }
        return lines.joined(separator: "\n") + "\n\n"
    }

    private func deleteNotes(at offsets: IndexSet) {
        let shown = filteredNotes
        for index in offsets {
            let note = shown[index]
            if note == selection { selection = nil }
            context.delete(note)
        }
    }
}

/// A pill filter for the sidebar (All / Recent / a tag).
private struct FilterChip: View {
    let theme: Theme
    let label: String
    var count: Int? = nil
    var color: Color? = nil
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.cornerRadius == 0 ? 0 : 99)
        Button(action: action) {
            HStack(spacing: 6) {
                if let color { Circle().fill(color).frame(width: 7, height: 7) }
                Text(label).font(theme.bodyFont(12.5))
                if let count {
                    Text("\(count)")
                        .font(theme.monoFont(10.5, relativeTo: .caption2))
                        .foregroundStyle(theme.inkFaint)
                }
            }
            .foregroundStyle(isOn ? theme.accentInk : theme.inkSoft)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(isOn ? theme.accentTint : theme.paperRaised, in: shape)
            .overlay(shape.strokeBorder(theme.edge, lineWidth: theme.borderWidth))
        }
        .buttonStyle(.plain)
        .lineLimit(1)
    }
}

/// A single note card in the sidebar — title, snippet, tags, and a date.
private struct NoteRow: View {
    let note: Note
    let theme: Theme
    let selected: Bool

    private var snippet: String {
        note.body
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(note.title.isEmpty ? "New Note" : note.title)
                .font(theme.titleFont(16, relativeTo: .headline))
                .tracking(theme.titleTracking)
                .textCase(theme.titleUppercase ? .uppercase : nil)
                .foregroundStyle(theme.ink)
                .lineLimit(1)

            if !snippet.isEmpty {
                Text(snippet)
                    .font(theme.bodyFont(12.5))
                    .foregroundStyle(theme.inkSoft)
                    .lineLimit(2)
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
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moodCard(theme, fill: selected ? theme.accentTint : theme.paperRaised, selected: selected)
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
        case .error:     "Sync issue"
        }
    }
}

/// A mood-styled empty state, shown when there are no notes / no matches.
private struct ThemedEmptyState: View {
    let theme: Theme
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 42))
                .foregroundStyle(theme.accent)
            Text(title)
                .font(theme.titleFont(22, relativeTo: .title2))
                .tracking(theme.titleTracking)
                .textCase(theme.titleUppercase ? .uppercase : nil)
                .foregroundStyle(theme.ink)
            Text(message)
                .font(theme.bodyFont(14))
                .foregroundStyle(theme.inkSoft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .padding(24)
    }
}

#Preview {
    NoteListView()
        .modelContainer(for: Note.self, inMemory: true)
        .environment(ThemeManager())
        .environment(EventKitService())
        .environment(SyncMonitor(cloudEnabled: false))
}
