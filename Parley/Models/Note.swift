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
    /// Rich (formatted) version of `body` as RTF, when the user has applied bold /
    /// italic / headers / bullets. `body` stays the plain-text mirror (search, the
    /// wrap-up, action-item detection all read it). Optional + external storage →
    /// CloudKit-safe and a lightweight migration; nil = plain note.
    @Attribute(.externalStorage) var bodyRich: Data?
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

    /// Freeform-board layout: where this card sits and how big it is on the
    /// dashboard when the user arranges it themselves. All optional (CloudKit-safe
    /// lightweight migration); nil = not yet placed, so it's auto-laid-out. Stored
    /// on the note so the arrangement **syncs** across devices.
    var boardX: Double?
    var boardY: Double?
    var boardW: Double?
    var boardH: Double?

    /// The last on-device AI summary (a `MeetingSummary` encoded as JSON).
    /// Optional → lightweight migration.
    var summaryData: Data?

    /// Plain-text mirror of the wrap-up, kept so search can index the clean
    /// version (overview, decisions, actions, questions). Default "" → CloudKit-safe.
    var summaryText: String = ""

    /// Structured transcript — `[TranscriptSegment]` encoded as JSON — carrying a
    /// per-line timestamp and an optional (manually-assigned) speaker. This is an
    /// *additive* mirror of `transcript` (the flat text stays the source of truth
    /// for search + the summary); the timeline UI prefers these when present.
    /// Optional Data → lightweight migration and CloudKit-safe.
    var transcriptData: Data?

    /// Per-speaker voice embeddings captured during this meeting's diarization,
    /// keyed by the speaker label ("Speaker 1", or an enrolled name). JSON of
    /// `[String: [Float]]`. Kept so a speaker can be named (→ enrolled) any time the
    /// note is open, not just right after recording. Optional Data → CloudKit-safe.
    var speakerEmbeddingsData: Data?

    /// Canvas items placed on the handwriting page (images + shapes), as JSON of
    /// `[CanvasItem]`. The handwriting strokes (`drawing`) sit on top; these are the
    /// "rich content" layer behind them. Optional Data → CloudKit-safe.
    var canvasItemsData: Data?

    /// Tags attached to this note. Optional to-many (CloudKit requirement); the
    /// inverse is declared on `Tag.notes`.
    var tags: [Tag]?

    /// Files and images attached to this note (photos, PDFs, docs). Optional
    /// to-many (CloudKit requirement); `.cascade` so deleting the note removes its
    /// attachments too. The inverse is `Attachment.note`. The bytes themselves live
    /// in external storage (see `Attachment.data`), so notes stay light.
    @Relationship(deleteRule: .cascade, inverse: \Attachment.note)
    var attachments: [Attachment]?

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

    /// Canvas items (images + shapes) on the page. Convenience around the JSON in
    /// `canvasItemsData`.
    var canvasItems: [CanvasItem] {
        get {
            guard let canvasItemsData else { return [] }
            return (try? JSONDecoder().decode([CanvasItem].self, from: canvasItemsData)) ?? []
        }
        set {
            canvasItemsData = newValue.isEmpty ? nil : (try? JSONEncoder().encode(newValue))
        }
    }

    /// This meeting's per-speaker embeddings (label → 256-d voiceprint).
    /// Convenience around the JSON in `speakerEmbeddingsData`.
    var speakerEmbeddings: [String: [Float]] {
        get {
            guard let speakerEmbeddingsData else { return [:] }
            return (try? JSONDecoder().decode([String: [Float]].self, from: speakerEmbeddingsData)) ?? [:]
        }
        set {
            speakerEmbeddingsData = newValue.isEmpty ? nil : (try? JSONEncoder().encode(newValue))
        }
    }
}

