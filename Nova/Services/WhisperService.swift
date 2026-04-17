import Foundation
@preconcurrency import AVFoundation
import WhisperKit

// MARK: - WhisperService
// Lokální on-device speech-to-text přes WhisperKit (Core ML / Neural Engine).
// Nahrazuje DictationTranscriber. Auto-detect jazyka, streaming, plně offline.
//
// Použití:
//   let whisper = WhisperService()
//   await whisper.loadModel(.small)
//   whisper.onTranscript = { text, isFinal, language in ... }
//   try whisper.startListening()
//   ...
//   whisper.stopListening()

@MainActor
class WhisperService: ObservableObject {

    // MARK: - Public

    enum ModelSize: String {
        case tiny    = "openai_whisper-tiny"
        case base    = "openai_whisper-base"
        case small   = "openai_whisper-small"   // doporučeno (244MB)
        case medium  = "openai_whisper-medium"
        case largeV3 = "openai_whisper-large-v3"
    }

    enum WhisperState: Equatable {
        case unloaded
        case loading
        case ready
        case listening
        case transcribing
        case error(String)
    }

    @Published private(set) var state: WhisperState = .unloaded
    @Published private(set) var detectedLanguage: String? = nil
    @Published private(set) var loadProgress: Double = 0.0

    /// Callback pro každý nový (i průběžný) přepis.
    /// - Parameters:
    ///   - text: Aktuální transkript
    ///   - isFinal: True když uživatel domluvil (VAD detekoval ticho)
    ///   - language: Detekovaný jazyk (např. "cs", "en")
    var onTranscript: ((String, Bool, String?) -> Void)?

    /// Doba ticha (v sekundách) než se transkript prohlásí za final
    var silenceThreshold: TimeInterval = 1.5

    /// Práh amplitudy pro VAD (0.0 - 1.0). Pod tímto = ticho.
    nonisolated(unsafe) var vadThreshold: Float = 0.015

    /// Jazykový hint — nil = auto-detect, "cs" = preferuj češtinu
    var languageHint: String? = nil

    /// Callback pro raw 16kHz Float32 samples — pro Voice ID ring buffer
    nonisolated(unsafe) var onRawAudio: (([Float]) -> Void)?

    // MARK: - Private

    private var whisperKit: WhisperKit?
    private let audioEngine = AVAudioEngine()
    private var audioBuffer: [Float] = []
    private let sampleRate: Double = 16000  // Whisper vyžaduje 16kHz
    private var lastVoiceTime: Date?
    private var silenceTimer: Timer?
    private var transcribeTask: Task<Void, Never>?
    private var isProcessing = false

    // Akumulátor pro chunked transcription
    private var minChunkSamples: Int { Int(sampleRate * 1.0) }   // min 1s
    private var maxChunkSamples: Int { Int(sampleRate * 30.0) }  // max 30s (Whisper limit)

    // MARK: - Init

    private var interruptionObserver: NSObjectProtocol?

    init() {
        setupInterruptionHandling()
    }

