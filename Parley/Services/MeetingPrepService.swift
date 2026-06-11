import Foundation
import FoundationModels

/// What the user should know and do *before* an upcoming meeting — generated
/// on-device from the meeting's related history and any pending reminders.
struct MeetingPrep: Equatable {
    /// One or two sentences: what this meeting is about / where it stands.
    var context: String
    /// Concrete things to do beforehand (short imperatives).
    var checklist: [String]
}

/// `@Generable` (Foundation Models) — guided generation fills this exact shape.
@Generable
private struct PrepDraft {
    @Guide(description: "One or two sentences of context: what this meeting is likely about and where it stands, based ONLY on the provided history. Empty if there's no history to go on.")
    var context: String
    @Guide(description: "2 to 5 concrete things to do BEFORE the meeting, each a short imperative phrase. Empty if there's genuinely nothing to prepare.")
    var checklist: [String]
}

/// Produces a short "before this meeting" brief entirely on-device (Foundation
/// Models). Stateless: callers own any per-event loading state and caching. Like
/// the rest of Inkling's AI, it only uses information it's given — it never invents
/// people, facts, or tasks.
@MainActor
@Observable
final class MeetingPrepService {
    /// `nil` if the on-device model is ready; otherwise a human message.
    func availabilityMessage() -> String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This device doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings to prepare for meetings."
        case .unavailable(.modelNotReady):
            return "The on-device model is still downloading. Try again shortly."
        case .unavailable(let other):
            return "Meeting prep is unavailable (\(other))."
        }
    }

    /// Generate a prep brief for one meeting. `historyText` is a compact digest of
    /// related past notes (summaries, open questions, pending actions); `reminders`
    /// are titles of reminders due around the meeting.
    func generate(title: String, when: Date, attendees: [String],
                  historyText: String, reminders: [String]) async -> MeetingPrep? {
        guard availabilityMessage() == nil else { return nil }

        let session = LanguageModelSession(instructions: """
        You help the user get ready for an upcoming meeting. Using the related past \
        notes and any pending reminders, write a brief context line and list the \
        concrete things to do BEFORE the meeting. Use ONLY the information provided — \
        never invent people, facts, or tasks. Lean on prior open questions and \
        unfinished action items when they exist. If there's little to go on, give a \
        short, sensible prep. Keep every item short and actionable.
        """)
        do {
            let draft = try await session.respond(
                to: Self.prompt(title: title, when: when, attendees: attendees,
                                historyText: historyText, reminders: reminders),
                generating: PrepDraft.self
            ).content
            let cleaned = draft.checklist
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return MeetingPrep(context: draft.context.trimmingCharacters(in: .whitespacesAndNewlines),
                               checklist: cleaned)
        } catch {
            return nil
        }
    }

    private static func prompt(title: String, when: Date, attendees: [String],
                               historyText: String, reminders: [String]) -> String {
        """
        MEETING: \(title.isEmpty ? "Untitled meeting" : title)
        WHEN: \(when.formatted(.dateTime.weekday(.wide).month().day().hour().minute()))
        ATTENDEES: \(attendees.isEmpty ? "(unknown)" : attendees.joined(separator: ", "))

        PENDING REMINDERS (due around this time):
        \(reminders.isEmpty ? "(none)" : reminders.map { "• \($0)" }.joined(separator: "\n"))

        RELATED PAST NOTES:
        \(historyText.isEmpty ? "(no related past notes)" : historyText)

        Write the context line, then list what to do before this meeting.
        """
    }
}
