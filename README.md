# Parley

A **standalone, on-device, cross-platform** meeting companion — like Granola, but
private and pen-friendly. It records a meeting, transcribes it live on-device,
lets you take your own notes at the same time (typed anywhere, handwritten with
Apple Pencil on iPad), then merges your sparse notes + the full transcript into a
clean structured summary — all without anything leaving your devices.

> **Privacy first.** Everything runs on-device via Apple frameworks. No
> third-party cloud, ever. The only network egress is your own **private**
> iCloud database for cross-device sync.

## Requirements

- **Xcode 26+**, **iOS/iPadOS/macOS 26+** (the transcription and on-device AI use
  WWDC 2025 APIs).
- A device with **Apple Intelligence** for the summary feature, and a **real
  device** for live transcription (the Simulator ships no speech models).
- A **paid Apple Developer Program** membership for CloudKit sync.

## Tech stack (all first-party Apple frameworks)

| Concern            | Framework                                   |
|--------------------|---------------------------------------------|
| UI                 | SwiftUI (one multiplatform target)          |
| Persistence        | SwiftData                                    |
| Cross-device sync   | CloudKit (private DB via SwiftData)         |
| Live transcription | SpeechAnalyzer + SpeechTranscriber (Speech) |
| Audio capture      | AVFoundation (AVAudioEngine)                |
| Handwriting        | PencilKit (iPad)                            |
| Calendar/Reminders | EventKit                                    |
| On-device summary  | Foundation Models                           |

## Architecture

**MVVM-ish, with each capability behind its own small service.** Views are thin;
SwiftData `@Model` is the source of truth; `@Observable` services hold
orchestration and are injected through the SwiftUI environment.

```
Parley/
├─ ParleyApp.swift            App entry: builds the (CloudKit) ModelContainer,
│                             registers fonts, injects the shared services.
├─ Models/
│  └─ Note.swift              @Model: id, title, body, createdAt, drawing,
│                             transcript, transcriptData (timestamped segments),
│                             calendarEventID, startDate, endDate, attendees,
│                             summaryData. CloudKit-ready (all optional/defaulted).
├─ Services/
│  ├─ TranscriptionService    AVAudioEngine → SpeechAnalyzer/Transcriber.
│  ├─ EventKitService         Today's meetings (read) + Reminders (write).
│  ├─ SummaryService          Foundation Models structured summary.
│  └─ SyncMonitor             CloudKit sync status for the UI.
├─ Theme/                     The "mood" design system (see below).
│  ├─ Mood.swift              4 moods + per-mood config (accents, faces…).
│  ├─ Theme.swift             Resolved design tokens + font builders.
│  ├─ ThemeManager.swift      @Observable persisted preferences + derivation.
│  ├─ Density.swift, Color+Hex.swift, ThemeShadowModifier.swift, AppFonts.swift
├─ Views/
│  ├─ NoteListView            Sidebar of note cards + sync chip + toolbar.
│  ├─ NoteDetailView          Adaptive notes-|-transcript split; pen on iPad.
│  ├─ TranscriptPanel, DrawingCanvas, SettingsView,
│  ├─ TodayMeetingsSheet, ActionItemsSheet, SummaryView
└─ Fonts/                     Bundled OFL typefaces (registered at launch).
```

### The mood system

Four "moods" (**Paper**, **Terminal**, **Swiss**, **Neubrutalist**) re-skin the
whole app — color, type, geometry — from the design's token set. `ThemeManager`
resolves a base mood plus user overrides (accent, highlight, paper warmth, type
face, density) into a `Theme` of concrete tokens; views read those instead of
hard-coding anything. Adjustable in **Settings** (sliders icon, or ⌘, on Mac).

Fonts are real bundled typefaces (Newsreader, Space Grotesk, Archivo, IBM Plex
Mono, Hanken Grotesk — all SIL OFL), instanced to the exact weights used and
registered at launch via CoreText.

## Features by phase

- **0 — Notes.** SwiftData notes; list + editor; add/delete.
- **1 — Pen.** PencilKit canvas on iPad, persisted alongside text.
- **2 — Ears.** Live on-device transcription; language is auto (preferred
  languages) or chosen in Settings.
- **3 — Calendar brain.** Today's meetings → pre-filled notes; detected action
  items → Reminders.
- **4 — Granola magic.** Foundation Models merge notes + transcript into a
  structured summary (overview, decisions, action items, open questions).
- **Sync.** CloudKit private-database sync across iPhone/iPad/Mac.

## Setup

1. Open `Parley.xcodeproj` in Xcode 26.
2. Select the **Parley** target → **Signing & Capabilities** → set your **Team**.
   Confirm the bundle id is `com.lessane.Parley` (the CloudKit container
   `iCloud.com.lessane.Parley` must match it).
3. Capabilities expected (entitlements are checked in): **iCloud → CloudKit**
   (container `iCloud.com.lessane.Parley`), **Background Modes → Remote
   notifications**, **Push Notifications**. With automatic signing, Xcode
   registers these on first build.
4. Run on **My Mac** or a real iPhone/iPad. (Speech + Foundation Models + CloudKit
   don't work in the Simulator.)

## Testing notes

- **Transcription / Summary:** real device with Apple Intelligence enabled; the
  on-device model downloads on first use.
- **CloudKit:** sign two devices into the same Apple ID; a note made on one
  appears on the other. First run auto-creates the schema in the CloudKit
  **Development** environment. For App Store, switch `aps-environment` to
  `production` and promote the schema in the CloudKit Console.

## Known caveats / TODO

- The new Speech / Foundation Models APIs are isolated in their services; a call
  signature may need adjusting against the shipping SDK.
- Action-item detection without a summary is a simple heuristic
  (`ActionItemDetector`); the summary path uses the model.
- Paper/Swiss face pickers await bundling Fraunces / Source Serif 4 / Spectral /
  Inter.
- See `docs/DESIGN_EVOLUTION.md` for the plan to grow into the full design.
