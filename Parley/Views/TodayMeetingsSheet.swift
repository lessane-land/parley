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

// MARK: - Big calendar (iPad/Mac) — Month / Week / Day + day panel

/// Which scale the calendar is showing.
enum CalendarScale: String, CaseIterable, Identifiable {
    case month, week, day
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
}

/// How an event reads at a glance: happening *now* (live), already tied to a note
/// (linked), or a plain entry. Drives the accent treatment, mirroring the design's
/// per-kind colours without inventing data we don't have.
private enum CalEventKind { case live, linked, plain }

/// The big calendar: a Month / Week / Day stage on the left and a day panel on the
/// right (events + linked notes + a jot affordance for the selected day). It *is*
/// the navigation root (full window on iPad/Mac), so its own header carries the
/// title, the prev/Today/next nav, the scale picker, and New event; the outer
/// stack only supplies "Done" to return to the dashboard. Built on the same theme
/// tokens as the design's `--pk-*` variables, so it themes per mood.
struct MonthCalendarView: View {
    let theme: Theme
    let notes: [Note]
    let access: EventKitService.Access
    var remindersAccess: EventKitService.Access = .unknown
    var onOpenMeeting: (Meeting) -> Void
    var onOpenNote: (Note) -> Void
    var loadMeetings: (Date, Date) async -> [Meeting]
    var onAddEvent: (EventDraft) async -> Void
    /// Create a fresh note dated to a given day (the day panel's "New note").
    var onCreateNote: ((Date) -> Void)? = nil
    /// Jot a quick note for a day — created in place (no navigation), so it shows
    /// up on the calendar immediately (the day panel's "Quick note").
    var onJotNote: ((Date, String) -> Void)? = nil
    /// Load incomplete reminders due in a window (across all the user's lists).
    var loadReminders: (Date, Date) async -> [ReminderItem] = { _, _ in [] }
    /// Mark a reminder complete / incomplete.
    var onToggleReminder: (String, Bool) async -> Void = { _, _ in }
    /// Add a reminder (e.g. a prep item pushed to Reminders).
    var onAddReminder: (ReminderDraft) async -> Void = { _ in }
    /// Generate an on-device prep brief for a meeting, given its related past notes
    /// and the titles of reminders due around it.
    var generatePrep: (Meeting, [Note], [String]) async -> MeetingPrep? = { _, _, _ in nil }
    /// Why prep is unavailable (nil = the on-device model is ready).
    var prepUnavailableMessage: String? = nil
    /// Return to the dashboard (it's shown as the navigation root, not a modal).
    var onClose: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CalendarScale = .month
    /// The anchor the month/week stage is built around.
    @State private var cursor: Date = Calendar.current.startOfDay(for: Date())
    @State private var selected: Date = Calendar.current.startOfDay(for: Date())
    @State private var meetings: [Meeting] = []
    @State private var reminders: [ReminderItem] = []
    @State private var showingNewEvent = false

    private let cal = Calendar.current

    /// The week/day grids cover the whole day and scroll; they open scrolled to
    /// the morning (or just before the first event), so nothing is ever cut off.
    private let dayStartHour = 0
    private let dayEndHour = 24
    private let weekHourHeight: CGFloat = 46
    private let dayHourHeight: CGFloat = 58

