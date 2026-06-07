import Foundation
import EventKit

/// Calendar + Reminders, behind one small service (per the "capability behind a
/// manager" convention). Reads today's meetings and writes action items as
/// reminders — all local, via Apple's EventKit. Nothing syncs to a third party.
///
/// `@MainActor @Observable` so views can read the access states.
@MainActor
@Observable
final class EventKitService {
    enum Access { case unknown, granted, denied }

    private(set) var calendarAccess: Access = .unknown
    private(set) var remindersAccess: Access = .unknown

    /// One store serves both calendar and reminders.
    private let store = EKEventStore()

    // MARK: Calendar

    /// Today's timed meetings, soonest first, as plain value types (we don't let
    /// `EKEvent` leak into the views).
    func todaysMeetings() async -> [Meeting] {
        guard await ensureCalendarAccess() else { return [] }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
            .map(Meeting.init)
    }

    /// Timed meetings from today through the next `days`, soonest first — for the
    /// in-app Calendar (not just today).
    func upcomingMeetings(days: Int = 14) async -> [Meeting] {
        guard await ensureCalendarAccess() else { return [] }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: days, to: start) else { return [] }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
            .map(Meeting.init)
    }

    /// Create a calendar event from a draft (in the user's default calendar) and
    /// return it as a `Meeting` so the caller can link/refresh. Needs calendar
    /// **write** access (the same full-access prompt we already request).
    @discardableResult
    func addEvent(_ draft: EventDraft) async -> Meeting? {
        guard await ensureCalendarAccess() else { return nil }
        guard let calendar = store.defaultCalendarForNewEvents
                ?? store.calendars(for: .event).first(where: { $0.allowsContentModifications }) else { return nil }
        let event = EKEvent(eventStore: store)
        event.title = draft.title.isEmpty ? "New event" : draft.title
        event.startDate = draft.start
        // Guard against a zero/negative duration.
        event.endDate = max(draft.end, draft.start.addingTimeInterval(900))
        event.calendar = calendar
        if let notes = draft.notes, !notes.isEmpty { event.notes = notes }
        do {
            try store.save(event, span: .thisEvent, commit: true)
            return Meeting(event)
        } catch {
            return nil
        }
    }

    /// Timed meetings in an arbitrary date range (for the month calendar grid).
    func meetings(from start: Date, to end: Date) async -> [Meeting] {
        guard await ensureCalendarAccess() else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
            .map(Meeting.init)
    }

    // MARK: Reminders

    /// The title of the dedicated reminders list Parley owns. Action items the app
    /// creates go here, and the in-app Reminders screen reads only from it — so the
    /// app's reminders stay grouped and separate from the user's other lists.
    private let parleyListTitle = "Parley"

    /// Parley's reminders (incomplete by default), soonest due first — for the
    /// in-app Reminders list. Reads only from the "Parley" list; if it doesn't
    /// exist yet (nothing's been added), returns empty.
    func fetchReminders(includingCompleted: Bool = false) async -> [ReminderItem] {
        guard await ensureRemindersAccess() else { return [] }
        guard let list = findParleyList() else { return [] }
        let predicate = includingCompleted
            ? store.predicateForReminders(in: [list])
            : store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: [list])
        let reminders: [EKReminder] = await withCheckedContinuation { continuation in
            _ = store.fetchReminders(matching: predicate) { continuation.resume(returning: $0 ?? []) }
        }
        return reminders
            .sorted { ($0.dueDateComponents?.date ?? .distantFuture) < ($1.dueDateComponents?.date ?? .distantFuture) }
            .map(ReminderItem.init)
    }

    /// Incomplete reminders due within a date window, across **all** the user's
    /// lists (not just Parley's) — so the calendar can show what's due in the same
    /// window of time as their events. Soonest due first.
    func reminders(from start: Date, to end: Date) async -> [ReminderItem] {
        guard await ensureRemindersAccess() else { return [] }
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: start, ending: end, calendars: nil)
        let reminders: [EKReminder] = await withCheckedContinuation { continuation in
            _ = store.fetchReminders(matching: predicate) { continuation.resume(returning: $0 ?? []) }
        }
        return reminders
            .sorted { ($0.dueDateComponents?.date ?? .distantFuture) < ($1.dueDateComponents?.date ?? .distantFuture) }
            .map(ReminderItem.init)
    }

    /// The existing "Parley" reminders list, or nil if it hasn't been created yet.
    private func findParleyList() -> EKCalendar? {
        store.calendars(for: .reminder).first { $0.title == parleyListTitle }
    }

    /// The "Parley" reminders list, creating it on first use. A reminders calendar
    /// needs a source that supports reminders — we borrow the default reminders
    /// list's source (iCloud/local), falling back to a local source.
    private func getOrCreateParleyList() -> EKCalendar? {
        if let existing = findParleyList() { return existing }
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = parleyListTitle
        calendar.source = store.defaultCalendarForNewReminders()?.source
            ?? store.sources.first { $0.sourceType == .local }
            ?? store.sources.first
        guard calendar.source != nil else { return nil }
        do {
            try store.saveCalendar(calendar, commit: true)
            return calendar
        } catch {
            // Lost a race, or the source rejected it — fall back to whatever exists.
            return findParleyList()
        }
    }

    /// Mark a reminder complete/incomplete by its identifier.
    @discardableResult
    func setReminderCompleted(id: String, completed: Bool) async -> Bool {
        guard await ensureRemindersAccess() else { return false }
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return false }
        reminder.isCompleted = completed
        return (try? store.save(reminder, commit: true)) != nil
    }

    /// Saves each title as a reminder in the default list. Returns how many were
    /// written. (Convenience for the bulk/no-date path.)
    @discardableResult
    func addReminders(_ titles: [String]) async -> Int {
        await addReminders(titles.map { ReminderDraft(title: $0, due: nil) })
    }

    /// Saves each draft as a reminder in Parley's own list (created on first use),
    /// carrying its due date through to the Reminders app when one was set. Returns
    /// how many were written.
    @discardableResult
    func addReminders(_ drafts: [ReminderDraft]) async -> Int {
        guard await ensureRemindersAccess() else { return 0 }
        guard let list = getOrCreateParleyList() else { return 0 }

        var saved = 0
        for draft in drafts {
            let reminder = EKReminder(eventStore: store)
            reminder.title = draft.title
            reminder.calendar = list
            if let due = draft.due {
                // Day-granularity due date; an alarm makes it actually notify.
                reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: due)
                reminder.addAlarm(EKAlarm(absoluteDate: due))
            }
            if (try? store.save(reminder, commit: false)) != nil { saved += 1 }
        }
        try? store.commit()
        return saved
    }

    // MARK: Access

    private func ensureCalendarAccess() async -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized:
            calendarAccess = .granted
            return true
        case .notDetermined:
            let granted = (try? await store.requestFullAccessToEvents()) ?? false
            calendarAccess = granted ? .granted : .denied
            return granted
        default:
            calendarAccess = .denied
            return false
        }
    }

    private func ensureRemindersAccess() async -> Bool {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess, .authorized:
            remindersAccess = .granted
            return true
        case .notDetermined:
            let granted = (try? await store.requestFullAccessToReminders()) ?? false
            remindersAccess = granted ? .granted : .denied
            return granted
        default:
            remindersAccess = .denied
            return false
        }
    }
}

