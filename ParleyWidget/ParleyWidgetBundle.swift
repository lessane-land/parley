import WidgetKit
import SwiftUI

/// The widget extension's entry point. We only ship the recording Live Activity.
@main
struct ParleyWidgetBundle: WidgetBundle {
    var body: some Widget {
        RecordingLiveActivity()
    }
}
