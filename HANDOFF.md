# HANDOFF — continuing Parley in a new session

Read this first, then `README.md` (architecture/setup) and
`docs/DESIGN_EVOLUTION.md` (the design roadmap). This file is the live status +
how-to-continue note.

## TL;DR

Parley is a private, on-device, multiplatform (iOS/iPadOS/macOS 26) meeting
companion. **All five phases + CloudKit sync are implemented, plus large parts
of the design evolution (E1/E2/E3/E5).** The code has **not been compiled by the
assistant that wrote it** (it ran on Linux with no Xcode), so the #1 pending task
is **building + testing on a real Mac/iPad and fixing whatever the compiler/
device surfaces** — especially the brand-new WWDC-2025 APIs.

- Branch: **`claude/optimistic-brown-fSPcZ`** (do all work here; push here).
- 23 Swift files, 19 bundled fonts. Bundle id `com.lessane.Parley`,
  CloudKit container `iCloud.com.lessane.Parley`.

## Working agreement / environment notes

- **Develop on `claude/optimistic-brown-fSPcZ`.** Commit + push there.
- On your personal Mac you DO have Xcode — so **build early and often**; that's
  the main thing the previous (Linux) sessions couldn't do.
- The project file (`Parley.xcodeproj/project.pbxproj`) is a **conventional,
  explicit** pbxproj (objectVersion 56). When you add Swift files **in Xcode**,
  it updates the project for you — easy. (Earlier sessions hand-edited the
  pbxproj; you won't need to.)
- If a future remote/Linux session edits files, **close Xcode before
  `git pull`** so it doesn't fight over `project.pbxproj`.
- Fonts auto-register at launch (`AppFonts.registerAll()` scans the bundle), so
  adding a `.ttf` to the `Fonts` group is all that's needed.

## What's built (by area)

- **Models** (`Models/`): `Note` (id, title, body, createdAt, drawing,
  transcript, transcriptData, calendarEventID, startDate, endDate, attendees,
  summaryData, tags), `TranscriptSegment` (text/at/speaker, JSON in
  `transcriptData`), and `Tag` (name, colorHex, notes). All CloudKit-safe: every
  property optional/defaulted, no unique constraints, relationships optional.
- **Theme system** (`Theme/`): four moods (Paper/Terminal/Swiss/Neubrutalist)
  resolved into design tokens; per-mood accent/highlight/warmth/face overrides;
  density; mood grids + paper grain; bundled OFL fonts. Driven by
  `ThemeManager` (persisted), surfaced in `SettingsView`.
- **Services** (`Services/`):
  - `TranscriptionService` — AVAudioEngine → SpeechAnalyzer/SpeechTranscriber,
    permissions, model download, locale resolution.
  - `EventKitService` — today's meetings (read) + action items → Reminders
    (write); `ActionItemDetector` heuristic.
  - `SummaryService` — Foundation Models guided generation → `MeetingSummary`
    (overview/decisions/action items+owners/open questions).
  - `SyncMonitor` — CloudKit sync status for the sidebar chip.
- **Views** (`Views/`): home is a `NavigationStack` with a rail + notes grid
  (`NoteListView` + `NotesGridView`); tapping a note pushes `NoteDetailView`
  full-screen (top-bar record cluster, orientation-aware notes⟷transcript split,
  unified Pencil-over-text canvas, transcript timeline, bottom Summarize bar).
  Plus `SettingsView`, `TodayMeetingsSheet`, `ActionItemsSheet`, `SummaryView`,
  `DrawingCanvas`, `TranscriptPanel`.

## ⚠️ Highest-risk areas to verify on device (do these first)

These use new iOS/macOS 26 APIs the assistant could not compile. Each is isolated
to one file so fixes are local. If the compiler errors, the call shapes are the
suspects:

1. **`Services/SummaryService.swift`** — Foundation Models. Check
   `SystemLanguageModel.default.availability` reason cases, `@Generable` (incl.
   the nested `ActionDraft`), and `session.respond(to:generating:)` (it may want
   a `Prompt(...)` wrapper rather than a raw `String`).
2. **`Services/TranscriptionService.swift`** — Speech. Check
   `SpeechTranscriber.supportedLocales` / `installedLocales`,
   `AssetInventory.assetInstallationRequest(supporting:)`,
   `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)`,
   `finalizeAndFinishThroughEndOfInput()`. **Needs a real device** (Simulator
   ships no speech models → falls back to a best-guess locale and will error).
3. **`Views/DrawingCanvas.swift` + `NoteDetailView` unified canvas** — the
   Type/Draw overlay (allowsHitTesting + `isActive` tool-picker/first-responder
   toggle). Test Pencil draw vs keyboard type swapping on a real iPad.
4. **CloudKit** — needs the iCloud/CloudKit capability + container provisioned on
   your paid team (see README "Setup"); test sync across two devices on the same
   Apple ID. Foundation Models + Speech also need a real, Apple-Intelligence-
   capable device. **Fixed:** `Note`'s `id/title/body/createdAt` lacked
   declaration-level defaults, so the CloudKit store failed to open and silently
   ran local-only — they now default on the property (CloudKit requires every
   attribute optional-or-defaulted). `SyncMonitor` now also reports the iCloud
   account status + the container-open failure reason on the sync chip, so a
   misconfig reads as a concrete message instead of a quiet "On this device".

## Device test checklist

- [ ] Builds clean (0 errors/warnings) on macOS 26 / Xcode 26.
- [ ] Runs on **My Mac**, **iPad** (sim ok for UI), and a **real device** for
      Speech/AI/CloudKit.
- [ ] Phase 1: Pencil canvas draws on iPad; Type/Draw toggle routes input
      correctly; Clear works; strokes persist.
- [ ] Phase 2: Record → permission prompt → model download → live transcript;
      language follows Settings / preferred languages.
- [ ] Phase 3: Today's meetings → pre-filled note; action items → Reminders.
- [ ] Phase 4: Summarize → structured summary; checkboxes persist; per-item +
      "send all" to Reminders.
- [ ] Sync: a note made on device A appears on device B; chip shows Syncing/Synced.
- [ ] Moods: switch all four; accent/highlight/warmth/face pickers; grids + grain.
- [ ] Nav: open note = full-screen; Back = dashboard (no stray sidebar toggle).

## Pending work (roughly prioritized)

1. **Compile + device-test pass** (above). Most important.
2. **E4 done** — meeting metadata (start/end date, attendees) promoted to real
   `Note` fields (rendered as a meta line in the detail header; attendees feed the
   summary prompt). `Decision` is now a structured type (text + optional
   rationale, with legacy `[String]` decoding) alongside `ActionItem`.
3. **Summary screen done** — promoted from a bottom-bar sheet to a first-class
   *pushed* screen (`navigationDestination(isPresented:)`) with a real back button.
4. **Transcript speakers done** — transcript is now stored as `TranscriptSegment`s
   (`Note.transcriptData`, mirrored from the flat `transcript`) carrying a
   wall-clock timestamp per line; the timeline shows the time + speaker, and a
   node menu assigns a **free-text** speaker name (quick-pick of names already used
   in the note, "New name…", or Clear). On-device diarization isn't offered, so
   speakers stay manual.
5. **iPhone compact** layout fine-tuning (rail hidden; filters in toolbar — works,
   but could be nicer).
6. **Tests** — add a unit-test target (do this in Xcode) for: locale resolution
   (`TranscriptionService.resolveLocale`), `ActionItemDetector.detect`,
   `MeetingSummary` Codable round-trip, `PK` color mixing.
7. **Release readiness** — set `aps-environment` to `production` and promote the
   CloudKit schema in the CloudKit Console before TestFlight/App Store.
8. **Accessibility** — broaden VoiceOver labels / Dynamic Type audit.

## How to continue in a new Claude Code session

Tell the new session:
- "Work on branch `claude/optimistic-brown-fSPcZ`. Read `HANDOFF.md`, `README.md`,
  and `docs/DESIGN_EVOLUTION.md` first."
- Then either: "Build it and fix any compiler errors" (best first step now that
  you have Xcode), or pick a pending item above.
- Project conventions: SwiftUI multiplatform, MVVM with `@Observable` services
  injected via environment, SwiftData `@Model` as source of truth, everything
  on-device, mood tokens for all styling (never hard-code colors/fonts), SF
  Symbols (no emoji), iOS/macOS 26 minimum.
