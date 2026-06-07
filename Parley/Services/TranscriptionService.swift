import Foundation
@preconcurrency import AVFoundation
import Speech
import SwiftData
#if os(macOS)
@preconcurrency import ScreenCaptureKit   // system-audio capture (the meeting's far side)
#endif
#if canImport(FluidAudio)
import FluidAudio   // on-device speaker diarization (Core ML / ANE). Add via SPM.
#endif

/// On-device live transcription, kept behind one small service (per the project's
/// "each capability behind its own manager" convention).
///
/// Pipeline (all on-device, nothing leaves the machine):
///   AVAudioEngine input tap → (format convert) → SpeechAnalyzer + SpeechTranscriber
///   → async stream of results → `finalizedText` / `volatileText`.
///
/// `@MainActor @Observable` so the UI can read `state`, `finalizedText`, and
/// `volatileText` and update live. The audio tap runs on a background thread and
/// only touches the (thread-safe) stream continuation + a local converter.
///
/// NOTE: `SpeechAnalyzer`/`SpeechTranscriber` are iOS/macOS 26 APIs (WWDC 2025).
/// The exact spelling of a few calls (`supportedLocales`, `installedLocales`,
/// `AssetInventory.assetInstallationRequest`, `bestAvailableAudioFormat`,
/// `finalizeAndFinishThroughEndOfInput`) may need small adjustment against the
/// installed SDK — they're isolated here so that's a one-file fix.
@MainActor
@Observable
final class TranscriptionService {
    enum State: Equatable {
        case idle
        case preparing
        case downloadingModel
        case recording
        case finishing
        case identifyingSpeakers   // running diarization after a recording
        case denied
        case unavailable(String)
    }

    private(set) var state: State = .idle
    /// Confirmed text (won't change).
    private(set) var finalizedText: String = ""
    /// The same confirmed text as timestamped segments (one per finalized line),
    /// mirrored by the owner into `note.transcriptData`. Additive — `finalizedText`
    /// stays the flat source of truth.
    private(set) var finalizedSegments: [TranscriptSegment] = []

    /// Per-speaker voice embeddings from the last diarization, keyed by the speaker
    /// label ("Speaker 1"). The owner persists these on the note and uses them to
    /// recognize / enroll voices across meetings. Empty until `identifySpeakers()`
    /// runs (and only populated when FluidAudio is linked).
    private(set) var speakerEmbeddings: [String: [Float]] = [:]
    /// The in-flight guess for what's being said right now (updates rapidly).
    private(set) var volatileText: String = ""
    /// When the current session began (for the timer).
    private(set) var startedAt: Date?

    /// The locale transcription actually resolved to for this session (Automatic
    /// picks one; this is what it landed on). Surfaced so the UI can show which
    /// language it's listening for — on-device transcription is single-language.
    private(set) var activeLocale: Locale?

    /// A compact label for `activeLocale`, e.g. "EN-US" / "ES-ES", or nil before
    /// the first session.
    var activeLanguageLabel: String? {
        activeLocale.map { $0.identifier(.bcp47).uppercased() }
    }

    var isRecording: Bool { state == .recording }

    // Audio + Speech objects
    private let engine = AVAudioEngine()
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?

    // Diarization: the session audio is recorded to a temp file and, on stop,
    // diarized offline to assign speakers. Kept around `stop()` so the post-stop
    // `identifySpeakers()` can use it. Harmless when FluidAudio isn't linked.
    private var diarAudioURL: URL?
    private var diarSessionStart: Date?

    #if os(macOS)
    /// Captures the Mac's system audio (the meeting's far side) alongside the mic.
    private var systemAudio: SystemAudioCapture?
    #endif
    // The diarizer's Core ML models are cached inside `DiarizationEngine` (a
    // background actor), so the heavy work never runs on the main thread.

    // MARK: Start / stop

