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
    var id: UUID

    var title: String
    var body: String
    var createdAt: Date

    /// The live, on-device transcript captured while recording. Kept separate
    /// from `body` (the user's own notes) so we can merge them into a summary
    /// later (Phase 4). Has a default, so adding it is a lightweight migration.
    var transcript: String = ""

    /// If this note was created from a calendar event, its identifier — so we
    /// reuse the same note instead of duplicating it when the meeting is tapped
    /// again. Optional → lightweight migration.
    var calendarEventID: String?

    /// The last on-device AI summary (a `MeetingSummary` encoded as JSON).
    /// Optional → lightweight migration.
    var summaryData: Data?

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
    init(id: UUID = UUID(), title: String = "", body: String = "", createdAt: Date = .now, drawing: Data? = nil, transcript: String = "", calendarEventID: String? = nil, summaryData: Data? = nil) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.drawing = drawing
        self.transcript = transcript
        self.calendarEventID = calendarEventID
        self.summaryData = summaryData
    }
}