/// An enrolled voice: a name plus its averaged voice embedding, so Parley can
/// recognize the same person across meetings ("that's Vanesa again"). The bytes
/// are a 256-d `[Float]` (L2-normalized) from on-device diarization — math, not
/// audio. CloudKit-safe (defaults + optional), so your enrolled voices sync across
/// your own devices and never leave your private iCloud.
@Model
final class SpeakerProfile {
    var id: UUID = UUID()
    var name: String = ""
    /// The averaged embedding, encoded as raw `Float` bytes.
    var embeddingData: Data?
    /// How many samples have been averaged in (for a running mean on re-enroll).
    var sampleCount: Int = 1
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), name: String = "", embedding: [Float] = [], sampleCount: Int = 1) {
        self.id = id
        self.name = name
        self.sampleCount = sampleCount
        self.updatedAt = Date()
        self.embedding = embedding
    }

    /// The embedding as a `[Float]` (computed → not separately persisted).
    var embedding: [Float] {
        get { SpeakerEmbedding.decode(embeddingData) }
        set { embeddingData = SpeakerEmbedding.encode(newValue) }
    }
}

/// Raw `[Float]` ⇄ `Data` for compact, CloudKit-friendly embedding storage.
enum SpeakerEmbedding {
    static func encode(_ vector: [Float]) -> Data? {
        vector.isEmpty ? nil : vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }
    static func decode(_ data: Data?) -> [Float] {
        guard let data, !data.isEmpty else { return [] }
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}

/// A file or image attached to a note (photo, PDF, document…). The raw bytes
/// live in **external storage** so they don't bloat the SQLite row — and so
/// CloudKit ships them as assets later. CloudKit-safe like `Note`: every property
/// is optional or has a declaration-level default, and the relationship back to
/// the note is the optional inverse of `Note.attachments`.
@Model
final class Attachment {
    var id: UUID = UUID()
    var filename: String = ""

    /// Uniform Type Identifier (e.g. "public.jpeg", "com.adobe.pdf"). Drives the
    /// icon and whether we render a thumbnail vs. a generic file tile.
    var typeIdentifier: String = ""
    var createdAt: Date = Date()

    /// The raw bytes. `.externalStorage` keeps large blobs out of the row.
    @Attribute(.externalStorage) var data: Data?

    /// Text recognized from this attachment (a photo/scan of handwritten or printed
    /// notes), via on-device Vision. Cached so the wrap-up can fold it in without
    /// re-running OCR. Optional → lightweight migration + CloudKit-safe.
    var ocrText: String?

    /// The owning note — the inverse of `Note.attachments`.
    var note: Note?

    init(id: UUID = UUID(), filename: String = "", typeIdentifier: String = "", createdAt: Date = .now, data: Data? = nil, ocrText: String? = nil) {
        self.id = id
        self.filename = filename
        self.typeIdentifier = typeIdentifier
        self.createdAt = createdAt
        self.data = data
        self.ocrText = ocrText
    }
}

/// A piece of rich content placed on the handwriting page: an image or a vector
/// shape. Position/size are in the page's point coordinates. `Codable` so it
/// persists inside `Note.canvasItemsData`; image bytes are stored inline
/// (downscaled on insert) so the whole page syncs as one record.
struct CanvasItem: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case image, rectangle, ellipse, line, arrow }

    var id: UUID = UUID()
    var kind: Kind = .rectangle
    var x: Double = 40
    var y: Double = 40
    var width: Double = 180
    var height: Double = 130
    var colorHex: String = "#3E5C50"
    var imageData: Data?

    init(id: UUID = UUID(), kind: Kind = .rectangle, x: Double = 40, y: Double = 40,
         width: Double = 180, height: Double = 130, colorHex: String = "#3E5C50", imageData: Data? = nil) {
        self.id = id
        self.kind = kind
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.colorHex = colorHex
        self.imageData = imageData
    }

    /// Lenient decode so items saved before a field existed still load.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .rectangle
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 40
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 40
        width = try c.decodeIfPresent(Double.self, forKey: .width) ?? 180
        height = try c.decodeIfPresent(Double.self, forKey: .height) ?? 130
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "#3E5C50"
        imageData = try c.decodeIfPresent(Data.self, forKey: .imageData)
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
