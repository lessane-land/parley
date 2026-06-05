import SwiftUI
import SwiftData

/// A label that can be attached to notes (the design's colored tag chips).
///
/// CloudKit-safe like `Note`: defaulted properties and an **optional**
/// relationship (CloudKit requires to-many relationships be optional). The
/// inverse is declared here so SwiftData keeps both sides in sync.
@Model
final class Tag {
    var name: String = ""
    var colorHex: String = "#3E5C50"

    @Relationship(inverse: \Note.tags)
    var notes: [Note]?

    init(name: String = "", colorHex: String = "#3E5C50") {
        self.name = name
        self.colorHex = colorHex
    }

    var color: Color { Color(hex: colorHex) }

    /// A rotating palette so new tags get distinct colors without a picker.
    static let palette = [
        "#3E5C50", "#C75B39", "#2B4BF2", "#E2231A",
        "#8B3A2F", "#16A34A", "#7A5AE0", "#0A5FFF"
    ]
}