/// A plain, view-friendly snapshot of a calendar event.
struct Meeting: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let attendees: [String]
    /// The source calendar's name (e.g. "Work", "Home") — shown after the time
    /// like the design's "· Meeting / · Product" label, but from real data.
    let calendarName: String

    init(_ event: EKEvent) {
        id = event.eventIdentifier ?? UUID().uuidString
        title = event.title ?? "Untitled meeting"
        start = event.startDate
        end = event.endDate
        attendees = (event.attendees ?? []).compactMap(\.name)
        calendarName = event.calendar?.title ?? ""
    }
}

/// A plain, view-friendly snapshot of a reminder.
struct ReminderItem: Identifiable {
    let id: String
    let title: String
    let completed: Bool
    let due: Date?

    init(_ reminder: EKReminder) {
        id = reminder.calendarItemIdentifier
        title = reminder.title ?? "Untitled"
        completed = reminder.isCompleted
        due = reminder.dueDateComponents?.date
    }
}

/// A reminder to be written: a title plus an optional real due date. Lets the
/// summary pass a user-set date straight through to the Reminders app.
struct ReminderDraft {
    let title: String
    let due: Date?
}

/// A calendar event to be created.
struct EventDraft {
    var title: String
    var start: Date
    var end: Date
    var notes: String? = nil
}

/// Heuristic action-item detection. This is a deliberate **placeholder** for
/// Phase 3 — Phase 4 replaces it with on-device Foundation Models extraction.
/// For now it picks out checklist/bullet lines and a few keyword prefixes.
enum ActionItemDetector {
    static func detect(in text: String) -> [String] {
        let bulletMarkers = ["- [ ]", "- []", "[]", "- ", "* ", "• ", "· "]
        let keywordPrefixes = ["todo:", "todo ", "action item:", "action:", "ai:", "follow up:", "follow-up:"]

        var items: [String] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let lower = line.lowercased()

            var item: String?
            for marker in bulletMarkers where line.hasPrefix(marker) {
                item = String(line.dropFirst(marker.count)); break
            }
            if item == nil {
                for keyword in keywordPrefixes where lower.hasPrefix(keyword) {
                    item = String(line.dropFirst(keyword.count)); break
                }
            }
            if item == nil, lower.contains("action item") {
                item = line
            }

            if let cleaned = item?.trimmingCharacters(in: .whitespaces), !cleaned.isEmpty {
                items.append(cleaned)
            }
        }

        // De-duplicate, preserving order.
        var seen = Set<String>()
        return items.filter { seen.insert($0.lowercased()).inserted }
    }
}
