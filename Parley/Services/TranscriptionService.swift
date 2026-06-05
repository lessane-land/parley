import Foundation
import AVFoundation
import Speech
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
    #if canImport(FluidAudio)
    private var diarizer: LSEENDDiarizer?   // cached so models load once
    #endif

    // MARK: Start / stop

    /// Begin a session, seeding with any transcript already on the note so we
    /// append rather than overwrite. `preferredLanguage` is a language code
    /// ("es") to force, or `nil` for Automatic.
    func start(seed: String, seedSegments: [TranscriptSegment] = [], preferredLanguage: String? = nil) async {
        guard state == .idle || isError else { return }
        finalizedText = seed
        finalizedSegments = seedSegments
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
        // `.allowBluetooth` lets a paired headset/mic be the input source.
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.allowBluetooth, .defaultToSpeaker])
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

    /// Run after `stop()`. Diarizes the recorded session audio and labels each
    /// transcript segment with "Speaker N" by time overlap. Best-effort: on any
    /// failure (or when FluidAudio isn't linked) it simply leaves segments as-is,
    /// so manual labeling still works. Never overwrites a custom (renamed) speaker.
    func identifySpeakers() async {
        #if canImport(FluidAudio)
        guard let url = diarAudioURL, let sessionStart = diarSessionStart else { return }
        defer { cleanupDiarAudio() }
        guard !finalizedSegments.isEmpty else { return }

        state = .identifyingSpeakers
        do {
            let engine: LSEENDDiarizer
            if let cached = diarizer {
                engine = cached
            } else {
                engine = try await LSEENDDiarizer(variant: .dihard3)
                diarizer = engine
            }
            // processComplete is throwing-but-synchronous and returns the timeline.
            let timeline = try engine.processComplete(audioFileURL: url)
            applySpeakers(turns: Self.turns(from: timeline), sessionStart: sessionStart)
        } catch {
            // Diarization is a bonus; keep the transcript even if it fails.
        }
        state = .idle
        #endif
    }

    #if canImport(FluidAudio)
    private struct Turn { let slot: Int; let start: Double; let end: Double }

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

    /// Flatten the diarization timeline into time-ordered speaker turns.
    /// (`DiarizerSegment.startTime/endTime` are `Float` seconds.)
    private static func turns(from timeline: DiarizerTimeline) -> [Turn] {
        var turns: [Turn] = []
        for (slot, speaker) in timeline.speakers {
            for seg in speaker.finalizedSegments {
                turns.append(Turn(slot: slot, start: Double(seg.startTime), end: Double(seg.endTime)))
            }
        }
        return turns.sorted { $0.start < $1.start }
    }

    /// Assign "Speaker N" to each segment by which speaker dominates the audio
    /// window in which that line was spoken. Each finalized line's window is
    /// approximated as [previous finalize, this finalize] relative to the session
    /// start — no dependency on the WWDC audio-time API.
    private func applySpeakers(turns: [Turn], sessionStart: Date) {
        guard !turns.isEmpty else { return }
        // Stable display numbers: sort distinct slots, number them 1…k.
        let numberForSlot = Dictionary(
            uniqueKeysWithValues: Set(turns.map(\.slot)).sorted().enumerated().map { ($1, $0 + 1) }
        )

        var previousOffset = 0.0
        for index in finalizedSegments.indices {
            guard let at = finalizedSegments[index].at else { continue }
            let offset = max(previousOffset, at.timeIntervalSince(sessionStart))
            defer { previousOffset = offset }

            var overlapBySlot: [Int: Double] = [:]
            for turn in turns {
                let overlap = min(offset, turn.end) - max(previousOffset, turn.start)
                if overlap > 0 { overlapBySlot[turn.slot, default: 0] += overlap }
            }
            guard let slot = overlapBySlot.max(by: { $0.value < $1.value })?.key,
                  let number = numberForSlot[slot] else { continue }

            // Don't clobber a name the user typed; only (re)set the auto labels.
            let current = finalizedSegments[index].speaker
            if current == nil || Self.isAutoSpeakerLabel(current!) {
                finalizedSegments[index].speaker = "Speaker \(number)"
            }
        }
    }

    /// True for the auto-generated "Speaker 3" form (so we never overwrite a name
    /// the user typed).
    static func isAutoSpeakerLabel(_ name: String) -> Bool {
        name.range(of: #"^Speaker \d+$"#, options: .regularExpression) != nil
    }
    #endif

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
