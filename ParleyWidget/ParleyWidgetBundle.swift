import WidgetKit
import SwiftUI

/// The widget extension's entry point. We only ship the recording Live Activity,
/// which is iOS-only (ActivityKit). The `#else` placeholder keeps the
/// `WidgetBundle` valid if the extension is ever compiled for another platform —
/// the extension is configured iOS-only, so the placeholder never actually ships.
@main
struct ParleyWidgetBundle: WidgetBundle {
    var body: some Widget {
        #if os(iOS)
        RecordingLiveActivity()
        #else
        PlaceholderWidget()
        #endif
    }
}

#if !os(iOS)
struct PlaceholderWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "parley.placeholder", provider: PlaceholderProvider()) { _ in
            EmptyView()
        }
    }
}

private struct PlaceholderEntry: TimelineEntry { let date = Date() }

private struct PlaceholderProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlaceholderEntry { PlaceholderEntry() }
    func getSnapshot(in context: Context, completion: @escaping (PlaceholderEntry) -> Void) {
        completion(PlaceholderEntry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PlaceholderEntry>) -> Void) {
        completion(Timeline(entries: [PlaceholderEntry()], policy: .never))
    }
}
#endif
