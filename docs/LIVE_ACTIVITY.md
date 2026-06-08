# Recording Live Activity (Lock Screen + Dynamic Island)

This is **fully wired** — app side and widget extension. No manual Xcode setup needed.

## What's in the project
- `Parley/RecordingActivity.swift` — the shared `RecordingActivityAttributes`
  (member of **both** the app and the `ParleyWidgetExtension` target).
- `TranscriptionService` starts the activity on record, ends it on stop (iOS).
- `INFOPLIST_KEY_NSSupportsLiveActivities = YES` on the app target.
- **`ParleyWidgetExtension`** target (in `project.pbxproj`) builds the widget from
  `ParleyWidget/`:
  - `ParleyWidgetBundle.swift` — `@main` widget bundle.
  - `RecordingLiveActivity.swift` — Lock Screen + Dynamic Island UI.
  - `Info.plist` — `NSExtensionPointIdentifier = com.apple.widgetkit-extension`.
  - `Assets.xcassets` — `AccentColor`, `WidgetBackground`.

The extension is **iOS/iPadOS only** (`SUPPORTED_PLATFORMS = iphoneos iphonesimulator`);
Live Activities don't exist on macOS, so the Mac app simply builds without it.

## To run it
1. Open `Parley.xcodeproj`, select the **Parley** app scheme + a **real device**.
2. Build & run. Start a recording, then lock the phone / switch apps.
3. The recording appears on the Lock Screen and in the Dynamic Island with a live
   timer, and ends automatically when you stop.

## Notes
- Live Activities need a physical device (Simulator is unreliable) and the user must
  have Live Activities enabled (Settings ▸ Parley).
- If signing complains about the widget, confirm the bundle id
  `com.lessane.Parley.ParleyWidget` under the `ParleyWidgetExtension` target ▸
  Signing & Capabilities, with your team selected (automatic signing).
