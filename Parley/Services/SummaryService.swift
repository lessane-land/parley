import Foundation
import FoundationModels

/// The structured shape we ask the on-device model to produce.
///
/// `@Generable` (Foundation Models, iOS/macOS 26) tells the model to emit this
/// exact structure via guided generation — no fragile string parsing. Each
/// `@Guide` description steers a field. We also make it `Codable` so we can
/// persist the result on the note.
@Generable
struct MeetingSummary: Codable, Equatable {
    @Guide(description: "A one or two sentence overview of what the meeting was about.")
    var overview: String

    @Guide(description: "Concrete decisions that were made. Empty if none.")
    var decisions: [String]

    @Guide(description: "Action items — short imperative tasks, with an owner if one was mentioned. Empty if none.")
    var actionItems: [String]

    @Guide(description: "Open questions or unresolved topics needing follow-up. Empty if none.")
    var openQuestions: [String]
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

    func summarize(notes: String, transcript: String) async -> MeetingSummary? {
        if let message = availabilityMessage() {
            state = .unavailable(message)
            return nil
        }

        state = .working
        // Instructions are passed as a string literal so they convert to the
        // framework's `Instructions` type (which is ExpressibleByStringLiteral).
        let session = LanguageModelSession(instructions: """
        You are a meeting-notes assistant. From a user's sparse notes and a full \
        transcript, produce a clean, faithful summary. Only include information \
        supported by the inputs — never invent facts. Be concise. If a section \
        has nothing, return an empty list.
        """)
        do {
            let response = try await session.respond(
                to: Self.prompt(notes: notes, transcript: transcript),
                generating: MeetingSummary.self
            )
            state = .idle
            return response.content
        } catch {
            state = .unavailable(error.localizedDescription)
            return nil
        }
    }

    private static func prompt(notes: String, transcript: String) -> String {
        """
        USER NOTES:
        \(notes.isEmpty ? "(none)" : notes)

        TRANSCRIPT:
        \(transcript.isEmpty ? "(none)" : transcript)

        Summarize this meeting.
        """
    }
}