    /// Begin a session, seeding with any transcript already on the note so we
    /// append rather than overwrite. `preferredLanguage` is a language code
    /// ("es") to force, or `nil` for Automatic.
    func start(seed: String, seedSegments: [TranscriptSegment] = [], preferredLanguage: String? = nil,
               captureSystemAudio: Bool = false) async {
        guard state == .idle || isError else { return }
        finalizedText = seed
        finalizedSegments = seedSegments
        speakerEmbeddings = [:]
        volatileText = ""
        state = .preparing

        guard await ensureMicrophonePermission() else { state = .denied; return }

        do {
            // Speech models are keyed by language *and* region (en-US, es-ES, …).
            // The device locale may be a combination with no model (e.g. en-ES =
            // English in Spain), so resolve to a supported locale that matches the
            // language rather than demanding an exact region match.
            // `supportedLocales` is empty on the Simulator (no on-device speech
            // models). Use it to pick a good region when present; otherwise fall
            // back to a best guess and still try — on a real device the model
            // downloads; on the Simulator `start`/install throws a clearer error.
            let supported = await SpeechTranscriber.supportedLocales
            let locale = Self.resolveLocale(from: supported, preferred: preferredLanguage)
                ?? Self.fallbackLocale(preferred: preferredLanguage)
            activeLocale = locale

            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults],
                attributeOptions: [.audioTimeRange]
            )
            self.transcriber = transcriber