    deinit {
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupInterruptionHandling() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleAudioInterruption(notification)
            }
        }
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            print("[whisper] audio interrupted (phone call, Siri, etc.)")
            if case .listening = state {
                stopListening()
            }
        case .ended:
            let shouldResume = (info[AVAudioSessionInterruptionOptionKey] as? UInt)
                .flatMap { AVAudioSession.InterruptionOptions(rawValue: $0) }
                .map { $0.contains(.shouldResume) } ?? false
            print("[whisper] interruption ended, shouldResume: \(shouldResume)")
            if shouldResume && state == .ready {
                try? startListening()
            }
        @unknown default:
            break
        }
    }

    // MARK: - Model loading

    /// Načte (a stáhne pokud chybí) Whisper model.
    /// Modely se cachují v Documents/whisperkit-models/
    func loadModel(_ size: ModelSize? = nil) async {
        state = .loading
        loadProgress = 0.0

        // Model selection s fallback chain
        let modelsToTry: [String]
        if let size = size {
            modelsToTry = [size.rawValue]
        } else {
            let recommended = WhisperKit.recommendedModels()
            let rec = recommended.default
            let deviceRAM = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024) // GB
            print("[whisper] device recommends: \(rec), RAM: \(deviceRAM)GB")
            // Smart model selection podle zařízení:
            // 6GB+ RAM (Pro/Max): small → base (nejlepší poměr kvalita/výkon)
            // 4GB+ RAM: base → tiny
            // <4GB RAM: tiny
            // Pozn: large-v3 je na mobilech příliš velký na CoreML kompilaci
            if deviceRAM >= 6 {
                modelsToTry = [ModelSize.small.rawValue, ModelSize.base.rawValue]
            } else if deviceRAM >= 4 {
                modelsToTry = [ModelSize.base.rawValue, ModelSize.tiny.rawValue]
            } else {
                modelsToTry = [ModelSize.tiny.rawValue]
            }
        }

        for modelName in modelsToTry {
            print("[whisper] trying model: \(modelName)")
            do {
                // Animovaný progress (simulovaný, WhisperKit neexponuje download progress v init)
                let progressTask = Task { @MainActor [weak self] in
                    var p = 0.0
                    while p < 0.9 {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        p = min(p + 0.05, 0.9)
                        self?.loadProgress = p
                    }
                }

                whisperKit = try await WhisperKit(
                    WhisperKitConfig(
                        model: modelName,
                        verbose: false,
                        logLevel: .error,
                        prewarm: true,
                        load: true,
                        download: true
                    )
                )
                progressTask.cancel()
                await MainActor.run { self.loadProgress = 1.0 }
                state = .ready
                print("[whisper] model ready: \(modelName)")
                return
            } catch {
                print("[whisper] model \(modelName) failed: \(error.localizedDescription)")
                continue
            }
        }

        state = .error("Whisper nelze načíst")
        print("[whisper] all models failed")
    }

    // MARK: - Listening control

    /// Spustí kontinuální poslech mikrofonu s VAD a streaming transcription.
    func startListening() throws {
        guard case .ready = state else {
            print("[whisper] not ready, state: \(state)")
            return
        }
        guard whisperKit != nil else {
            print("[whisper] no model loaded")
            return
        }

        // Audio session
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        // Vyčisti předchozí stav
        audioBuffer.removeAll()
        lastVoiceTime = nil
        isProcessing = false

        // Setup audio tap (16kHz mono Float32)
        let inputNode = audioEngine.inputNode
        let hwFormat = inputNode.inputFormat(forBus: 0)

        // Whisper potřebuje 16kHz mono Float32
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw NSError(domain: "WhisperService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot create target audio format"])
        }

        guard let converter = AVAudioConverter(from: hwFormat, to: targetFormat) else {
            throw NSError(domain: "WhisperService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Cannot create audio converter"])
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
            self?.handleAudioBuffer(buffer, converter: converter, targetFormat: targetFormat)
        }

        audioEngine.prepare()
        try audioEngine.start()

        state = .listening
        startSilenceMonitor()
        print("[whisper] listening started")
    }

    /// Zastaví poslech a uvolní audio session.
    func stopListening() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        transcribeTask?.cancel()
        transcribeTask = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)

        audioBuffer.removeAll()
        lastVoiceTime = nil
        isProcessing = false

        if case .listening = state { state = .ready }
        if case .transcribing = state { state = .ready }
        print("[whisper] listening stopped")
    }

    // MARK: - Audio processing

    /// Audio buffer processing — called from audio tap (real-time thread).
    /// Extracted as nonisolated to avoid @MainActor violation on audio render thread.
    nonisolated private func handleAudioBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, targetFormat: AVAudioFormat) {
        // Konverze na 16kHz mono Float32
        let frameRatio = targetFormat.sampleRate / buffer.format.sampleRate
        let convertedFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * frameRatio)
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: convertedFrameCount) else { return }

        var error: NSError?
        converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        if let error = error {
            print("[whisper] audio conversion error: \(error)")
        }
        guard error == nil, let channelData = convertedBuffer.floatChannelData?[0] else { return }
        let frameLength = Int(convertedBuffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))

        // Voice ID ring buffer — export raw 16kHz samples (nonisolated safe)
        let rawAudioCallback = self.onRawAudio
        rawAudioCallback?(samples)

        // Voice Activity Detection — RMS amplitude
        let rms = Self.computeRMS(samples)
        let threshold = self.vadThreshold

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.audioBuffer.append(contentsOf: samples)

            if rms > threshold {
                self.lastVoiceTime = Date()
            }

            // Limit buffer size (30s max — Whisper limit)
            if self.audioBuffer.count > self.maxChunkSamples {
                let excess = self.audioBuffer.count - self.maxChunkSamples
                self.audioBuffer.removeFirst(excess)
            }
        }
    }

    nonisolated private static func computeRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumSquares = samples.reduce(0) { $0 + $1 * $1 }
        return sqrt(sumSquares / Float(samples.count))
    }

    // MARK: - VAD silence monitor

    private func startSilenceMonitor() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkSilence()
            }
        }
    }

    private func checkSilence() {
        guard let lastVoice = lastVoiceTime else { return }
        guard !isProcessing else { return }
        guard audioBuffer.count >= minChunkSamples else { return }

        let elapsed = Date().timeIntervalSince(lastVoice)
        if elapsed >= silenceThreshold {
            // Uživatel domluvil → finalize chunk
            triggerTranscription(isFinal: true)
        } else if audioBuffer.count >= Int(sampleRate * 5.0) && !isProcessing {
            // Průběžný transcript každých 5s mluvení (streaming feedback)
            triggerTranscription(isFinal: false)
        }
    }

    // MARK: - Transcription

    private func triggerTranscription(isFinal: Bool) {
        guard let whisperKit = whisperKit else { return }
        guard !isProcessing else { return }
        guard !audioBuffer.isEmpty else { return }

        let samples = audioBuffer
        if isFinal {
            audioBuffer.removeAll()
            lastVoiceTime = nil
        }

        isProcessing = true
        state = .transcribing

        transcribeTask = Task {
            do {
                // Pokud je nastaven languageHint, vynuť jazyk (žádný auto-detect drift)
                let options = DecodingOptions(
                    verbose: false,
                    task: .transcribe,
                    language: self.languageHint,
                    temperature: 0.0,
                    temperatureFallbackCount: self.languageHint != nil ? 0 : 3,
                    detectLanguage: self.languageHint == nil,
                    skipSpecialTokens: true,
                    withoutTimestamps: true,
                    noSpeechThreshold: 0.6
                )
                let result: [TranscriptionResult] = try await whisperKit.transcribe(
                    audioArray: samples,
                    decodeOptions: options
                )

                let text = result.first?.text ?? ""
                let language = result.first?.language

                await MainActor.run {
                    self.isProcessing = false
                    if case .transcribing = self.state { self.state = .listening }

                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        if let lang = language {
                            self.detectedLanguage = lang
                        }
                        self.onTranscript?(trimmed, isFinal, language)
                        print("[whisper] transcript (\(language ?? "?"), final: \(isFinal)): \(trimmed)")
                    }
                }
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    if case .transcribing = self.state { self.state = .listening }
                    print("[whisper] transcription error: \(error)")
                }
            }
        }
    }
}
