import SwiftUI
import SwiftData

/// The home: a left **rail** (brand, search, nav, tags, Record CTA) beside a
/// **grid** of note cards. Tapping a card — or Record — pushes the editor.
struct NoteListView: View {
    @Environment(\.modelContext) private var context
    @Environment(ThemeManager.self) private var themeManager
    @Environment(EventKitService.self) private var eventKit
    @Environment(SyncMonitor.self) private var syncMonitor

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
    @State private var showingAsk = false
    @State private var meetings: [Meeting] = []
    @State private var loadingMeetings = false

    private enum Scope: Hashable {
        case all, recent
        case tag(PersistentIdentifier)
    }

    private var theme: Theme { themeManager.theme }

    var body: some View {
        NavigationStack(path: $path) {
            home
                .navigationTitle("")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { homeToolbar }
                .navigationDestination(for: Note.self) { note in
                    NoteDetailView(
                        note: note,
                        autoRecord: note.persistentModelID == recordIntentID,
                        onAutoRecordConsumed: { recordIntentID = nil }
                    )
                }
                .sheet(isPresented: $showingToday) {
                    TodayMeetingsSheet(
                        theme: theme,
                        meetings: meetings,
                        access: eventKit.calendarAccess,
                        isLoading: loadingMeetings,
                        onPick: openMeeting
                    )
                }
                .sheet(isPresented: $showingAsk) {
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

    /// Whether to show the side rail (iPad/Mac) or a compact grid (iPhone).
    private var isRegular: Bool {
        #if os(macOS)
        true
        #else
        hSize == .regular
        #endif
    }

    /// The dashboard: rail + grid side by side on iPad/Mac; just the grid on
    /// iPhone (filters move to the toolbar). Opening a note pushes it full-screen.
    @ViewBuilder
    private var home: some View {
        if isRegular {
            HStack(spacing: 0) {
                rail.frame(width: 268)
                Rectangle().fill(theme.line).frame(width: theme.borderWidth)
                grid
            }
        } else {
            grid
                .searchable(text: $searchText)
        }
    }

    private var grid: some View {
        NotesGridView(
            theme: theme,
            title: scopeTitle,
            notes: filteredNotes,
            onOpen: { path.append($0) },
            onDelete: deleteNote
        )
    }

    @ToolbarContentBuilder
    private var homeToolbar: some ToolbarContent {
        ToolbarItem { Button(action: addNote) { Label("New Note", systemImage: "square.and.pencil") } }
        ToolbarItem { Button { showingAsk = true } label: { Label("Ask Parley", systemImage: "sparkles") } }
        ToolbarItem { Button { openToday() } label: { Label("Today's Meetings", systemImage: "calendar") } }
        #if !os(macOS)
        ToolbarItem(placement: .topBarLeading) {
            Button { showingSettings = true } label: { Label("Settings", systemImage: "slider.horizontal.3") }
        }
        if !isRegular {
            // On iPhone the rail is hidden, so Record + filters live in the bar.
            ToolbarItem { Button(action: createAndRecord) { Label("Record", systemImage: "mic.fill") } }
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("Filter", selection: $scope) {
                        Label("All Notes", systemImage: "tray.full").tag(Scope.all)
                        Label("Recent", systemImage: "clock").tag(Scope.recent)
                        ForEach(allTags) { tag in Text(tag.name).tag(Scope.tag(tag.persistentModelID)) }
                    }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
        #endif
    }

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

                    if !allTags.isEmpty {
                        Text("TAGS")
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

            recordCTA
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

            SyncStatusChip(theme: theme, status: syncMonitor.status)
        }
        .background(theme.paperSunk)
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
        path.append(note)
    }

    private func createAndRecord() {
        let note = Note(title: "New recording")
        context.insert(note)
        recordIntentID = note.persistentModelID
        path.append(note)
    }

    private func openToday() {
        showingToday = true
        loadingMeetings = true
        Task {
            meetings = await eventKit.todaysMeetings()
            loadingMeetings = false
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

#Preview {
    NoteListView()
        .modelContainer(for: Note.self, inMemory: true)
        .environment(ThemeManager())
        .environment(EventKitService())
        .environment(SyncMonitor(cloudEnabled: false))
}
