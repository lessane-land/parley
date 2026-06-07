import SwiftUI

/// Lists today's calendar meetings; tapping one creates (or reopens) a note.
/// A "dumb" view — the owner loads the meetings and handles the tap.
struct TodayMeetingsSheet: View {
    let theme: Theme
    let meetings: [Meeting]
    let access: EventKitService.Access
    let isLoading: Bool
    let onPick: (Meeting) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .background(theme.paperSunk)
                .navigationTitle("Today")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            centered { ProgressView() }
        } else if access == .denied {
            message("Calendar access is off", "Enable it in Settings to pull in today's meetings.", "calendar.badge.exclamationmark")
        } else if meetings.isEmpty {
            message("No meetings today", "Nothing on the calendar for the rest of today.", "calendar")
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(meetings) { meeting in
                        Button { onPick(meeting); dismiss() } label: {
                            MeetingRow(theme: theme, meeting: meeting)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
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
                .multilineTextAlignment(.center).frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

/// The in-app Calendar: upcoming meetings grouped by day (not just today). Tapping
/// one creates (or reopens) a note, like the Today sheet.
struct CalendarSheet: View {
    let theme: Theme
    let meetings: [Meeting]
    let access: EventKitService.Access
    let isLoading: Bool
    let onPick: (Meeting) -> Void
    /// Create a calendar event (nil hides the + button).
    var onAddEvent: ((EventDraft) async -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var showingNewEvent = false

    private struct DayGroup: Identifiable {
        let id: Date
        let items: [Meeting]
    }

    private var grouped: [DayGroup] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: meetings) { cal.startOfDay(for: $0.start) }
        return dict.keys.sorted().map { DayGroup(id: $0, items: (dict[$0] ?? []).sorted { $0.start < $1.start }) }
    }

    var body: some View {
        NavigationStack {
            content
                .background(theme.paperSunk)
                .navigationTitle("Calendar")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    if onAddEvent != nil {
                        ToolbarItem(placement: .primaryAction) {
                            Button { showingNewEvent = true } label: { Image(systemName: "plus") }
                                .accessibilityLabel("New Event")
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
                .sheet(isPresented: $showingNewEvent) {
                    NewEventSheet(theme: theme) { draft in await onAddEvent?(draft) }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if access == .denied {
            calMessage("Calendar access is off", "Enable it in Settings to see your meetings.", "calendar.badge.exclamationmark")
        } else if meetings.isEmpty {
            calMessage("No upcoming meetings", "Nothing scheduled in the next couple of weeks.", "calendar")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(grouped) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(dayLabel(group.id))
                                .font(theme.monoFont(11)).tracking(1.2).foregroundStyle(theme.inkSoft)
                            ForEach(group.items) { meeting in
                                Button { onPick(meeting); dismiss() } label: { MeetingRow(theme: theme, meeting: meeting) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    private func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "TODAY" }
        if cal.isDateInTomorrow(date) { return "TOMORROW" }
        return date.formatted(.dateTime.weekday(.wide).month().day()).uppercased()
    }

    private func calMessage(_ title: String, _ detail: String, _ icon: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 32)).foregroundStyle(theme.inkFaint)
            Text(title).font(theme.titleFont(18, relativeTo: .headline)).foregroundStyle(theme.ink)
            Text(detail).font(theme.bodyFont(13)).foregroundStyle(theme.inkSoft)
                .multilineTextAlignment(.center).frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
    }
}

private struct MeetingRow: View {
    let theme: Theme
    let meeting: Meeting

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(meeting.start, format: .dateTime.hour().minute())
                    .font(theme.monoFont(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.accentInk)
                Text(meeting.end, format: .dateTime.hour().minute())
                    .font(theme.monoFont(11, relativeTo: .caption))
                    .foregroundStyle(theme.inkFaint)
            }
            .frame(width: 56, alignment: .trailing)

            Rectangle().fill(theme.accent).frame(width: 3).clipShape(Capsule())

            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.title)
                    .font(theme.titleFont(16, relativeTo: .headline))
                    .tracking(theme.titleTracking)
                    .textCase(theme.titleUppercase ? .uppercase : nil)
                    .foregroundStyle(theme.ink)
                    .lineLimit(2)
                if !meeting.attendees.isEmpty {
                    Label(meeting.attendees.joined(separator: ", "),
                          systemImage: "person.2")
                        .font(theme.bodyFont(12))
                        .foregroundStyle(theme.inkSoft)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moodCard(theme)
    }
}

/// A small form to create a calendar event (title + start/end). Used by the
/// Calendar sheet's "+" button.
struct NewEventSheet: View {
    let theme: Theme
    var onSave: (EventDraft) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var start: Date
    @State private var end: Date
    @State private var saving = false

    init(theme: Theme, day: Date = Date(), prefillTitle: String = "",
         onSave: @escaping (EventDraft) async -> Void) {
        self.theme = theme
        self.onSave = onSave
        _title = State(initialValue: prefillTitle)
        let base = NewEventSheet.startTime(on: day)
        _start = State(initialValue: base)
        _end = State(initialValue: base.addingTimeInterval(3600))
    }

    /// Next whole hour today; 9:00 on another day.
    static func startTime(on day: Date) -> Date {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return nextHour() }
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                DatePicker("Starts", selection: $start)
                DatePicker("Ends", selection: $end, in: start...)
            }
            .formStyle(.grouped)
            .tint(theme.accent)
            .navigationTitle("New Event")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        saving = true
                        let draft = EventDraft(title: title, start: start,
                                               end: max(end, start.addingTimeInterval(900)))
                        Task { await onSave(draft); dismiss() }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
            .onChange(of: start) { _, newStart in
                if end <= newStart { end = newStart.addingTimeInterval(3600) }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 240)
        #endif
    }

    /// The next whole hour — a sensible default start.
    static func nextHour() -> Date {
        let cal = Calendar.current
        let soon = Date().addingTimeInterval(3600)
        return cal.date(from: cal.dateComponents([.year, .month, .day, .hour], from: soon)) ?? soon
    }
}

// MARK: - Month calendar (iPad/Mac)

/// A full month-grid calendar: each day shows dots for meetings (accent) and notes
/// (ink); tap a day to see/Create its meetings + notes below. The "＋" adds an event
/// to the selected day. Meetings load per visible month via `loadMeetings`.
struct MonthCalendarView: View {
    let theme: Theme
    let notes: [Note]
    let access: EventKitService.Access
    var onOpenMeeting: (Meeting) -> Void
    var onOpenNote: (Note) -> Void
    var loadMeetings: (Date, Date) async -> [Meeting]
    var onAddEvent: (EventDraft) async -> Void
    /// Return to the dashboard (it's shown as the navigation root, not a modal).
    var onClose: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var month: Date = MonthCalendarView.startOfMonth(Date())
    @State private var selected: Date = Calendar.current.startOfDay(for: Date())
    @State private var meetings: [Meeting] = []
    @State private var showingNewEvent = false

    private let cal = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        // No inner NavigationStack — this view *is* the stack's root (full window),
        // so the toolbar/title belong to the outer stack.
        VStack(spacing: 0) {
            monthHeader
            weekdayHeader
            grid
            Divider().overlay(theme.line)
            dayDetail
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.paperSunk)
        .navigationTitle("Calendar")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingNewEvent = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New Event")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { onClose?() ?? dismiss() }
            }
        }
        .sheet(isPresented: $showingNewEvent) {
            // Pre-fill the new event on the selected day.
            NewEventSheet(theme: theme, day: selected) { draft in
                await onAddEvent(draft)
                await reload()
            }
        }
        .task(id: month) { await reload() }
    }

    // MARK: Header

    private var monthHeader: some View {
        HStack(spacing: 14) {
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(theme.titleFont(22, relativeTo: .title2))
                .tracking(theme.titleTracking)
                .foregroundStyle(theme.ink)
            Spacer()
            Button("Today") { withAnimation(.snappy) { month = Self.startOfMonth(Date()); selected = cal.startOfDay(for: Date()) } }
                .font(theme.bodyFont(13).weight(.semibold))
                .foregroundStyle(theme.accentInk)
            Button { step(-1) } label: { Image(systemName: "chevron.left") }
            Button { step(1) } label: { Image(systemName: "chevron.right") }
        }
        .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 10)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 6) {
            ForEach(Array(orderedWeekdaySymbols.enumerated()), id: \.offset) { _, s in
                Text(s.uppercased())
                    .font(theme.monoFont(10)).tracking(0.5)
                    .foregroundStyle(theme.inkFaint)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12).padding(.bottom, 6)
    }

    // MARK: Grid

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(gridDays, id: \.self) { day in dayCell(day) }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private func dayCell(_ day: Date) -> some View {
        let inMonth = cal.isDate(day, equalTo: month, toGranularity: .month)
        let isToday = cal.isDateInToday(day)
        let isSelected = cal.isDate(day, inSameDayAs: selected)
        let mtgCount = eventsOn(day).count
        let noteCount = notesOn(day).count
        let shape = RoundedRectangle(cornerRadius: theme.cornerRadius == 0 ? 0 : 8, style: .continuous)
        return Button { withAnimation(.snappy) { selected = day } } label: {
            VStack(spacing: 4) {
                Text("\(cal.component(.day, from: day))")
                    .font(theme.monoFont(13, relativeTo: .body))
                    .foregroundStyle(isSelected ? theme.paper : (inMonth ? theme.ink : theme.inkGhost))
                HStack(spacing: 3) {
                    if mtgCount > 0 { Circle().fill(isSelected ? theme.paper : theme.accent).frame(width: 5, height: 5) }
                    if noteCount > 0 { Circle().fill(isSelected ? theme.paper.opacity(0.7) : theme.inkFaint).frame(width: 5, height: 5) }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(isSelected ? theme.accent : .clear, in: shape)
            .overlay(shape.strokeBorder(isToday && !isSelected ? theme.accent : .clear, lineWidth: 1.5))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
    }

    // MARK: Selected-day detail

    private var dayDetail: some View {
        let dayMeetings = eventsOn(selected)
        let dayNotes = notesOn(selected)
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(selected.formatted(.dateTime.weekday(.wide).month().day()))
                    .font(theme.titleFont(16, relativeTo: .headline)).foregroundStyle(theme.ink)

                if access == .denied {
                    Text("Calendar access is off — enable it in Settings to see meetings.")
                        .font(theme.bodyFont(12)).foregroundStyle(theme.inkFaint)
                }
                if dayMeetings.isEmpty && dayNotes.isEmpty {
                    Text("Nothing on this day. Tap ＋ to add an event.")
                        .font(theme.bodyFont(13)).foregroundStyle(theme.inkFaint)
                }
                ForEach(dayMeetings) { meeting in
                    Button { onOpenMeeting(meeting) } label: { MeetingRow(theme: theme, meeting: meeting) }
                        .buttonStyle(.plain)
                }
                if !dayNotes.isEmpty {
                    Text("NOTES").font(theme.monoFont(10)).tracking(1.2).foregroundStyle(theme.inkFaint).padding(.top, 4)
                    ForEach(dayNotes) { note in
                        Button { onOpenNote(note) } label: { noteRow(note) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func noteRow(_ note: Note) -> some View {
        HStack(spacing: 10) {
            Image(systemName: note.transcript.isEmpty ? "note.text" : "waveform")
                .foregroundStyle(theme.accent).frame(width: 18)
            Text(note.title.isEmpty ? "New Note" : note.title)
                .font(theme.bodyFont(14)).foregroundStyle(theme.ink).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moodCard(theme)
    }

    // MARK: Data

    private func reload() async {
        guard let first = gridDays.first, let last = gridDays.last,
              let end = cal.date(byAdding: .day, value: 1, to: last) else { return }
        meetings = await loadMeetings(first, end)
    }

    private func eventsOn(_ day: Date) -> [Meeting] {
        meetings.filter { cal.isDate($0.start, inSameDayAs: day) }
    }
    private func notesOn(_ day: Date) -> [Note] {
        notes.filter { cal.isDate($0.startDate ?? $0.createdAt, inSameDayAs: day) }
            .sorted { ($0.startDate ?? $0.createdAt) < ($1.startDate ?? $1.createdAt) }
    }

    private func step(_ delta: Int) {
        guard let m = cal.date(byAdding: .month, value: delta, to: month) else { return }
        withAnimation(.snappy) { month = Self.startOfMonth(m) }
    }

    /// The 42 days (6 weeks) covering the visible month, week-aligned.
    private var gridDays: [Date] {
        let monthStart = Self.startOfMonth(month)
        let weekday = cal.component(.weekday, from: monthStart)
        let leading = (weekday - cal.firstWeekday + 7) % 7
        guard let start = cal.date(byAdding: .day, value: -leading, to: monthStart) else { return [] }
        return (0..<42).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    /// Weekday symbols rotated to the user's first weekday.
    private var orderedWeekdaySymbols: [String] {
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let shift = cal.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    static func startOfMonth(_ date: Date) -> Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
    }
}

/// A small form to create a reminder (title + optional due date). Used from a note.
struct NewReminderSheet: View {
    let theme: Theme
    var onSave: (ReminderDraft) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var hasDue = false
    @State private var due = NewEventSheet.nextHour()
    @State private var saving = false

    init(theme: Theme, prefillTitle: String = "", onSave: @escaping (ReminderDraft) async -> Void) {
        self.theme = theme
        self.onSave = onSave
        _title = State(initialValue: prefillTitle)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Reminder", text: $title)
                Toggle("Due date", isOn: $hasDue.animation())
                if hasDue { DatePicker("Due", selection: $due) }
            }
            .formStyle(.grouped)
            .tint(theme.accent)
            .navigationTitle("New Reminder")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        saving = true
                        let draft = ReminderDraft(title: title, due: hasDue ? due : nil)
                        Task { await onSave(draft); dismiss() }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 200)
        #endif
    }
}