            // Make sure the on-device model for this locale is installed.
            let modelInstalled = await isModelInstalled(locale)
            if !modelInstalled {
                state = .downloadingModel
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    try await request.downloadAndInstall()
                }
            }

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            self.analyzer = analyzer

            let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])

            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            self.continuation = continuation

            // Consume results. This Task inherits @MainActor, so updating state is safe.
            resultsTask = Task { [weak self] in
                guard let self, let transcriber = self.transcriber else { return }
                do {
                    for try await result in transcriber.results {
                        let piece = String(result.text.characters)
                        if result.isFinal {
                            self.appendFinalized(piece)
                            self.volatileText = ""
                        } else {
                            self.volatileText = piece
                        }
                    }
                } catch {
                    self.state = .unavailable(error.localizedDescription)
                }
            }

            try await analyzer.start(inputSequence: stream)
            try startEngine(convertingTo: analyzerFormat)

            #if os(macOS)
            // Add the Mac's system audio (the other participants) to the same
            // analyzer stream. Best-effort: if Screen Recording permission is
            // denied or capture fails, the mic transcript still works.
            if captureSystemAudio {
                await startSystemAudio(convertingTo: analyzerFormat)
            }
            #endif

            startedAt = Date()
            diarSessionStart = startedAt
            state = .recording
        } catch {
            state = .unavailable(error.localizedDescription)
            await teardown()
        }
    }

    /// Stop recording, flush the last partial result, and leave `finalizedText`
    /// holding the complete transcript.
    func stop() async {
        guard state == .recording || state == .finishing else { return }
        state = .finishing

        #if os(macOS)
        await systemAudio?.stop()
        systemAudio = nil
        #endif

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()

        do { try await analyzer?.finalizeAndFinishThroughEndOfInput() } catch { /* best effort */ }
        resultsTask?.cancel()

        if !volatileText.isEmpty {
            appendFinalized(volatileText)
            volatileText = ""
        }

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif

        await teardown()
        startedAt = nil
        state = .idle
    }

    // MARK: Audio engine

    private func startEngine(convertingTo analyzerFormat: AVAudioFormat?) throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        // This must be the exact combination Apple's SpeechAnalyzer sample uses.
        // `.spokenAudio` is an output-oriented mode, so it's only valid on an
        // output-bearing category — pairing it with the input-only `.record`
        // makes setCategory throw paramErr (OSStatus -50). `.playAndRecord` is
        // the right category for live capture (and what the sample uses).
        // `.allowBluetoothHFP` lets a paired headset/mic be the input source
        // (the modern spelling of the deprecated `.allowBluetooth`).
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.allowBluetoothHFP, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        // A zero-sample-rate / zero-channel format means the input route isn't
        // ready (no mic, or the session didn't activate). Installing a tap with
        // such a format also throws paramErr (-50), so fail with a clear message.
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw NSError(
                domain: "Parley.Transcription", code: -50,
                userInfo: [NSLocalizedDescriptionKey: "No audio input is available. Check the microphone and that it isn't in use by another app."]
            )
        }

        // Captured locally so the background tap never touches main-actor state.
        let continuation = self.continuation
        let converter = BufferConverter()

        // Record the session audio to a temp file for offline diarization. Only
        // when FluidAudio is linked (otherwise there's nothing to diarize).
        #if canImport(FluidAudio)
        let diarFile = makeDiarFile(format: inputFormat)
        #endif

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            #if canImport(FluidAudio)
            try? diarFile?.write(from: buffer)
            #endif
            guard let continuation else { return }
            if let analyzerFormat {
                if let converted = try? converter.convert(buffer, to: analyzerFormat) {
                    continuation.yield(AnalyzerInput(buffer: converted))
                }
            } else {
                continuation.yield(AnalyzerInput(buffer: buffer))
            }
        }

        engine.prepare()
        try engine.start()
    }

    #if os(macOS)
    /// Start capturing system audio and feed it into the same analyzer stream as
    /// the mic. Both sources convert to `analyzerFormat` before yielding. (We feed
    /// two sources into one stream rather than mixing in the engine; in a meeting
    /// only one side usually talks at a time, so the transcript stays coherent and
    /// diarization separates the speakers afterward.)
    private func startSystemAudio(convertingTo analyzerFormat: AVAudioFormat?) async {
        let continuation = self.continuation
        let converter = BufferConverter()
        let capture = SystemAudioCapture { buffer in
            guard let continuation else { return }
            if let analyzerFormat, let converted = try? converter.convert(buffer, to: analyzerFormat) {
                continuation.yield(AnalyzerInput(buffer: converted))
            } else {
                continuation.yield(AnalyzerInput(buffer: buffer))
            }
        }
        do {
            try await capture.start()
            systemAudio = capture
        } catch {
            print("Parley.systemAudio › capture unavailable (mic still recording): \(error)")
        }
    }
    #endif

    // MARK: Helpers

    private var isError: Bool {
        if case .unavailable = state { return true }
        return state == .denied
    }

    private func appendFinalized(_ piece: String) {
        let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        finalizedText += finalizedText.isEmpty ? trimmed : " " + trimmed
        // Mirror as a timestamped segment. The time is when the line *finalized*
        // (a second or two after it was spoken) — robust and dependency-free,
        // versus the WWDC audio-time API.
        finalizedSegments.append(TranscriptSegment(text: trimmed, at: Date()))
    }

    private func teardown() async {
        continuation = nil
        analyzer = nil
        transcriber = nil
        resultsTask = nil
    }

    // MARK: Speaker diarization (FluidAudio, on-device)

    /// Run after `stop()`. Diarizes the recorded session audio, labels each
    /// transcript segment with "Speaker N" by time overlap, and captures a voice
    /// embedding per speaker (into `speakerEmbeddings`) so the owner can recognize
    /// and enroll voices across meetings. Best-effort: on any failure (or when
    /// FluidAudio isn't linked) it leaves segments as-is, so manual labeling still
    /// works. Never overwrites a custom (renamed) speaker.
    ///
    /// NOTE: the FluidAudio calls below (`DiarizerManager`, `performCompleteDiarization`,
    /// `TimedSpeakerSegment.speakerId/startTimeSeconds/endTimeSeconds`,
    /// `speakerManager.getSpeaker(for:)?.currentEmbedding`) follow FluidAudio's
    /// documented API; if the installed package differs, this one method is the
    /// only place to adjust.
    func identifySpeakers(knownVoices: [KnownVoice] = []) async {
        #if canImport(FluidAudio)
        guard let url = diarAudioURL, let sessionStart = diarSessionStart else { return }
        defer { cleanupDiarAudio() }
        guard !finalizedSegments.isEmpty else { return }

        state = .identifyingSpeakers
        do {
            // All the heavy Core ML work happens on the background DiarizationEngine
            // actor, so the UI stays responsive (and can show "Processing…").
            let output = try await DiarizationEngine.shared.diarize(url: url, knownVoices: knownVoices)
            guard !output.turns.isEmpty else { state = .idle; return }

            let turns = output.turns.map { Turn(id: $0.id, start: $0.start, end: $0.end) }
            let knownNames = Set(knownVoices.map(\.name))
            let labelForId = applySpeakers(turns: turns, sessionStart: sessionStart, knownNames: knownNames)

            // Re-key the per-speaker embeddings by display label.
            var embeddings: [String: [Float]] = [:]
            for (id, vector) in output.embeddingsById {
                if let label = labelForId[id] { embeddings[label] = vector }
            }
            speakerEmbeddings = embeddings

            print("Parley.speakers › known=\(Array(knownNames)) detectedIDs=\(Array(Set(turns.map(\.id)))) labels=\(labelForId) embeddingDims=\(speakerEmbeddings.mapValues(\.count))")
        } catch {
            print("Parley.speakers › diarization failed: \(error)")
        }
        state = .idle
        #endif
    }

    #if canImport(FluidAudio)
    private struct Turn { let id: String; let start: Double; let end: Double }

    private func makeDiarFile(format: AVAudioFormat) -> AVAudioFile? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("parley-diar-\(UUID().uuidString).caf")
        guard let file = try? AVAudioFile(forWriting: url, settings: format.settings) else { return nil }
        diarAudioURL = url
        return file
    }

    private func cleanupDiarAudio() {
        if let url = diarAudioURL { try? FileManager.default.removeItem(at: url) }
        diarAudioURL = nil
        diarSessionStart = nil
    }

    /// Assign "Speaker N" to each segment by which speaker dominates the audio
    /// window in which that line was spoken. Returns the speakerId → display-label
    /// map so embeddings can be keyed by the same label. Each finalized line's
    /// window is approximated as [previous finalize, this finalize] relative to the
    /// session start — no dependency on the WWDC audio-time API.
    @discardableResult
    private func applySpeakers(turns: [Turn], sessionStart: Date, knownNames: Set<String> = []) -> [String: String] {
        guard !turns.isEmpty else { return [:] }

        // A recognized voice comes back with its enrolled name as the id — use it
        // directly. Unknown voices get sequential "Speaker N" labels.
        var order: [String] = []
        for turn in turns where !order.contains(turn.id) { order.append(turn.id) }
        var labelForId: [String: String] = [:]
        var unknownCount = 0
        for id in order {
            if knownNames.contains(id) {
                labelForId[id] = id
            } else {
                unknownCount += 1
                labelForId[id] = "Speaker \(unknownCount)"
            }
        }

        var previousOffset = 0.0
        for index in finalizedSegments.indices {
            guard let at = finalizedSegments[index].at else { continue }
            let offset = max(previousOffset, at.timeIntervalSince(sessionStart))
            defer { previousOffset = offset }

            var overlapById: [String: Double] = [:]
            for turn in turns {
                let overlap = min(offset, turn.end) - max(previousOffset, turn.start)
                if overlap > 0 { overlapById[turn.id, default: 0] += overlap }
            }
            guard let id = overlapById.max(by: { $0.value < $1.value })?.key,
                  let label = labelForId[id] else { continue }

            // Don't clobber a name the user typed; only (re)set the auto labels.
            let current = finalizedSegments[index].speaker
            if current == nil || Self.isAutoSpeakerLabel(current!) {
                finalizedSegments[index].speaker = label
            }
        }
        return labelForId
    }

    #endif

    /// True for the auto-generated "Speaker 3" form (so we never overwrite a name
    /// the user typed). Available regardless of FluidAudio so the UI can use it.
    static func isAutoSpeakerLabel(_ name: String) -> Bool {
        name.range(of: #"^Speaker \d+$"#, options: .regularExpression) != nil
    }

    /// Pick a supported locale for transcription.
    ///
    /// - An explicit `preferred` language code wins (matched by language).
    /// - Otherwise "Automatic": walk the device's preferred languages *in order*
    ///   and take the first that has a model — exact region match, else same
    ///   language. (So `es` in your language list beats an `en-ES` region quirk.)
    /// - Then fall back to `en-US`, then anything supported.
    static func resolveLocale(from supported: [Locale], preferred: String?) -> Locale? {
        func match(language code: String) -> Locale? {
            supported.first { $0.language.languageCode?.identifier == code }
        }

        if let preferred, !preferred.isEmpty, let forced = match(language: preferred) {
            return forced
        }

        for identifier in Locale.preferredLanguages {
            let locale = Locale(identifier: identifier)
            if let exact = supported.first(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) {
                return exact
            }
            if let code = locale.language.languageCode?.identifier, let sameLanguage = match(language: code) {
                return sameLanguage
            }
        }

        return supported.first(where: { $0.identifier(.bcp47) == "en-US" }) ?? supported.first
    }

    /// A reasonable default region for a language when the supported list is
    /// unavailable (e.g. Simulator), so we can still attempt a real-device run.
    static func fallbackLocale(preferred: String?) -> Locale {
        let language = preferred
            ?? Locale.current.language.languageCode?.identifier
            ?? "en"
        let defaults = [
            "en": "en-US", "es": "es-ES", "fr": "fr-FR", "de": "de-DE",
            "it": "it-IT", "pt": "pt-BR", "nl": "nl-NL",
            "zh": "zh-CN", "ja": "ja-JP", "ko": "ko-KR"
        ]
        return Locale(identifier: defaults[language] ?? "en-US")
    }
}

