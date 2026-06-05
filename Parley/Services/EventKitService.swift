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

    // MARK: Reminders

    /// The user's reminders (incomplete by default), soonest due first — for the
    /// in-app Reminders list.
    func fetchReminders(includingCompleted: Bool = false) async -> [ReminderItem] {
        guard await ensureRemindersAccess() else { return [] }
        let predicate = includingCompleted
            ? store.predicateForReminders(in: nil)
            : store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let reminders: [EKReminder] = await withCheckedContinuation { continuation in
            _ = store.fetchReminders(matching: predicate) { continuation.resume(returning: $0 ?? []) }
        }
        return reminders
            .sorted { ($0.dueDateComponents?.date ?? .distantFuture) < ($1.dueDateComponents?.date ?? .distantFuture) }
            .map(ReminderItem.init)
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

    /// Saves each draft as a reminder, carrying its due date through to the
    /// Reminders app when one was set. Returns how many were written.
    @discardableResult
    func addReminders(_ drafts: [ReminderDraft]) async -> Int {
        guard await ensureRemindersAccess() else { return 0 }
        guard let list = store.defaultCalendarForNewReminders() else { return 0 }

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

    init(_ event: EKEvent) {
        id = event.eventIdentifier ?? UUID().uuidString
        title = event.title ?? "Untitled meeting"
        start = event.startDate
        end = event.endDate
        attendees = (event.attendees ?? []).compactMap(\.name)
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
