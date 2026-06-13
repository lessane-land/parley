// `canImport(ActivityKit)` is true on macOS (the module exists) even though the
// types are unavailable there — so it must be combined with `os(iOS)`, matching
// the guards in TranscriptionService.
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation

/// Live Activity model for an in-progress recording — shown on the Lock Screen
/// and in the Dynamic Island while Inkling records in the background.
///
/// IMPORTANT: this file must belong to BOTH targets — the app (which starts/ends
/// the activity) and the widget extension (which draws it). In Xcode, select this
/// file and tick both targets under File Inspector ▸ Target Membership.
struct RecordingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// "Recording" while capturing, "Wrapping up…" during finalization.
        var status: String
    }

    /// Fixed for the life of the activity.
    var noteTitle: String
    var startedAt: Date
}
#endif