/// An enrolled voice handed to diarization so FluidAudio can recognize it and
/// return the enrolled name as the speaker id.
struct KnownVoice: Sendable {
    let name: String
    let embedding: [Float]
}

#if canImport(FluidAudio)
/// One diarized speaker turn (a time span attributed to a speaker id).
struct DiarTurn: Sendable { let id: String; let start: Double; let end: Double }

/// Runs diarization off the main thread. `TranscriptionService` is `@MainActor`,
/// so doing the Core ML work there froze the UI; this dedicated actor keeps the
/// heavy resample + inference on a background executor and caches the models so
/// they load once. Inputs/outputs are all `Sendable`.
actor DiarizationEngine {
    static let shared = DiarizationEngine()
    private var manager: DiarizerManager?

    func diarize(url: URL, knownVoices: [KnownVoice]) async throws -> (turns: [DiarTurn], embeddingsById: [String: [Float]]) {
        let manager = try await self.makeManager()

        // Seed enrolled voices so a recognized speaker comes back as its name.
        if !knownVoices.isEmpty {
            let speakers = knownVoices.map { Speaker(id: $0.name, name: $0.name, currentEmbedding: $0.embedding) }
            manager.speakerManager.initializeKnownSpeakers(speakers)
        }

        let samples = try AudioConverter().resampleAudioFile(url)
        guard !samples.isEmpty else { return ([], [:]) }

        let result = try manager.performCompleteDiarization(samples)
        let turns = result.segments.map {
            DiarTurn(id: $0.speakerId, start: Double($0.startTimeSeconds), end: Double($0.endTimeSeconds))
        }
        var embeddingsById: [String: [Float]] = [:]
        for id in Set(turns.map(\.id)) {
            if let vector = manager.speakerManager.getSpeaker(for: id)?.currentEmbedding, !vector.isEmpty {
                embeddingsById[id] = vector
            }
        }
        return (turns, embeddingsById)
    }

    private func makeManager() async throws -> DiarizerManager {
        if let manager { return manager }
        let models = try await DiarizerModels.downloadIfNeeded()
        let created = DiarizerManager()
        created.initialize(models: models)
        manager = created
        return created
    }
}
#endif

