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
private struct NewEventSheet: View {
    let theme: Theme
    var onSave: (EventDraft) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var start = NewEventSheet.nextHour()
    @State private var end = NewEventSheet.nextHour().addingTimeInterval(3600)
    @State private var saving = false

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
