import Foundation
import FoundationModels

/// The stored + displayed summary (Codable; persisted on `note.summaryData`).
/// Action items carry user state (done) on top of the generated content.
struct MeetingSummary: Codable, Equatable {
    var overview: String
    var decisions: [Decision]
    var actionItems: [ActionItem]
    var openQuestions: [String]
    var keyQuotes: [KeyQuote]

    init(overview: String, decisions: [Decision], actionItems: [ActionItem],
         openQuestions: [String], keyQuotes: [KeyQuote] = []) {
        self.overview = overview
        self.decisions = decisions
        self.actionItems = actionItems
        self.openQuestions = openQuestions
        self.keyQuotes = keyQuotes
    }

    /// Lenient decoder so summaries cached before a field existed (e.g. `keyQuotes`)
    /// still load — missing keys fall back to empty rather than failing the decode.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        overview = try c.decodeIfPresent(String.self, forKey: .overview) ?? ""
        decisions = try c.decodeIfPresent([Decision].self, forKey: .decisions) ?? []
        actionItems = try c.decodeIfPresent([ActionItem].self, forKey: .actionItems) ?? []
        openQuestions = try c.decodeIfPresent([String].self, forKey: .openQuestions) ?? []
        keyQuotes = try c.decodeIfPresent([KeyQuote].self, forKey: .keyQuotes) ?? []
    }
}

extension MeetingSummary {
    /// A flat, plain-text rendering of the whole wrap-up — used to index it for
    /// search so the clean version is findable later.
    var plainText: String {
        var parts: [String] = [overview]
        parts += decisions.map { [$0.text, $0.rationale].joined(separator: " ") }
        parts += actionItems.map { [$0.title, $0.owner].joined(separator: " ") }
        parts += openQuestions
        parts += keyQuotes.map { [$0.text, $0.speaker].joined(separator: " ") }
        return parts.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: "\n")
    }
}

/// One action item: the generated task + owner + due, plus the user's checkbox.
/// `due` is the model's free-text hint ("Thu"); `dueDate` is a real date the user
/// sets by hand, which is what gets written to Reminders. Both optional, so old
/// cached summaries (which lacked `dueDate`) still decode — the synthesized
/// decoder back-fills nil.
struct ActionItem: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var owner: String = ""     // empty == no owner mentioned
    var due: String?           // short due like "Thu" / "This wk", or nil
    var dueDate: Date?         // a real, user-set due date (→ Reminders), or nil
    var done: Bool = false
}

/// A notable line pulled from the transcript (Settings ▸ AI ▸ "Key quotes").
struct KeyQuote: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var text: String
    var speaker: String = ""
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
    @Guide(description: "A few short, notable verbatim quotes from the transcript. Empty if none.")
    var keyQuotes: [KeyQuoteDraft]
}

@Generable
private struct ActionDraft {
    @Guide(description: "The task as a short imperative phrase.")
    var title: String
    @Guide(description: "The person responsible, or empty if none was mentioned.")
    var owner: String
    @Guide(description: "A short due hint like \"Thu\" or \"This week\", or empty if none.")
    var due: String
}

@Generable
private struct KeyQuoteDraft {
    @Guide(description: "A short, notable quote, roughly verbatim.")
    var text: String
    @Guide(description: "Who said it, or empty if unclear.")
    var speaker: String
}

@Generable
private struct DecisionDraft {
    @Guide(description: "The decision that was made, as a short statement.")
    var text: String
    @Guide(description: "A brief reason for the decision, or empty if none was given.")
    var rationale: String
}

