#if os(iOS)
import ActivityKit
import WidgetKit
import SwiftUI

/// The Lock Screen + Dynamic Island UI for an in-progress recording.
/// Uses `RecordingActivityAttributes` (in `Parley/RecordingActivity.swift`), which
/// is a member of both the app and this widget extension target.
struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            // Lock Screen / notification banner.
            HStack(spacing: 12) {
                recDot
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.noteTitle)
                        .font(.headline).lineLimit(1)
                    Text(context.state.status)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(context.attributes.startedAt, style: .timer)
                    .font(.system(.title3, design: .rounded).monospacedDigit())
                    .frame(width: 72, alignment: .trailing)
            }
            .padding(14)
            .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label { Text(context.attributes.noteTitle).lineLimit(1) } icon: { recDot }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.startedAt, style: .timer)
                        .monospacedDigit().frame(width: 60, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.status).font(.caption).foregroundStyle(.secondary)
                }
            } compactLeading: {
                recDot
            } compactTrailing: {
                Text(context.attributes.startedAt, style: .timer)
                    .monospacedDigit().frame(width: 46, alignment: .trailing)
            } minimal: {
                recDot
            }
            .keylineTint(.red)
        }
    }

    private var recDot: some View {
        Circle().fill(.red).frame(width: 10, height: 10)
    }
}
#endif
