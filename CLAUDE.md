# CLAUDE.md — Parley

> Project brief for Claude Code. Read this fully before writing or changing code.
> (`Parley` is a placeholder name — rename freely.)

## What we're building

A **standalone**, **on-device**, **cross-platform** meeting companion app — like Granola,
but private and pen-friendly. It:

- Records a meeting and **transcribes it live, on-device**.
- Lets the user **take their own notes at the same time** — typed on any device,
  **handwritten with Apple Pencil on iPad**.
- After the meeting, merges the sparse user notes + the full transcript into a clean,
  structured summary with action items (the "Granola magic"), **on-device**.
- Pulls the user's **Calendar** to auto-create/title notes from meetings, and pushes
  action items to **Reminders**.
- Syncs notes across **iPhone, iPad, and Mac**.

## Hard requirements

- **One SwiftUI multiplatform codebase** targeting iOS, iPadOS, and macOS. No per-platform forks
  unless a feature genuinely only exists on one platform (e.g. PencilKit canvas → iPad/iPhone).
- **Minimum deployment: iOS 26 / iPadOS 26 / macOS 26.** The transcription and on-device AI
  depend on APIs introduced at WWDC 2025.
- **Privacy first: everything runs on-device. No third-party cloud, ever.** This is a
  non-negotiable design constraint (the user attends confidential work meetings).

## Tech stack (all first-party Apple frameworks)

| Concern              | Framework / API                              | Notes |
|----------------------|----------------------------------------------|-------|
| UI                   | **SwiftUI** (multiplatform)                  | NavigationSplitView for the note list/detail. |
| Persistence          | **SwiftData**                                | Local first. |
| Cross-device sync    | **CloudKit** (private database via SwiftData)| **Deferred** — needs paid Apple Developer Program. Add when enrolled. |
| Live transcription   | **SpeechAnalyzer + SpeechTranscriber** (Speech) | On-device, tuned for long-form conversational speech. iOS/macOS 26+. |
| Audio capture        | **AVFoundation** (AVAudioEngine)             | Feed buffers into the analyzer. |
| Handwriting          | **PencilKit** (PKCanvasView)                 | iPad/iPhone only; gracefully absent on Mac. |
| Calendar & Reminders | **EventKit**                                 | Read calendar events; write action items as reminders. |
| AI summary           | **Foundation Models** (on-device LLM)        | iOS/macOS 26+. Used only for note+transcript summarization. |

Good open-source reference for the Speech + Foundation Models combo: `FluidInference/swift-scribe`
(MIT). Study it; don't copy wholesale.

## Architecture conventions

- **MVVM.** Views are dumb; `@Observable` view models hold state and orchestration.
- SwiftData `@Model` types are the source of truth for persisted data.
- Keep transcription, audio, calendar, and AI each behind its own small manager/service type
  so they can be built and tested in isolation (matches the phased plan below).
- Async/await everywhere; no completion-handler spaghetti.
- Use SF Symbols (vector) for iconography. **Never emojis in the UI.**

## Developer profile (calibrate your explanations to this)

The developer is a **senior software engineer** (≈10 yrs Java) and an experienced **Product Owner**,
but **brand new to Swift, SwiftUI, and the Apple toolchain**. So:

- Assume strong general engineering instincts; do **not** over-explain programming basics.
- **Do** explain Swift/SwiftUI-specific idioms the first time they appear — value vs reference types,
  `@State`/`@Binding`/`@Observable`, optionals, `async`/`await`, property wrappers, SwiftData macros.
- The developer **directs**; you implement. Prefer small, reviewable steps with a one-line
  "why" before each chunk. When something is a SwiftUI gotcha, say so.

## Phased roadmap — build in order, one phase per session

> **CURRENT PHASE: 0.** Do not start a later phase until the current one is reviewed and approved.

- **Phase 0 — Walking skeleton.** Multiplatform app. SwiftData `Note` model
  (`id`, `title`, `body`, `createdAt`). NavigationSplitView: list of notes + detail editor.
  Add/delete. **Local SwiftData only** (CloudKit deferred). Runs on iPhone, iPad, Mac.
- **Phase 1 — The pen.** Add a PencilKit canvas to the note detail on iPad. Persist the drawing
  alongside the text. Mac/iPhone gracefully fall back to typed notes.
- **Phase 2 — The ears.** Add SpeechTranscriber + AVAudioEngine. Record button → live transcript
  streams into the note next to the user's own notes. Handle mic + speech permissions.
- **Phase 3 — The calendar brain.** EventKit: list today's meetings; tapping one creates a note
  pre-filled with title/time/attendees. Action items detected in a note → written to Reminders.
- **Phase 4 — The Granola magic.** Foundation Models: take the user's notes + full transcript and
  produce a structured summary (decisions, action items, open questions) on-device.

Each phase must be independently runnable and useful. No big-bang.

## Things to ask before assuming

- If a step needs the paid Developer Program (CloudKit, device push), flag it rather than failing silently.
- If an API behaves differently than expected on the installed OS version, surface it early.