    /// Shape for the accent (New event) buttons — square for Swiss/Neubrutalist.
    private var accentButtonShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.cornerRadius == 0 ? 0 : 9)
    }

    var body: some View {
        GeometryReader { geo in
            // The day panel rides alongside when there's room (always on Mac and
            // iPad landscape; it folds away on a narrow iPad portrait split).
            let showPanel = geo.size.width >= 720
            HStack(spacing: 0) {
                main
                if showPanel {
                    Divider().overlay(theme.line)
                    DayPanel(theme: theme, day: selected, meetings: eventsOn(selected),
                             notes: notesOn(selected), reminders: remindersOn(selected),
                             access: access, remindersAccess: remindersAccess,
                             linkedNote: { linkedNote($0) },
                             relatedNotes: { relatedNotes(to: $0) },
                             reminderTitlesForDay: remindersOn(selected).map(\.title),
                             prepUnavailableMessage: prepUnavailableMessage,
                             onNewEvent: { showingNewEvent = true },
                             onOpenMeeting: onOpenMeeting, onOpenNote: onOpenNote,
                             onNewNote: { onCreateNote?(selected) },
                             onJotNote: { text in onJotNote?(selected, text) },
                             onToggleReminder: { id, done in
                                 await onToggleReminder(id, done)
                                 await reloadReminders()
                             },
                             onAddReminder: { draft in
                                 await onAddReminder(draft)
                                 await reloadReminders()
                             },
                             generatePrep: generatePrep)
                        .frame(width: 320)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .moodPaper(theme)
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .sheet(isPresented: $showingNewEvent) {
            NewEventSheet(theme: theme, day: selected) { draft in
                await onAddEvent(draft)
                await reload()
            }
        }
        .task(id: rangeKey) { await reload() }
    }

    // MARK: Main column (header + stage)

    private var main: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(theme.line)
            stage
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: 16) {
            Text(headerTitle)
                .font(theme.titleFont(24, relativeTo: .title))
                .tracking(theme.titleTracking)
                .textCase(theme.titleUppercase ? .uppercase : nil)
                .foregroundStyle(theme.ink)
                .lineLimit(1)
            HStack(spacing: 4) {
                Button { step(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain).foregroundStyle(theme.inkSoft)
                Button("Today") { goToday() }
                    .font(theme.bodyFont(12.5).weight(.semibold))
                    .foregroundStyle(theme.inkSoft)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .overlay(RoundedRectangle(cornerRadius: theme.cornerRadius == 0 ? 0 : 8)
                        .strokeBorder(theme.edge, lineWidth: max(1, theme.borderWidth)))
                    .buttonStyle(.plain)
                Button { step(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.plain).foregroundStyle(theme.inkSoft)
            }
            Spacer(minLength: 8)
            Picker("View", selection: $scale.animation(.snappy)) {
                ForEach(CalendarScale.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            Button { showingNewEvent = true } label: {
                Label("New event", systemImage: "plus")
                    .font(theme.bodyFont(13).weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.paper)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(theme.accent, in: accentButtonShape)
            .overlay(accentButtonShape.strokeBorder(theme.edge, lineWidth: theme.borderWidth))
            .themeShadow(theme.shadow)
            .fixedSize()
        }
        .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 14)
    }

    @ViewBuilder
    private var stage: some View {
        switch scale {
        case .month: monthGrid
        case .week:  weekGrid
        case .day:   dayGrid
        }
    }

    // MARK: Month

    private var monthGrid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(orderedWeekdaySymbols.enumerated()), id: \.offset) { _, s in
                    Text(s.uppercased())
                        .font(theme.monoFont(10)).tracking(1)
                        .foregroundStyle(theme.inkFaint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 10)
                }
            }
            .padding(.top, 10).padding(.bottom, 8).padding(.horizontal, 14)

            GeometryReader { geo in
                let rows = 5
                let rowH = max(70, geo.size.height / CGFloat(rows))
                let gap = max(1, theme.borderWidth)   // Neubrutalist → 2px black gaps
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gap), count: 7), spacing: gap) {
                    ForEach(monthDays, id: \.self) { day in monthCell(day, height: rowH) }
                }
                .background(theme.line)
                .overlay(Rectangle().strokeBorder(theme.line, lineWidth: gap))
            }
            .padding(.horizontal, 14).padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func monthCell(_ day: Date, height: CGFloat) -> some View {
        let inMonth = cal.isDate(day, equalTo: cursor, toGranularity: .month)
        let isToday = cal.isDateInToday(day)
        let isSelected = cal.isDate(day, inSameDayAs: selected)
        let evs = eventsOn(day)
        let hasNote = !notesOn(day).isEmpty
        let hasReminder = !remindersOn(day).isEmpty
        return Button { pickDay(day) } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text("\(cal.component(.day, from: day))")
                        .font(theme.monoFont(12.5, relativeTo: .body))
                        .foregroundStyle(isToday ? theme.paper : (inMonth ? theme.ink2 : theme.inkGhost))
                        .frame(width: 22, height: 22)
                        .background(isToday ? theme.accent : .clear,
                                    in: theme.cornerRadius == 0 ? AnyShape(Rectangle()) : AnyShape(Circle()))
                    Spacer(minLength: 0)
                    if hasReminder {
                        Image(systemName: "checklist").font(.system(size: 10))
                            .foregroundStyle(theme.rec.opacity(0.8))
                    }
                    // Standalone notes read as a pencil flag (the design's noteflag);
                    // the notes themselves live in the day panel.
                    if hasNote {
                        Image(systemName: "pencil").font(.system(size: 10))
                            .foregroundStyle(theme.accent.opacity(0.7))
                    }
                }
                ForEach(evs.prefix(3)) { ev in monthChip(ev) }
                if evs.count > 3 {
                    Text("+\(evs.count - 3) more")
                        .font(theme.monoFont(10)).foregroundStyle(theme.inkFaint)
                        .padding(.leading, 6)
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
            .background(inMonth ? theme.paperRaised : theme.paperSunk)
            .overlay(isSelected ? Rectangle().strokeBorder(theme.accent, lineWidth: 2) : nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func monthChip(_ ev: Meeting) -> some View {
        let kind = eventKind(ev)
        let bg: Color = kind == .live ? theme.accent : (kind == .linked ? theme.accentTint : theme.paperSunk)
        let fg: Color = kind == .live ? theme.paper : (kind == .linked ? theme.accentInk : theme.ink2)
        return HStack(spacing: 5) {
            if kind == .live {
                Circle().fill(theme.paper).frame(width: 5, height: 5)
            } else {
                Text(ev.start, format: .dateTime.hour().minute())
                    .font(theme.monoFont(9.5))
                    .foregroundStyle(kind == .linked ? theme.accent : theme.inkFaint)
            }
            Text(ev.title).font(theme.bodyFont(11)).lineLimit(1)
            if linkedNote(ev) != nil {
                Image(systemName: "link").font(.system(size: 8)).opacity(0.6)
            }
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bg, in: RoundedRectangle(cornerRadius: theme.cornerRadius == 0 ? 0 : 5))
    }

    // MARK: Week / Day time grids

    private var weekGrid: some View {
        let days = weekDays
        return VStack(spacing: 0) {
            // weekday header row, aligned to the columns (leading time gutter).
            // The leading spacer is height-capped so it can't stretch the row.
            HStack(spacing: 0) {
                Color.clear.frame(width: 58, height: 1)
                ForEach(days, id: \.self) { d in weekHeaderCell(d) }
            }
            .padding(.trailing, 14)
            Divider().overlay(theme.line)
            ScrollViewReader { proxy in
                ScrollView {
                    HStack(alignment: .top, spacing: 0) {
                        timeGutter(hourHeight: weekHourHeight)
                        ForEach(days, id: \.self) { d in timeColumn(d, hourHeight: weekHourHeight) }
                    }
                    .padding(.trailing, 14)
                }
                .onAppear { proxy.scrollTo("h-\(defaultScrollHour)", anchor: .top) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var dayGrid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    timeGutter(hourHeight: dayHourHeight)
                    timeColumn(selected, hourHeight: dayHourHeight)
                }
                .padding(.trailing, 16)
            }
            .onAppear { proxy.scrollTo("h-\(defaultScrollHour)", anchor: .top) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Open the timeline scrolled to ~1h before the earliest event in view (else
    /// 7am), so the morning is visible without hiding an early meeting.
    private var defaultScrollHour: Int {
        let hours = meetings.map { cal.component(.hour, from: $0.start) }
        return max(0, (hours.min() ?? 8) - 1)
    }

    private func weekHeaderCell(_ d: Date) -> some View {
        let isToday = cal.isDateInToday(d)
        let isSel = cal.isDate(d, inSameDayAs: selected)
        // Design: today's date sits in a filled accent box; the *selected* day
        // (when it isn't today) gets a tinted header cell.
        return Button { pickDay(d) } label: {
            VStack(spacing: 3) {
                Text(cal.shortWeekdaySymbols[cal.component(.weekday, from: d) - 1].uppercased())
                    .font(theme.monoFont(10)).tracking(0.6).foregroundStyle(theme.inkFaint)
                Text("\(cal.component(.day, from: d))")
                    .font(theme.titleFont(17, relativeTo: .headline))
                    .foregroundStyle(isToday ? theme.paper : theme.ink)
                    .frame(width: 30, height: 30)
                    .background(isToday ? theme.accent : .clear,
                                in: theme.cornerRadius == 0 ? AnyShape(Rectangle()) : AnyShape(Circle()))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(isSel && !isToday ? theme.accentTint : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func timeGutter(hourHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(dayStartHour..<dayEndHour, id: \.self) { h in
                Text(hourLabel(h))
                    .font(theme.monoFont(10)).foregroundStyle(theme.inkFaint)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 9)
                    .frame(height: hourHeight, alignment: .top)
                    .offset(y: -6)
                    .id("h-\(h)")
            }
        }
        .frame(width: 58)
    }

    private func timeColumn(_ day: Date, hourHeight: CGFloat) -> some View {
        let isToday = cal.isDateInToday(day)
        let total = CGFloat(dayEndHour - dayStartHour) * hourHeight
        return ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(dayStartHour..<dayEndHour, id: \.self) { _ in
                    Color.clear.frame(height: hourHeight)
                        .overlay(alignment: .top) { Divider().overlay(theme.line.opacity(0.5)) }
                }
            }
            ForEach(eventsOn(day)) { ev in eventBlock(ev, hourHeight: hourHeight) }
            ForEach(notesOn(day)) { note in noteBlock(note, hourHeight: hourHeight) }
        }
        .frame(maxWidth: .infinity, minHeight: total, alignment: .topLeading)
        .background(isToday ? theme.accent.opacity(0.05) : .clear)   // today column washed (design)
        .overlay(alignment: .leading) { Divider().overlay(theme.line.opacity(0.5)) }
    }

    /// A note placed on the timeline at the time it was made (or its meeting time),
    /// so notes are directly visible in week/day — pencil for typed, waveform for
    /// recorded. Tapping opens the note.
    private func noteBlock(_ note: Note, hourHeight: CGFloat) -> some View {
        let when = note.startDate ?? note.createdAt
        let pxPerMin = hourHeight / 60
        let top = CGFloat(minutesFromDayStart(when)) * pxPerMin
        return Button { onOpenNote(note) } label: {
            HStack(spacing: 5) {
                Image(systemName: note.transcript.isEmpty ? "pencil" : "waveform")
                    .font(.system(size: 10))
                Text(note.title.isEmpty ? "New Note" : note.title)
                    .font(theme.bodyFont(11.5).weight(.semibold)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(theme.accentInk)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
            .background(theme.accentTint)
            .overlay(alignment: .leading) { Rectangle().fill(theme.accent).frame(width: 3) }
            .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius == 0 ? 0 : 6))
            .overlay(RoundedRectangle(cornerRadius: theme.cornerRadius == 0 ? 0 : 6)
                .strokeBorder(theme.edge, lineWidth: max(1, theme.borderWidth)))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .offset(y: top)
    }

    private func eventBlock(_ ev: Meeting, hourHeight: CGFloat) -> some View {
        let kind = eventKind(ev)
        let pxPerMin = hourHeight / 60
        let top = CGFloat(minutesFromDayStart(ev.start)) * pxPerMin
        let mins = max(20, ev.end.timeIntervalSince(ev.start) / 60)
        let h = max(24, CGFloat(mins) * pxPerMin)
        let bg: Color = kind == .live ? theme.accent : (kind == .linked ? theme.accentTint : theme.paperSunk)
        let fg: Color = kind == .live ? theme.paper : theme.ink
        let rail: Color = kind == .plain ? theme.inkGhost : theme.accent
        return Button { onOpenMeeting(ev) } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if kind == .live { Circle().fill(theme.paper).frame(width: 5, height: 5) }
                    Text(ev.title).font(theme.bodyFont(12).weight(.semibold)).lineLimit(1)
                }
                Text("\(timeText(ev.start))–\(timeText(ev.end))")
                    .font(theme.monoFont(10))
                    .foregroundStyle(kind == .live ? theme.paper.opacity(0.85) : theme.inkSoft)
            }
            .foregroundStyle(fg)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: h, alignment: .topLeading)
            .background(bg)
            .overlay(alignment: .leading) { Rectangle().fill(rail).frame(width: 3) }
            .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius == 0 ? 0 : 6))
            // Mood card edge (Neubrutalist gets its black border + hard shadow).
            .overlay(RoundedRectangle(cornerRadius: theme.cornerRadius == 0 ? 0 : 6)
                .strokeBorder(theme.edge, lineWidth: max(1, theme.borderWidth)))
            .themeShadow(theme.shadow)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .offset(y: top)
    }

    // MARK: Data

    private func reload() async {
        guard let first = rangeStart, let last = rangeEnd else { return }
        meetings = await loadMeetings(first, last)
        reminders = await loadReminders(first, last)
    }

    private func reloadReminders() async {
        guard let first = rangeStart, let last = rangeEnd else { return }
        reminders = await loadReminders(first, last)
    }

    private func eventsOn(_ day: Date) -> [Meeting] {
        meetings.filter { cal.isDate($0.start, inSameDayAs: day) }
            .sorted { $0.start < $1.start }
    }
    private func notesOn(_ day: Date) -> [Note] {
        notes.filter { cal.isDate($0.startDate ?? $0.createdAt, inSameDayAs: day) }
            .sorted { ($0.startDate ?? $0.createdAt) < ($1.startDate ?? $1.createdAt) }
    }
    private func remindersOn(_ day: Date) -> [ReminderItem] {
        reminders.filter { if let due = $0.due { return cal.isDate(due, inSameDayAs: day) } else { return false } }
    }
    private func linkedNote(_ meeting: Meeting) -> Note? {
        notes.first { $0.calendarEventID == meeting.id }
    }

    /// Past notes that look related to a meeting — prior instances of the same
    /// titled meeting, notes sharing attendees, or the note already linked to it.
    /// The newest few, used to ground the AI prep brief.
    private func relatedNotes(to ev: Meeting) -> [Note] {
        let title = ev.title.lowercased()
        let att = Set(ev.attendees.map { $0.lowercased() })
        return notes.filter { n in
            guard (n.startDate ?? n.createdAt) < ev.start else { return false }   // past only
            if n.calendarEventID == ev.id { return true }
            if !title.isEmpty, n.title.lowercased() == title { return true }
            if !att.isEmpty, !att.isDisjoint(with: Set(n.attendees.map { $0.lowercased() })) { return true }
            return false
        }
        .sorted { ($0.startDate ?? $0.createdAt) > ($1.startDate ?? $1.createdAt) }
        .prefix(3)
        .map { $0 }
    }
    private func eventKind(_ ev: Meeting) -> CalEventKind {
        let now = Date()
        if ev.start <= now && now < ev.end { return .live }
        if linkedNote(ev) != nil { return .linked }
        return .plain
    }

    private func minutesFromDayStart(_ date: Date) -> Int {
        let h = cal.component(.hour, from: date)
        let m = cal.component(.minute, from: date)
        return max(0, (h - dayStartHour) * 60 + m)
    }
    /// Hour label that follows the system's 12/24-hour setting ("8 AM" or "20").
    private func hourLabel(_ h: Int) -> String {
        let date = cal.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: h)) ?? Date()
        return date.formatted(.dateTime.hour())
    }
    private func timeText(_ d: Date) -> String {
        d.formatted(.dateTime.hour().minute())
    }

    // MARK: Navigation

    private func step(_ delta: Int) {
        withAnimation(.snappy) {
            switch scale {
            case .month:
                if let m = cal.date(byAdding: .month, value: delta, to: cursor) { cursor = m }
            case .week:
                if let w = cal.date(byAdding: .day, value: delta * 7, to: cursor) { cursor = w }
            case .day:
                if let d = cal.date(byAdding: .day, value: delta, to: selected) { selected = d; cursor = d }
            }
        }
    }
    private func goToday() {
        withAnimation(.snappy) {
            let t = cal.startOfDay(for: Date())
            cursor = t; selected = t
        }
    }
    private func pickDay(_ day: Date) {
        withAnimation(.snappy) {
            selected = day
            if scale != .month { cursor = day }
        }
    }

    private var headerTitle: String {
        switch scale {
        case .month: return cursor.formatted(.dateTime.month(.wide).year())
        case .week:
            let days = weekDays
            guard let s = days.first, let e = days.last else { return "" }
            let sameMonth = cal.isDate(s, equalTo: e, toGranularity: .month)
            if sameMonth {
                return "\(s.formatted(.dateTime.month(.wide))) \(cal.component(.day, from: s))–\(cal.component(.day, from: e))"
            }
            return "\(s.formatted(.dateTime.month(.abbreviated).day())) – \(e.formatted(.dateTime.month(.abbreviated).day()))"
        case .day:
            return selected.formatted(.dateTime.weekday(.wide).month(.wide).day())
        }
    }

    // MARK: Date math

    /// The grid days for the visible month (6 weeks, week-aligned).
    private var monthDays: [Date] {
        let monthStart = Self.startOfMonth(cursor)
        let weekday = cal.component(.weekday, from: monthStart)
        let leading = (weekday - cal.firstWeekday + 7) % 7
        guard let start = cal.date(byAdding: .day, value: -leading, to: monthStart) else { return [] }
        return (0..<35).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    private var weekDays: [Date] {
        let weekday = cal.component(.weekday, from: cursor)
        let leading = (weekday - cal.firstWeekday + 7) % 7
        guard let start = cal.date(byAdding: .day, value: -leading, to: cal.startOfDay(for: cursor)) else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    /// Load window: the visible month grid (covers week/day too, since they fall
    /// inside the same month most of the time; we widen to be safe).
    private var rangeStart: Date? {
        switch scale {
        case .month: return monthDays.first
        case .week: return weekDays.first
        case .day: return cal.startOfDay(for: selected)
        }
    }
    private var rangeEnd: Date? {
        let last: Date?
        switch scale {
        case .month: last = monthDays.last
        case .week: last = weekDays.last
        case .day: last = selected
        }
        guard let last else { return nil }
        return cal.date(byAdding: .day, value: 1, to: last)
    }
    /// A value that changes whenever the visible range does, so `.task(id:)`
    /// reloads meetings on navigation.
    private var rangeKey: String {
        "\(scale.rawValue)-\(rangeStart?.timeIntervalSince1970 ?? 0)"
    }

    static func startOfMonth(_ date: Date) -> Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
    }

    /// Weekday symbols rotated to the user's first weekday.
    private var orderedWeekdaySymbols: [String] {
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let shift = cal.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }
}