/// Voice-embedding math for cross-meeting speaker recognition. Embeddings are
/// L2-normalized 256-d vectors, so cosine similarity (≈ dot product) in [-1, 1]
/// measures how alike two voices are; ~0.6+ is a confident same-speaker match.
enum SpeakerMatch {
    /// Cosine similarity between two equal-length embeddings (0 if mismatched).
    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in a.indices { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        let denom = na.squareRoot() * nb.squareRoot()
        return denom > 0 ? dot / denom : 0
    }

    /// A running mean of two embeddings (so re-enrolling a voice refines it), then
    /// L2-normalized to keep cosine comparisons meaningful.
    static func averaged(_ existing: [Float], count: Int, with new: [Float]) -> [Float] {
        guard !existing.isEmpty, existing.count == new.count else { return normalized(new) }
        let n = Float(max(count, 1))
        let mean = zip(existing, new).map { ($0 * n + $1) / (n + 1) }
        return normalized(mean)
    }

    static func normalized(_ v: [Float]) -> [Float] {
        let norm = v.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return norm > 0 ? v.map { $0 / norm } : v
    }

    /// A sample-count-weighted mean of two embeddings (for merging two profiles of
    /// the same voice), L2-normalized.
    static func weightedMean(_ a: [Float], _ wa: Int, _ b: [Float], _ wb: Int) -> [Float] {
        guard !a.isEmpty else { return normalized(b) }
        guard !b.isEmpty, a.count == b.count else { return normalized(a) }
        let fa = Float(max(wa, 1)), fb = Float(max(wb, 1))
        let total = fa + fb
        return normalized(zip(a, b).map { ($0 * fa + $1 * fb) / total })
    }
}

