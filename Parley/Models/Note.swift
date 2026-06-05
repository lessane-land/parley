import Foundation
import SwiftData

/// The single source of truth for a persisted note.
///
/// `@Model` is a SwiftData macro. At compile time it rewrites this plain class
/// into a persistent type: it generates the storage, change tracking, and the
/// schema SwiftData uses to create the underlying database. You never write SQL
/// or a `Codable` mapping — the macro does it. A `@Model` type must be a `class`
/// (reference type), because SwiftData tracks one shared instance per row; a
/// `struct` (value type) would be copied and couldn't be observed for edits.
@Model
final class Note {
    /// Our own stable identifier (required by the Phase 0 spec). This is separate
    /// from SwiftData's internal `persistentModelID`; having an explicit `UUID`
    /// is handy later for syncing and for referencing a note across devices.
    ///
    /// NOTE: these declaration-level defaults are **required for CloudKit**.
    /// `NSPersistentCloudKitContainer` insists every attribute be optional or have
    /// a default *on the property itself* — an `init` default doesn't count. Without
    /// them the CloudKit store fails to open and silently runs local-only (no sync).
    var id: UUID = UUID()

    var title: String = ""
    var body: String = ""
    var createdAt: Date = Date()

    /// The live, on-device transcript captured while recording. Kept separate
    /// from `body` (the user's own notes) so we can merge them into a summary
    /// later (Phase 4). Has a default, so adding it is a lightweight migration.
    var transcript: String = ""

    /// If this note was created from a calendar event, its identifier — so we
    /// reuse the same note instead of duplicating it when the meeting is tapped
    /// again. Optional → lightweight migration.
    var calendarEventID: String?

    /// Meeting metadata, promoted out of the note `body` into real fields (E4).
    /// `createdAt` records when the *note* was made; these record when the
    /// *meeting* runs and who's in it. All optional/defaulted → CloudKit-safe and
    /// a lightweight migration. `attendees` is a `[String]` of display names;
    /// SwiftData archives it as an attribute (not a relationship), so an empty
    /// default is fine.
    var startDate: Date?
    var endDate: Date?
    var attendees: [String] = []

    /// Pinned to the top of the dashboard (and shown in an accent style).
    var pinned: Bool = false

    /// The last on-device AI summary (a `MeetingSummary` encoded as JSON).
    /// Optional → lightweight migration.
    var summaryData: Data?

    /// Structured transcript — `[TranscriptSegment]` encoded as JSON — carrying a
    /// per-line timestamp and an optional (manually-assigned) speaker. This is an
    /// *additive* mirror of `transcript` (the flat text stays the source of truth
    /// for search + the summary); the timeline UI prefers these when present.
    /// Optional Data → lightweight migration and CloudKit-safe.
    var transcriptData: Data?

    /// Tags attached to this note. Optional to-many (CloudKit requirement); the
    /// inverse is declared on `Tag.notes`.
    var tags: [Tag]?

    /// Handwriting layer (iPad). A `PKDrawing` serialized via its
    /// `dataRepresentation()`. Optional because most notes have no drawing, and
    /// because adding an *optional* property is a SwiftData **lightweight
    /// migration** — existing notes upgrade automatically with no data loss.
    /// We store raw `Data` rather than importing PencilKit here so the model
    /// stays platform-neutral (PencilKit doesn't exist on macOS).
    @Attribute(.externalStorage) var drawing: Data?

    /// Every stored property gets a default value here. That isn't just
    /// convenience: when we add CloudKit sync in a later phase, CloudKit requires
    /// every SwiftData property to be optional or have a default, so starting this
    /// way avoids a migration headache down the road.
    init(id: UUID = UUID(), title: String = "", body: String = "", createdAt: Date = .now, drawing: Data? = nil, transcript: String = "", calendarEventID: String? = nil, startDate: Date? = nil, endDate: Date? = nil, attendees: [String] = [], pinned: Bool = false, summaryData: Data? = nil, transcriptData: Data? = nil) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.drawing = drawing
        self.transcript = transcript
        self.calendarEventID = calendarEventID
        self.startDate = startDate
        self.endDate = endDate
        self.attendees = attendees
        self.pinned = pinned
        self.summaryData = summaryData
        self.transcriptData = transcriptData
    }

    /// Decoded transcript segments (empty if none stored). Convenience around the
    /// JSON in `transcriptData`.
    var transcriptSegments: [TranscriptSegment] {
        get {
            guard let transcriptData else { return [] }
            return (try? JSONDecoder().decode([TranscriptSegment].self, from: transcriptData)) ?? []
        }
        set {
            transcriptData = newValue.isEmpty ? nil : (try? JSONEncoder().encode(newValue))
        }
    }
}

/// One finalized line of transcript: the text, the wall-clock moment it was
/// confirmed, and an optional speaker label the user assigns by hand (on-device
/// diarization isn't offered, so speakers are manual). `Codable` so it persists
/// inside `Note.transcriptData`; `Identifiable`/`Equatable` for SwiftUI lists.
struct TranscriptSegment: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var text: String
    var at: Date?
    var speaker: String?
    /// User flagged this line as an action item.
    var flagged: Bool = false

    init(id: UUID = UUID(), text: String, at: Date? = nil, speaker: String? = nil, flagged: Bool = false) {
        self.id = id
        self.text = text
        self.at = at
        self.speaker = speaker
        self.flagged = flagged
    }

    /// Lenient decode so segments stored before a field existed (e.g. `flagged`)
    /// still load — missing keys fall back rather than failing the decode.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        at = try c.decodeIfPresent(Date.self, forKey: .at)
        speaker = try c.decodeIfPresent(String.self, forKey: .speaker)
        flagged = try c.decodeIfPresent(Bool.self, forKey: .flagged) ?? false
    }
}