// MARK: - Day panel (right rail)

/// The selected day's detail: a New-event button, the day's meetings (with linked
/// notes / attendee avatars), and the notes jotted on that day. Mirrors the
/// design's `DayPanel`.
private struct DayPanel: View {
    let theme: Theme
    let day: Date
    let meetings: [Meeting]
    let notes: [Note]
    let reminders: [ReminderItem]
    let access: EventKitService.Access
    let remindersAccess: EventKitService.Access
    var linkedNote: (Meeting) -> Note?
    var relatedNotes: (Meeting) -> [Note]
    var reminderTitlesForDay: [String]
    var prepUnavailableMessage: String?
    var onNewEvent: () -> Void
    var onOpenMeeting: (Meeting) -> Void
    var onOpenNote: (Note) -> Void
    var onNewNote: () -> Void
    var onJotNote: (String) -> Void
    var onToggleReminder: (String, Bool) async -> Void
    var onAddReminder: (ReminderDraft) async -> Void
    var generatePrep: (Meeting, [Note], [String]) async -> MeetingPrep?

    private let cal = Calendar.current

    /// The quick-note jot field.
    @State private var jot = ""
    /// Per-event prep: which cards are expanded, and the result/loading state.
    @State private var expanded: Set<String> = []
    @State private var prep: [String: PrepState] = [:]
    /// Prep items the user has already pushed to Reminders this session (so the
    /// "+" turns into a check without a round-trip).
    @State private var added: Set<String> = []