extension SpeakerProfile {
    /// Fold profiles that share a name (case-insensitively) into a single one —
    /// merging their embeddings (weighted by sample count) and deleting the extras.
    /// This cleans up the duplicate records cross-device enrollment can create in
    /// CloudKit (e.g. "Me" enrolled on both the Mac and the iPad before they synced).
    @MainActor
    static func dedupe(_ profiles: [SpeakerProfile], in context: ModelContext) {
        let key: (SpeakerProfile) -> String = {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        let groups = Dictionary(grouping: profiles.filter { !key($0).isEmpty }, by: key)
        for (_, group) in groups where group.count > 1 {
            // Keep the most-refined (most samples); merge the rest into it.
            let ordered = group.sorted { $0.sampleCount > $1.sampleCount }
            let keeper = ordered[0]
            for duplicate in ordered.dropFirst() {
                keeper.embedding = SpeakerMatch.weightedMean(
                    keeper.embedding, keeper.sampleCount, duplicate.embedding, duplicate.sampleCount)
                keeper.sampleCount += duplicate.sampleCount
                keeper.updatedAt = max(keeper.updatedAt, duplicate.updatedAt)
                context.delete(duplicate)
            }
        }
    }
}

/// The languages offered in the Settings transcription picker (subset of common
/// ones; resolution still checks them against what the device actually supports).
enum TranscriptionLanguages {
    static let options: [(code: String, name: String)] = [
        ("en", "English"), ("es", "Spanish"), ("fr", "French"), ("de", "German"),
        ("it", "Italian"), ("pt", "Portuguese"), ("nl", "Dutch"),
        ("zh", "Chinese"), ("ja", "Japanese"), ("ko", "Korean")
    ]
}

private extension TranscriptionService {

    private func isModelInstalled(_ locale: Locale) async -> Bool {
        let installed = await SpeechTranscriber.installedLocales
        let target = locale.identifier(.bcp47)
        return installed.contains { $0.identifier(.bcp47) == target }
    }

    private func ensureMicrophonePermission() async -> Bool {
        #if os(iOS)
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default: return await AVAudioApplication.requestRecordPermission()
        }
        #else
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
        #endif
    }
}

#if os(macOS)
/// Captures the Mac's **system audio** (what you hear from the meeting app) using
/// ScreenCaptureKit and delivers it as PCM buffers. Paired with the mic, this lets
/// the transcript include the *other* participants — the core of a Mac meeting
/// companion.
///
/// Requires the user's **Screen Recording** permission (prompted on first use). A
/// tiny video stream is technically required by ScreenCaptureKit even for
/// audio-only; it's configured minimally and ignored.
final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private let onBuffer: (AVAudioPCMBuffer) -> Void
    private let queue = DispatchQueue(label: "parley.systemaudio")

    init(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) {
        self.onBuffer = onBuffer
    }

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else {
            throw NSError(domain: "Parley.SystemAudio", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No display available for audio capture."])
        }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true   // don't capture our own output (no feedback)
        config.sampleRate = 48_000
        config.channelCount = 2
        // A video stream is required even for audio-only capture; keep it minimal.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 6)

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid,
              let pcm = Self.pcmBuffer(from: sampleBuffer) else { return }
        onBuffer(pcm)
    }

    /// Convert a CoreMedia audio sample buffer into an `AVAudioPCMBuffer`.
    private static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription),
              let format = AVAudioFormat(streamDescription: asbd) else { return nil }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList)
        return status == noErr ? buffer : nil
    }
}
#endif

/// Converts an audio buffer from the engine's input format to the format the
/// analyzer wants. Reused across taps; rebuilt only when a format changes.
final class BufferConverter {
    private var converter: AVAudioConverter?

    func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format
        if inputFormat == format { return buffer }

        if converter == nil || converter?.inputFormat != inputFormat || converter?.outputFormat != format {
            converter = AVAudioConverter(from: inputFormat, to: format)
        }
        guard let converter else {
            throw NSError(domain: "Parley.BufferConverter", code: 1)
        }

        let ratio = format.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw NSError(domain: "Parley.BufferConverter", code: 2)
        }

        var consumed = false
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        if let conversionError { throw conversionError }
        return output
    }
}
