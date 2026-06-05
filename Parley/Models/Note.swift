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

    /// Every stored property gets a default value here. That isn't just
    /// convenience: when we add CloudKit sync in a later phase, CloudKit requires
    /// every SwiftData property to be optional or have a default, so starting this
    /// way avoids a migration headache down the road.
    init(id: UUID = UUID(), title: String = "", body: String = "", createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
    }
}
