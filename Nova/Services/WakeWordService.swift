import Foundation
import AVFoundation
import Speech
import Combine

/// On-device wake word detection for phrases like "Hi Nova", "Ahoj Nova", "Novo".
///
/// Design:
/// - Uses SFSpeechRecognizer with `requiresOnDeviceRecognition = true` for privacy + offline.
/// - Runs a lightweight continuous audio tap separate from the main conversation audio engine,
///   so wake-word listening does not collide with push-to-talk or live conversation audio.
/// - Rolling recognition window: restart every ~45s to prevent SFSpeech's long-utterance bugs.
/// - Fires `onWakeDetected` on the main actor when any wake phrase is heard.
///
/// Hard limits (iOS reality):
/// - Apple does NOT allow 3rd-party wake word while the app is suspended. This runs only when:
///     a) the app is in foreground, or
///     b) briefly in background for up to ~10–15 minutes after active conversation,
///        gated by `UIBackgroundModes = audio` (already set in Info.plist).
/// - For truly system-wide "Hi Nova" the user must say "Hey Siri, Hi Nova" — handled by
///   Siri Shortcuts invocation phrase in `NovaIntents.swift`.
@MainActor
final class WakeWordService: ObservableObject {
    @Published var isRunning = false
    @Published var lastHeardText = ""
    @Published var lastError: String?

    /// Callback — volá se když bylo zachyceno wake word. Běží na @MainActor.
    var onWakeDetected: (() -> Void)?

    /// Povolené wake fráze. Vyhodnocují se case-insensitive, bez diakritiky.
    /// "Novo" je nebezpečně krátké — chytá se i v běžné řeči, takže vyžadujeme kontext.
    private let wakePhrases: [String] = [
        "hi nova", "hey nova", "ahoj nova", "ahoj novo",
        "nova poslouchej", "novo poslouchej",
        "ok nova", "ok novo"
    ]

    /// Čas posledního triggeru — debounce, ať jedno vyslovení "Hi Nova" neprobudí Novu třikrát.
    private var lastTriggerAt: Date = .distantPast
    private let triggerCooldown: TimeInterval = 3.0

    // MARK: - Speech stack
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var rollingRestartTimer: Timer?

    init() {
        // Český recognizer jede jako primární — zachytí "Ahoj Nova" i "Hi Nova" (anglicismy projdou).
        // Pokud češtinu systém nemá, fallback na "en-US".
        self.recognizer = SFSpeechRecognizer(locale: Locale(identifier: "cs-CZ"))
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    // MARK: - Authorization
    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    // MARK: - Start / Stop
    func start() {
        guard !isRunning else { return }
        guard let recognizer = recognizer, recognizer.isAvailable else {
            lastError = "Speech recognizer nedostupný"
            print("[wake] recognizer not available")
            return
        }

        // Snaž se o on-device rozpoznání (privacy + žádný traffic do Apple)
        let req = SFSpeechAudioBufferRecognitionRequest()
        if #available(iOS 13.0, *) {
            req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        }
        req.shouldReportPartialResults = true
        if #available(iOS 16.0, *) {
            req.addsPunctuation = false
        }
        self.request = req

        // Audio session — necháme jí neinvazivní. Když někdo jiný (konverzace) aktivuje session,
        // přidáme se k ní; jinak si zvolíme .record s mixem.
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord,
                                    mode: .measurement,
                                    options: [.mixWithOthers, .duckOthers, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            lastError = "Audio session: \(error.localizedDescription)"
            print("[wake] audio session error: \(error)")
            return
        }
        #endif

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            lastError = "Audio engine: \(error.localizedDescription)"
            print("[wake] engine start failed: \(error)")
            return
        }

        self.task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor in
                    self.lastHeardText = text
                    self.evaluate(text: text)
                }
            }
            if error != nil || (result?.isFinal ?? false) {
                // Restart chain po chybě nebo final segmentu
                Task { @MainActor in
                    if self.isRunning { self.restartSoft() }
                }
            }
        }

        // Safety net: restart každých 45s, ať SF nezacykluje na dlouhém bufferu
        rollingRestartTimer?.invalidate()
        rollingRestartTimer = Timer.scheduledTimer(withTimeInterval: 45.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.restartSoft() }
        }

        isRunning = true
        lastError = nil
        print("[wake] started — locale: \(recognizer.locale.identifier), on-device: \(req.requiresOnDeviceRecognition)")
    }

    func stop() {
        rollingRestartTimer?.invalidate()
        rollingRestartTimer = nil
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        isRunning = false
        print("[wake] stopped")
    }

    /// Lehký restart recognition tasku beze změny audio enginu — používá se periodicky
    /// i po chybách, ať poslech nikdy "neumře".
    private func restartSoft() {
        guard isRunning else { return }
        guard let recognizer = recognizer, recognizer.isAvailable else { return }
        task?.cancel()
        task = nil
        request?.endAudio()

        let req = SFSpeechAudioBufferRecognitionRequest()
        if #available(iOS 13.0, *) {
            req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        }
        req.shouldReportPartialResults = true
        self.request = req

        self.task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor in
                    self.lastHeardText = text
                    self.evaluate(text: text)
                }
            }
            if error != nil || (result?.isFinal ?? false) {
                Task { @MainActor in
                    if self.isRunning { self.restartSoft() }
                }
            }
        }
    }

    // MARK: - Phrase evaluation
    private func evaluate(text raw: String) {
        let text = Self.normalize(raw)
        guard !text.isEmpty else { return }
        // Bereme jen poslední ~40 znaků — ať staré transkripty nebudí Novu opakovaně
        let tail = String(text.suffix(40))
        for phrase in wakePhrases {
            let normPhrase = Self.normalize(phrase)
            if tail.contains(normPhrase) {
                trigger(phrase: normPhrase)
                return
            }
        }
    }

    private func trigger(phrase: String) {
        let now = Date()
        guard now.timeIntervalSince(lastTriggerAt) > triggerCooldown else { return }
        lastTriggerAt = now
        print("[wake] 🔥 triggered by: \(phrase)")
        // Restart recognition buffer, ať se další vyslovení Novy nedetekuje dvakrát
        restartSoft()
        onWakeDetected?()
    }

    /// Normalizace: lowercase + bez diakritiky + jednoduché mezery.
    static func normalize(_ s: String) -> String {
        let lowered = s.lowercased()
        let folded = lowered.folding(options: .diacriticInsensitive, locale: Locale(identifier: "cs_CZ"))
        // squish multi-space
        return folded.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                     .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
