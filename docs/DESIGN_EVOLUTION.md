# Evolving Parley into the full design

The phased build (0–4 + sync) delivered every capability and the mood design
system. This is the plan to grow the **screens** up to the full Parley design
(the `Parley.html` prototype: a polished home/sidebar, a refined live-meeting
screen, and a first-class summary screen).

Legend: **S** ≈ ½–1 day · **M** ≈ 1–3 days · **L** ≈ 3+ days. ⚠️ = research/risk.

**Status:** E1 (home rail + grid; notes open full-screen) ✅ · E2 (top-bar
record + unified Pencil canvas + bottom Summarize bar + transcript timeline) ✅ ·
E3 (structured summary) ✅ · E4 (Tag + ActionItem done; meeting metadata as fields
pending) · E5 (fonts + face pickers + mood grids + paper grain + a11y labels done;
iPhone compact, tests, prod CloudKit pending). **Not yet compiled/device-tested —
see `HANDOFF.md`.**

---

## Where we are vs. the design

| Design element | Today | Gap |
|---|---|---|
| Sidebar (brand, search, nav, tags, Record CTA) | Plain list of note cards | Missing brand, search, nav sections, tags, CTA |
| Note cards (snippet, date, **tags**) | snippet + date | No tags |
| Live meeting top bar (title, meta, **REC pill + stop**) | Record lives in transcript panel | No dedicated top bar / circular stop |
| Notes + handwriting on one canvas | Separate typed box + Pencil box | Not a unified Pencil-over-text surface |
| Transcript with **speakers / timeline** | One flowing paragraph + live line | No speakers, no timeline variant |
| Summary screen (lede, owners, checkboxes, sources) | Sheet with sections | Not first-class; action items are plain strings |
| Paper grain, animations, grids per mood | Colors/shapes/fonts done | Missing texture + motion |

---

## E1 — Home & information architecture  *(highest visible impact)*

Make the sidebar the design's home screen.

- **Brand header** (mark + "Parley" wordmark). **S**
- **Search** — a `searchable` field filtering the `@Query` by title/body/transcript. **S**
- **Nav sections** — All Notes / Recent with counts; selectable. **M**
- **Tags** — new `Tag` `@Model` (name + color) with an optional Note↔Tags
  relationship (CloudKit-safe: optional, no unique). Tag chips on cards + a tag
  filter in the sidebar. **M**
- **Record CTA** — prominent button that creates a note *and* starts recording in
  one tap. **S**

Depends on: a small model addition (Tag). Everything else is view work on the
existing theme tokens.

## E2 — The live meeting screen

Bring the recording experience up to the prototype.

- **Top bar**: editable title, meta line (time · attendees · source), and the
  **REC pill + timer + circular stop** moved here from the panel. **M**
- **Unified note canvas** ⚠️ — overlay a PencilKit canvas on the typed notes with
  `drawingPolicy = .pencilOnly` so you type with the keyboard and draw with the
  Pencil on the *same* surface (finger scrolls). Replaces the separate
  handwriting box. Needs careful hit-testing/layout. **L ⚠️**
- **Transcript polish**: optional **timeline variant** (variant C) with speaker
  initials; keep the live-line highlight + autoscroll we have. **M**
- **Speaker labels** ⚠️ — only if the Speech API exposes diarization on-device;
  otherwise defer. **L ⚠️**
- **Texture & motion**: paper-grain background, and the design's `rise` / `pulse`
  / `breathe` animations. **S–M**

## E3 — The summary screen (full Granola magic)

Promote the summary from a sheet to a first-class, editable screen.

- **Structured action items** — replace `[String]` with an `ActionItem` type
  (text, owner, due date, done, linked reminder id) so we can show checkboxes +
  owners and keep a two-way link with Reminders. **M**
- **Layout**: prominent lede/overview, Decisions, Action items (checkable, with
  owners + per-item "add to Reminders"), Open questions, and **Sources** linking
  back to transcript moments. **M**
- **Streaming generation** — use `LanguageModelSession` streaming so the summary
  types in live. **S ⚠️**
- **Editable** summary + Regenerate (regenerate exists). **S**

## E4 — Data model deepening

Underpins E1–E3.

- `Tag` model + relationship. **S**
- `ActionItem` (and maybe `Decision`) as structured types persisted on the note.
  **M**
- Meeting metadata as real fields (`startDate`, `attendees: [String]`) instead of
  prefilled body text. **S**
- Migration: all additive/optional → SwiftData lightweight migration (and
  CloudKit-safe). **S**

## E5 — Polish, platform & quality

- Bundle remaining faces (**Fraunces, Source Serif 4, Spectral, Inter**) and wire
  the Paper/Swiss face pickers. **S**
- Mood extras: terminal hairline grid, swiss column grid (partly there). **S**
- Accessibility pass (VoiceOver labels; Dynamic Type already via `relativeTo`). **M**
- Permissions priming / onboarding screen. **M**
- macOS refinements (toolbar placement, window sizing, `Settings` polish). **S**
- Tests for services (locale resolution, action-item detection, summary decode). **M**
- For release: `aps-environment = production` + promote CloudKit schema. **S**

---

## Suggested order

1. **E1 Home/sidebar** — biggest visible jump toward the design, low risk.
2. **E4 model bits** as needed by E1/E3 (Tag, ActionItem).
3. **E3 summary screen** — the product's headline payoff.
4. **E2 meeting screen** — top bar first (easy), unified Pencil canvas later (the
   one genuinely hard piece).
5. **E5 polish** — continuous.

Each step stays independently shippable, on the existing MVVM + mood-token
foundation, and CloudKit-safe.
