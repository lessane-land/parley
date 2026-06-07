# Recording Live Activity (Lock Screen + Dynamic Island)

The app code is done — it starts/ends the activity when recording starts/stops.
You just need to add the **widget extension target** once.

## What's already wired (in the app)
- `Parley/RecordingActivity.swift` — the shared `RecordingActivityAttributes`.
- `TranscriptionService` starts the activity on record, ends it on stop (iOS).
- `INFOPLIST_KEY_NSSupportsLiveActivities = YES` is set on the app target.
- Widget UI is written in `ParleyWidget/` (not yet in any target — step 3 below).

## One-time setup in Xcode

1. **File ▸ New ▸ Target… ▸ Widget Extension.**
   - Product Name: **ParleyWidget**
   - **Check "Include Live Activity."** (Configuration App Intent optional.)
   - Click Finish, and **Activate** the scheme if prompted.

2. **Delete** the sample files Xcode generated inside the new `ParleyWidget` group
   (e.g. `ParleyWidget.swift`, the sample bundle) — keep `Assets.xcassets` and the
   `Info.plist`.

3. **Add the provided UI files** to the **ParleyWidget** target:
   - `ParleyWidget/RecordingLiveActivity.swift`
   - `ParleyWidget/ParleyWidgetBundle.swift`
   (Drag them into the ParleyWidget group; tick the ParleyWidget target.)

4. **Share the attributes file with the extension:** select
   `Parley/RecordingActivity.swift` → File Inspector → **Target Membership** →
   also tick **ParleyWidget**. (It must be in *both* the app and the extension.)

5. Make sure the **ParleyWidget** extension's Info.plist has
   `NSExtensionPointIdentifier = com.apple.widgetkit-extension` (the template sets
   this) and the deployment target is iOS 26 to match the app.

6. Build the **Parley** app scheme (it embeds the extension) and run on a **real
   device** — start a recording, lock the phone / switch apps: the recording
   appears on the Lock Screen and in the Dynamic Island with a live timer.

## Notes
- Live Activities need a physical device (Simulator support is unreliable) and the
  user must have Live Activities enabled (Settings ▸ Parley).
- The activity ends automatically when recording stops.