/// Runs the wrap-up entirely on-device: merge the user's sparse notes
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
                   isMeeting: Bool = true,
                   tone: SummaryTone = .balanced,
                   includeDecisions: Bool = true,
                   includeActionItems: Bool = true,
                   includeOpenQuestions: Bool = true,
                   includeKeyQuotes: Bool = false) async -> MeetingSummary? {
        if let message = availabilityMessage() {
            state = .unavailable(message)
            return nil
        }

        state = .working
        // Adapt the role: a multi-speaker recording is a meeting; otherwise it's
        // just the user's own notes (no attendees / decisions to attribute).
        let role = isMeeting
            ? "You are a meeting-notes assistant. From the user's notes and the transcript, produce a clean, faithful summary capturing the meeting's decisions, action items, and open questions."
            : "You are a notes assistant. These are the user's personal notes — NOT a meeting. Produce a clean, faithful summary and pull out any to-dos as action items. There are no attendees or speakers to attribute; leave decisions and open questions empty unless the notes clearly contain them."
        let session = LanguageModelSession(instructions: """
        \(role) Only include information supported by the inputs — never invent \
        facts, people, or tasks. \(tone.guidance) If a section has nothing, return \
        an empty list.
        """)
        do {
            let draft = try await session.respond(
                to: Self.prompt(notes: notes, transcript: transcript, attendees: attendees, isMeeting: isMeeting),
                generating: SummaryDraft.self
            ).content
            state = .idle
            // Honor the "Always extract" toggles regardless of what the model
            // returned, so a turned-off section is reliably empty.
            return MeetingSummary(
                overview: draft.overview,
                decisions: includeDecisions ? draft.decisions.map { Decision(text: $0.text, rationale: $0.rationale) } : [],
                actionItems: includeActionItems ? draft.actions.map {
                    ActionItem(title: $0.title, owner: $0.owner, due: $0.due.isEmpty ? nil : $0.due)
                } : [],
                openQuestions: includeOpenQuestions ? draft.openQuestions : [],
                keyQuotes: includeKeyQuotes ? draft.keyQuotes.map { KeyQuote(text: $0.text, speaker: $0.speaker) } : []
            )
        } catch {
            state = .unavailable(error.localizedDescription)
            return nil
        }
    }

    private static func prompt(notes: String, transcript: String, attendees: [String], isMeeting: Bool) -> String {
        let closing = isMeeting
            ? "Summarize this meeting. When assigning action-item owners, prefer names from the attendee list."
            : "Summarize these notes. Action items are the user's own to-dos — leave the owner empty."
        return """
        \(isMeeting ? "ATTENDEES:\n\(attendees.isEmpty ? "(unknown)" : attendees.joined(separator: ", "))\n\n" : "")USER NOTES:
        \(notes.isEmpty ? "(none)" : notes)

        TRANSCRIPT:
        \(transcript.isEmpty ? "(none)" : transcript)

        \(closing)
        """
    }
}

// MARK: - Translation (on-device)

/// Translates a transcript into another language entirely on-device (Foundation
/// Models), so a Spanish recording can be read in English (or vice-versa) without
/// anything leaving the machine. Long transcripts are translated in chunks so they
/// stay within the model's context window, then rejoined.
@MainActor
@Observable
final class TranslationService {
    enum State: Equatable { case idle, working, unavailable(String) }

    private(set) var state: State = .idle

    func availabilityMessage() -> String? {
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(.deviceNotEligible): return "This device doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in Settings to translate."
        case .unavailable(.modelNotReady): return "The on-device model is still downloading. Try again shortly."
        case .unavailable(let other): return "Translation is unavailable (\(other))."
        }
    }

    /// Translate `text` into the language named by `targetName` ("English",
    /// "Spanish", …). Returns nil on failure (the caller keeps the original).
    func translate(_ text: String, into targetName: String) async -> String? {
        if let message = availabilityMessage() { state = .unavailable(message); return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        state = .working
        let instructions = """
        You are a professional translator. Translate the user's text into \(targetName). \
        Preserve the meaning, tone, names, and numbers. Keep line breaks. Output ONLY the \
        translation — no preamble, no notes, no quotation marks around it.
        """
        var out: [String] = []
        for chunk in Self.chunk(trimmed) {
            // A fresh session per chunk keeps each translation independent and well
            // within the context window (vs. one growing multi-turn session).
            let session = LanguageModelSession(instructions: instructions)
            do {
                let piece = try await session.respond(to: chunk).content
                out.append(piece.trimmingCharacters(in: .whitespacesAndNewlines))
            } catch {
                state = .unavailable(error.localizedDescription)
                return nil
            }
        }
        state = .idle
        return out.joined(separator: "\n")
    }

    /// Split text into context-window-friendly chunks on paragraph/sentence
    /// boundaries (~1200 chars each) so long transcripts translate reliably.
    static func chunk(_ text: String, maxChars: Int = 1200) -> [String] {
        let paragraphs = text.components(separatedBy: "\n")
        var chunks: [String] = []
        var current = ""
        func flush() {
            let t = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { chunks.append(t) }
            current = ""
        }
        for para in paragraphs {
            if para.count > maxChars {
                // A single very long line: break on sentence enders.
                flush()
                var sentence = ""
                for word in para.split(separator: " ", omittingEmptySubsequences: false) {
                    if sentence.count + word.count + 1 > maxChars { chunks.append(sentence.trimmingCharacters(in: .whitespaces)); sentence = "" }
                    sentence += word
                    sentence += " "
                }
                let t = sentence.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { chunks.append(t) }
            } else if current.count + para.count + 1 > maxChars {
                flush()
                current = para + "\n"
            } else {
                current += para + "\n"
            }
        }
        flush()
        return chunks.isEmpty ? [text] : chunks
    }
}