    private enum PrepState: Equatable { case loading, ready(MeetingPrep), failed }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                head
                newEventButton
                section("\(meetings.count) event\(meetings.count == 1 ? "" : "s")")
                if access == .denied {
                    Text("Calendar access is off — enable it in Settings.")
                        .font(theme.bodyFont(12)).foregroundStyle(theme.inkFaint)
                        .padding(.bottom, 8)
                }
                if meetings.isEmpty {
                    Text("Nothing scheduled.")
                        .font(theme.bodyFont(13)).italic().foregroundStyle(theme.inkFaint)
                        .padding(.bottom, 8)
                }
                ForEach(meetings) { ev in eventItem(ev) }

                if !reminders.isEmpty || remindersAccess == .granted {
                    section(reminders.isEmpty ? "Reminders" : "\(reminders.count) due")
                    if reminders.isEmpty {
                        Text("Nothing due this day.")
                            .font(theme.bodyFont(13)).italic().foregroundStyle(theme.inkFaint)
                            .padding(.bottom, 8)
                    }
                    ForEach(reminders) { r in reminderRow(r) }
                }

                section(notes.isEmpty ? "Quick note" : "Notes")
                ForEach(notes) { note in noteRow(note) }
                jotField
                newNoteButton
                footer
            }
            .padding(18)
        }
        .background(theme.paperSunk)
    }

    private var head: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(cal.isDateInToday(day) ? "TODAY" : day.formatted(.dateTime.weekday(.wide)).uppercased())
                .font(theme.monoFont(11)).tracking(1).foregroundStyle(theme.accent)
            Text(day.formatted(.dateTime.month(.wide).day()))
                .font(theme.titleFont(22, relativeTo: .title2))
                .foregroundStyle(theme.ink)
        }
        .padding(.bottom, 14)
    }

    private var newEventButton: some View {
        let shape = RoundedRectangle(cornerRadius: theme.cornerRadius == 0 ? 0 : 10)
        return Button(action: onNewEvent) {
            Label("New event", systemImage: "plus")
                .font(theme.bodyFont(13).weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.paper)
        .background(theme.accent, in: shape)
        .overlay(shape.strokeBorder(theme.edge, lineWidth: theme.borderWidth))
        .themeShadow(theme.shadow)
        .padding(.bottom, 16)
    }

    /// The design's quick-note jotter: type a line and it becomes a note for this
    /// day, in place (the calendar updates immediately).
    private var jotField: some View {
        let shape = RoundedRectangle(cornerRadius: theme.cornerRadius == 0 ? 0 : 10)
        return HStack(spacing: 8) {
            TextField("Jot a note for \(day.formatted(.dateTime.month(.abbreviated).day()))…", text: $jot)
                .textFieldStyle(.plain)
                .font(theme.bodyFont(13))
                .foregroundStyle(theme.ink)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(theme.paperRaised, in: shape)
                .overlay(shape.strokeBorder(theme.edge, lineWidth: max(1, theme.borderWidth)))
                .onSubmit(submitJot)
            Button(action: submitJot) {
                Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.paper)
                    .frame(width: 40, height: 40)
                    .background(theme.accent, in: shape)
                    .overlay(shape.strokeBorder(theme.edge, lineWidth: theme.borderWidth))
                    .themeShadow(theme.shadow)
            }
            .buttonStyle(.plain)
            .disabled(jot.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.top, 6)
    }

    private func submitJot() {
        let text = jot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        onJotNote(text)
        jot = ""
    }

    private var newNoteButton: some View {
        Button(action: onNewNote) {
            Label("New note", systemImage: "square.and.pencil")
                .font(theme.bodyFont(12.5).weight(.semibold))
                .foregroundStyle(theme.accentInk)
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    private func section(_ title: String) -> some View {
        Text(title.uppercased())
            .font(theme.monoFont(10)).tracking(1)
            .foregroundStyle(theme.inkFaint)
            .padding(.top, 6).padding(.bottom, 10)
    }

    // MARK: Event card (with AI prep)

    private func eventItem(_ ev: Meeting) -> some View {
        let now = Date()
        let isLive = ev.start <= now && now < ev.end
        let linked = linkedNote(ev)
        let rail: Color = (isLive || linked != nil) ? theme.accent : theme.inkGhost
        return HStack(spacing: 0) {
            Rectangle().fill(rail).frame(width: 4)
            VStack(alignment: .leading, spacing: 0) {
                Button { onOpenMeeting(ev) } label: { eventBody(ev, isLive: isLive, linked: linked) }
                    .buttonStyle(.plain)
                if prepUnavailableMessage == nil { prepArea(ev) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.paperRaised)
        .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius == 0 ? 0 : 11))
        .overlay(RoundedRectangle(cornerRadius: theme.cornerRadius == 0 ? 0 : 11)
            .strokeBorder(theme.edge, lineWidth: max(1, theme.borderWidth)))
        .padding(.bottom, 9)
    }

    private func eventBody(_ ev: Meeting, isLive: Bool, linked: Note?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                if isLive { Circle().fill(theme.accent).frame(width: 6, height: 6) }
                Text(ev.title).font(theme.bodyFont(14).weight(.semibold))
                    .foregroundStyle(theme.ink).lineLimit(2)
            }
            Text("\(ev.start.formatted(.dateTime.hour().minute())) – \(ev.end.formatted(.dateTime.hour().minute()))")
                .font(theme.monoFont(11)).foregroundStyle(theme.inkSoft)
            HStack(spacing: 10) {
                if !ev.attendees.isEmpty { avatars(ev.attendees) }
                if let linked {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil").font(.system(size: 11))
                        Text(linked.title.isEmpty ? "Linked note" : linked.title).lineLimit(1)
                        Image(systemName: "arrow.right").font(.system(size: 10)).opacity(0.6)
                    }
                    .font(theme.bodyFont(11.5).weight(.semibold))
                    .foregroundStyle(theme.accentInk)
                } else {
                    Label("Link a note", systemImage: "link")
                        .font(theme.bodyFont(11.5).weight(.semibold))
                        .foregroundStyle(theme.inkFaint)
                }
            }
            .padding(.top, 3)
        }
        .padding(.horizontal, 12).padding(.top, 11).padding(.bottom, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func prepArea(_ ev: Meeting) -> some View {
        let isOpen = expanded.contains(ev.id)
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(theme.line)
            Button { togglePrep(ev) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 11))
                    Text(isOpen ? "Hide prep" : "Prep with Parley")
                        .font(theme.bodyFont(11.5).weight(.semibold))
                    Spacer(minLength: 0)
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down").font(.system(size: 9))
                }
                .foregroundStyle(theme.accentInk)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen { prepContent(ev) }
        }
        .padding(.horizontal, 12).padding(.bottom, 11).padding(.top, 8)
    }

    @ViewBuilder
    private func prepContent(_ ev: Meeting) -> some View {
        if let state = prep[ev.id] {
            switch state {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Preparing on device…").font(theme.bodyFont(12)).foregroundStyle(theme.inkSoft)
                }
            case .ready(let p):
                VStack(alignment: .leading, spacing: 8) {
                    if !p.context.isEmpty {
                        Text(p.context).font(theme.bodyFont(12.5)).foregroundStyle(theme.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if p.checklist.isEmpty {
                        Text("Nothing to prepare.").font(theme.bodyFont(12)).italic().foregroundStyle(theme.inkFaint)
                    } else {
                        ForEach(p.checklist, id: \.self) { item in prepItemRow(ev, item: item) }
                    }
                }
            case .failed:
                Text("Couldn't prepare right now — try again.")
                    .font(theme.bodyFont(12)).foregroundStyle(theme.inkFaint)
            }
        }
    }

    private func prepItemRow(_ ev: Meeting, item: String) -> some View {
        let key = ev.id + "|" + item
        let isAdded = added.contains(key)
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle").font(.system(size: 11)).foregroundStyle(theme.accent).padding(.top, 2)
            Text(item).font(theme.bodyFont(12.5)).foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button {
                added.insert(key)
                Task { await onAddReminder(ReminderDraft(title: item, due: ev.start)) }
            } label: {
                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(isAdded ? theme.accent : theme.inkFaint)
            }
            .buttonStyle(.plain)
            .disabled(isAdded)
            .accessibilityLabel(isAdded ? "Added to Reminders" : "Add to Reminders")
        }
    }

    private func togglePrep(_ ev: Meeting) {
        if expanded.contains(ev.id) {
            expanded.remove(ev.id)
            return
        }
        withAnimation(.snappy) { expanded.insert(ev.id) }
        let needsLoad: Bool
        switch prep[ev.id] {
        case .some(.loading), .some(.ready): needsLoad = false
        default: needsLoad = true
        }
        guard needsLoad else { return }
        prep[ev.id] = .loading
        Task { @MainActor in
            let result = await generatePrep(ev, relatedNotes(ev), reminderTitlesForDay)
            prep[ev.id] = result.map { PrepState.ready($0) } ?? .failed
        }
    }

    // MARK: Reminders

    private func reminderRow(_ r: ReminderItem) -> some View {
        Button {
            Task { await onToggleReminder(r.id, !r.completed) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: r.completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16)).foregroundStyle(r.completed ? theme.accent : theme.inkFaint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.title).font(theme.bodyFont(13.5)).foregroundStyle(theme.ink).lineLimit(2)
                    if let due = r.due {
                        Text(due.formatted(.dateTime.hour().minute()))
                            .font(theme.monoFont(10.5)).foregroundStyle(theme.inkSoft)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.paperRaised)
            .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius == 0 ? 0 : 10))
            .overlay(RoundedRectangle(cornerRadius: theme.cornerRadius == 0 ? 0 : 10)
                .strokeBorder(theme.edge, lineWidth: max(1, theme.borderWidth)))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
    }

    private func avatars(_ names: [String]) -> some View {
        HStack(spacing: -5) {
            ForEach(Array(names.prefix(4).enumerated()), id: \.offset) { _, name in
                CalAvatar(theme: theme, name: name, size: 20)
            }
        }
    }

    /// A day's note in the design's "quick note" style: an accent-tinted card with
    /// a pencil tack (waveform for recordings). Tapping opens it.
    private func noteRow(_ note: Note) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.cornerRadius == 0 ? 0 : 10)
        return Button { onOpenNote(note) } label: {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: note.transcript.isEmpty ? "pencil" : "waveform")
                    .font(.system(size: 12)).foregroundStyle(theme.accent).padding(.top, 1)
                Text(note.title.isEmpty ? "New Note" : note.title)
                    .font(theme.bodyFont(13)).foregroundStyle(theme.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading).lineLimit(2)
            }
            .padding(.horizontal, 13).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.accentTint, in: shape)
            .overlay(shape.strokeBorder(theme.edge, lineWidth: theme.borderWidth))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Image(systemName: "bolt.fill").font(.system(size: 11)).foregroundStyle(theme.accent)
            Text("Notes, events & prep stay on this device")
                .font(theme.bodyFont(11)).foregroundStyle(theme.inkFaint)
        }
        .padding(.top, 14)
    }
}

/// A small initials avatar with a stable per-name colour. Stands in for the
/// design's people avatars (we only have attendee display names from EventKit).
private struct CalAvatar: View {
    let theme: Theme
    let name: String
    let size: CGFloat

    private static let palette = ["3E5C50", "B14B3A", "5A6B7A", "7A5A8A", "C08A2D", "4A7B8A"]

    var body: some View {
        Circle()
            .fill(Color(hex: Self.palette[colorIndex]))
            .frame(width: size, height: size)
            .overlay(Text(initials).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.white))
            .overlay(Circle().strokeBorder(theme.paperRaised, lineWidth: 2))
    }

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init)
        return letters.joined().uppercased()
    }
    private var colorIndex: Int {
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return sum % Self.palette.count
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
