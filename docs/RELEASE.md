# Shipping Parley

A practical path from "it builds" to "it's on the App Store." Do it in order:
**harden → TestFlight → App Store.** There is no one-tap publish for a store app.

## Done in the repo
- [x] Usage strings (mic, camera, calendar, reminders, speech) — `INFOPLIST_KEY_*`.
- [x] Background audio mode (`UIBackgroundModes = audio remote-notification`).
- [x] App icons (iOS 1024 + macOS set), launch screen (generated).
- [x] iCloud / CloudKit entitlement + container `iCloud.com.lessane.Parley`.
- [x] **Privacy manifest** (`Parley/PrivacyInfo.xcprivacy`) — no tracking, no data
      collection, UserDefaults required-reason declared.

## You must do (needs your Mac + Apple Developer account)

### 1. Harden (a few days of real-device testing)
Test the **unhappy paths** on iPhone, iPad, and Mac:
- [ ] Permissions **denied**: mic, camera, calendar, reminders → app stays usable, clear messaging.
- [ ] **No iCloud account** / signed out → local-only, no crash (SyncMonitor shows it).
- [ ] **Apple Intelligence unavailable / model still downloading** → wrap-up + Ask + prep degrade gracefully.
- [ ] Empty states, very long notes/transcripts, rotation, background/lock while recording.
- [ ] Each mood; light/dark; Dynamic Type sizes.

### 2. CloudKit production schema
- [ ] In the **CloudKit Console**, deploy the **Development schema to Production**.
      (App Store builds use Production — sync silently fails otherwise.)

### 3. App Store Connect
- [ ] Create the app record (bundle id, name "Parley" or final name).
- [ ] **Privacy policy URL** (required) + support URL.
- [ ] Privacy "nutrition label": *Data Not Collected* (everything is on-device /
      user's private iCloud) — matches the manifest.
- [ ] Screenshots per device class (6.7"/6.1" iPhone, 13" iPad, Mac), description,
      keywords, category, age rating.

### 4. TestFlight first
- [ ] Archive (Product ▸ Archive) for iOS and macOS, upload to App Store Connect.
- [ ] Internal testing, then a handful of external testers. Fix what real use surfaces.

### 5. Submit for review
- [ ] Submit from App Store Connect. In review notes, explain: on-device AI
      (Apple Intelligence), background audio = meeting recording, requires iOS/macOS 26.

## Known constraints
- **Minimum iOS 26 / macOS 26** — the on-device transcription + Foundation Models
  APIs require it, so the initial audience is small until adoption grows.
- Rich-text drag-selection in the transcript is Mac-only (SwiftUI limitation);
  iOS uses long-press → Copy.
