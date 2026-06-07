import WidgetKit
import SwiftUI

/// The widget extension's entry point. If Xcode generated a sample widget when you
/// created the target, you can replace its bundle with this one (we only ship the
/// recording Live Activity).
@main
struct ParleyWidgetBundle: WidgetBundle {
    var body: some Widget {
        RecordingLiveActivity()
    }
}
