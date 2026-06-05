import Foundation
import FoundationModels

/// The stored + displayed summary (Codable; persisted on `note.summaryData`).
/// Action items carry user state (done) on top of the generated content.
struct MeetingSummary: Codable, Equatable {
    var overview: String
    var decisions: [Decision]
    var actionItems: [ActionItem]
    var openQuestions: [String]
}

/// One action item: the generated task + owner, plus the user's checkbox state.
struct ActionItem: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var owner: String = ""     // empty == no owner mentioned
    var done: Bool = false
}

/// One decision: what was decided, plus an optional rationale (the "why").
/// Structured (rather than a plain string) so the UI can surface the decision
/// prominently with its reasoning as a secondary line.
struct Decision: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var text: String
    var rationale: String = ""   // empty == no rationale captured

    init(text: String, rationale: String = "") {
        self.text = text
        self.rationale = rationale
    }

    /// Back-compat: summaries generated before the structured `Decision` type
    /// stored each decision as a bare JSON string. Decode either shape so an
    /// older cached summary still loads instead of silently vanishing.
    init(from decoder: any Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) {
            self.text = text
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try c.decode(String.self, forKey: .text)
        rationale = try c.decodeIfPresent(String.self, forKey: .rationale) ?? ""
    }
}

// MARK: - Generation shapes (what the model produces, kept separate from storage)

/// `@Generable` (Foundation Models) — guided generation fills this exact shape.
@Generable
private struct SummaryDraft {
    @Guide(description: "A one or two sentence overview of what the meeting was about.")
    var overview: String
    @Guide(description: "Concrete decisions that were made. Empty if none.")
    var decisions: [DecisionDraft]
    @Guide(description: "Action items from the meeting. Empty if none.")
    var actions: [ActionDraft]
    @Guide(description: "Open questions or unresolved topics needing follow-up. Empty if none.")
    var openQuestions: [String]
}

@Generable
private struct ActionDraft {
    @Guide(description: "The task as a short imperative phrase.")
    var title: String
    @Guide(description: "The person responsible, or empty if none was mentioned.")
    var owner: String
}

@Generable
private struct DecisionDraft {
    @Guide(description: "The decision that was made, as a short statement.")
    var text: String
    @Guide(description: "A brief reason for the decision, or empty if none was given.")
    var rationale: String
}

/// Runs the "Granola magic" entirely on-device: merge the user's sparse notes
/// with the full transcript into a clean, structured summary.
@MainActor
@Observable
final class SummaryService {
    enum State: Equatable {
        case idle
        case working
        case unavailable(String)
    }

    private(set) var state: State = .idle

    /// `nil` if the on-device model is ready; otherwise a human message.
    func availabilityMessage() -> String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This device doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings to generate summaries."
        case .unavailable(.modelNotReady):
            return "The on-device model is still downloading. Try again shortly."
        case .unavailable(let other):
            return "On-device summaries are unavailable (\(other))."
        }
    }

    func summarize(notes: String, transcript: String, attendees: [String] = [],
                   tone: SummaryTone = .balanced,
                   includeDecisions: Bool = true,
                   includeActionItems: Bool = true,
                   includeOpenQuestions: Bool = true) async -> MeetingSummary? {
        if let message = availabilityMessage() {
            state = .unavailable(message)
            return nil
        }

        state = .working
        let session = LanguageModelSession(instructions: """
        You are a meeting-notes assistant. From a user's sparse notes and a full \
        transcript, produce a clean, faithful summary. Only include information \
        supported by the inputs — never invent facts. \(tone.guidance) If a section \
        has nothing, return an empty list.
        """)
        do {
            let draft = try await session.respond(
                to: Self.prompt(notes: notes, transcript: transcript, attendees: attendees),
                generating: SummaryDraft.self
            ).content
            state = .idle
            // Honor the "Always extract" toggles regardless of what the model
            // returned, so a turned-off section is reliably empty.
            return MeetingSummary(
                overview: draft.overview,
                decisions: includeDecisions ? draft.decisions.map { Decision(text: $0.text, rationale: $0.rationale) } : [],
                actionItems: includeActionItems ? draft.actions.map { ActionItem(title: $0.title, owner: $0.owner) } : [],
                openQuestions: includeOpenQuestions ? draft.openQuestions : []
            )
        } catch {
            state = .unavailable(error.localizedDescription)
            return nil
        }
    }

    private static func prompt(notes: String, transcript: String, attendees: [String]) -> String {
        """
        ATTENDEES:
        \(attendees.isEmpty ? "(unknown)" : attendees.joined(separator: ", "))

        USER NOTES:
        \(notes.isEmpty ? "(none)" : notes)

        TRANSCRIPT:
        \(transcript.isEmpty ? "(none)" : transcript)

        Summarize this meeting. When assigning action-item owners, prefer names \
        from the attendee list.
        """
    }
}