// MARK: - Ask Inkling (on-device chat across your notes)

/// One line in the Ask Inkling conversation.
struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    var text: String
    var sources: [String] = []
}

/// The model's structured answer: the reply plus which note titles it leaned on
/// (so the UI can show citation chips honestly — from notes actually in context).
@Generable
private struct AskAnswer {
    @Guide(description: "A concise answer, grounded ONLY in the provided notes.")
    var answer: String
    @Guide(description: "Titles of the notes you actually used. Empty if none applied.")
    var sources: [String]
}

/// "Ask Inkling" — a multi-turn, on-device assistant that answers questions about
/// the user's notes. The notes corpus is folded into the session instructions
/// once; each question reuses the session so follow-ups keep context. Nothing
/// leaves the device (Foundation Models).
@MainActor
@Observable
final class AskService {
    enum State: Equatable { case idle, thinking, unavailable(String) }

    private(set) var state: State = .idle
    private(set) var messages: [ChatMessage] = []
    private var session: LanguageModelSession?

    var isReady: Bool { availabilityMessage() == nil }

    func availabilityMessage() -> String? {
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(.deviceNotEligible): return "This device doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in Settings to use Ask Parley."
        case .unavailable(.modelNotReady): return "The on-device model is still downloading. Try again shortly."
        case .unavailable(let other): return "Ask Inkling is unavailable (\(other))."
        }
    }

    /// (Re)ground the assistant in the current notes. Call when the chat opens.
    func start(context: String) {
        session = LanguageModelSession(instructions: """
        You are Inkling's on-device assistant. Answer the user's questions using ONLY \
        the notes below — their meeting notes, transcripts, and summaries. If the \
        answer isn't supported by the notes, say so plainly instead of guessing. Be \
        concise and conversational. In `sources`, list the titles of the notes you used.

        NOTES:
        \(context.isEmpty ? "(no notes yet)" : context)
        """)
        if let message = availabilityMessage() { state = .unavailable(message) }
    }

    func ask(_ question: String) async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, state != .thinking else { return }
        if let message = availabilityMessage() { state = .unavailable(message); return }

        guard let session else { state = .unavailable("Ask Inkling isn't ready yet."); return }
        messages.append(ChatMessage(role: .user, text: q))
        state = .thinking
        do {
            let reply = try await session.respond(to: q, generating: AskAnswer.self).content
            messages.append(ChatMessage(role: .assistant, text: reply.answer, sources: reply.sources))
            state = .idle
        } catch {
            // The on-device safety guardrail can false-positive on short/ambiguous
            // prompts — soften that instead of showing the raw "unsafe" text.
            let desc = error.localizedDescription.lowercased()
            let friendly = (desc.contains("unsafe") || desc.contains("guardrail") || desc.contains("safety"))
                ? "I couldn't answer that one — try rephrasing, or ask with a bit more detail."
                : "Sorry — I couldn't answer that right now."
            messages.append(ChatMessage(role: .assistant, text: friendly))
            state = .idle
        }
    }
}
