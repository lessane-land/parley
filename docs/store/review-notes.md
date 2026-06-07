# App Review notes — Parley

Paste into App Store Connect ▸ App Review Information ▸ Notes.

---

Parley is a private, on‑device meeting‑notes app for iPhone, iPad, and Mac.
Everything runs locally; there is no account or login required to review it.

PLATFORM REQUIREMENT
- Requires iOS/iPadOS/macOS 26. The live transcription (SpeechAnalyzer) and the
  AI features (Foundation Models / Apple Intelligence) depend on APIs introduced
  in this release.

ON‑DEVICE AI
- Summaries ("Wrap‑up"), meeting prep, and "Ask Parley" use Apple's on‑device
  foundation models. On hardware without Apple Intelligence, these features show
  a clear "unavailable" state and the rest of the app works normally.

BACKGROUND AUDIO
- The "audio" background mode is used solely so a meeting recording/transcription
  keeps running when the app is backgrounded or the device is locked. It is only
  active while the user is recording.

PERMISSIONS (all optional; app remains usable if denied)
- Microphone: record & transcribe meetings.
- Camera/Photos: attach a photo of handwritten notes; text is read on device.
- Calendar: list events and create events from a note.
- Reminders: save action items the user chooses to add.

ICLOUD / SYNC
- Content syncs across the user's own devices via the private CloudKit database.
  iCloud is optional — without it the app runs local‑only. No reviewer iCloud
  setup is required.

PRIVACY
- No data is collected, transmitted, or shared. No analytics, no ads, no
  third‑party SDKs. See the included privacy manifest and "Data Not Collected"
  privacy label.

HOW TO TRY IT QUICKLY
1. Open the app → tap Record meeting (grant mic) → speak a few sentences → stop.
2. Tap "Wrap‑up" to generate the on‑device summary (needs Apple Intelligence).
3. Optional: add a typed note, or attach a photo of handwriting, then re‑run the
   wrap‑up to see it folded in.
