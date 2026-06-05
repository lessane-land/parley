import Foundation
import AVFoundation
import Speech

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
        case denied
        case unavailable(String)
    }

    private(set) var state: State = .idle
    /// Confirmed text (won't change).
    private(set) var finalizedText: String = ""
    /// The in-flight guess for what's being said right now (updates rapidly).
    private(set) var volatileText: String = ""
    /// When the current session began (for the timer).
    private(set) var startedAt: Date?

    var isRecording: Bool { state == .recording }

    // Audio + Speech objects
    private let engine = AVAudioEngine()
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?

    // MARK: Start / stop

    /// Begin a session, seeding with any transcript already on the note so we
    /// append rather than overwrite. `preferredLanguage` is a language code
    /// ("es") to force, or `nil` for Automatic.
    func start(seed: String, preferredLanguage: String? = nil) async {
        guard state == .idle || isError else { return }
        finalizedText = seed
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
        // `.record` (input only) — we never play audio back, so we must NOT pass
        // `.duckOthers` here: ducking is only valid on output-bearing categories
        // (.playback/.playAndRecord/…), and combining it with `.record` makes
        // setCategory throw paramErr (OSStatus -50). `.allowBluetooth` lets a
        // paired headset/mic be the input source.
        try session.setCategory(.record, mode: .spokenAudio, options: [.allowBluetooth])
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

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
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
    }

    private func teardown() async {
        continuation = nil
        analyzer = nil
        transcriber = nil
        resultsTask = nil
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
