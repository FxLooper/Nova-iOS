import Foundation
import AVFoundation
import SoundAnalysis

/// Wake Word detection using CoreML Sound Classifier (HeyNovaClassifier)
/// Runs on Neural Engine — low power, on-device, no internet needed.
/// Detects "Hey Nova" and fires onWakeDetected callback.
@MainActor
final class WakeWordService: ObservableObject {
    @Published var isRunning = false
    @Published var lastHeardText = ""
    @Published var lastError: String?

    /// Callback — volá se když bylo zachyceno "Hey Nova"
    var onWakeDetected: (() -> Void)?

    private var audioEngine: AVAudioEngine?
    private var analyzer: SNAudioStreamAnalyzer?
    private var request: SNClassifySoundRequest?
    private let analysisQueue = DispatchQueue(label: "com.fxlooper.nova.wakeword")

    /// Confidence threshold — adaptivní podle ambient noise.
    /// V tichu citlivější (lépe zachytí), v hluku odolnější (méně false triggers).
    private let minThreshold: Double = 0.62
    private let maxThreshold: Double = 0.80
    private var currentThreshold: Double = 0.70

    /// Ambient RMS — exponential moving average pro adaptivní threshold
    private var ambientRMS: Float = 0.0
    private let rmsAlpha: Float = 0.05  // pomalá adaptace ~30s timeconstant

    /// Debounce — cooldown mezi triggery
    private var lastTriggerAt: Date = .distantPast
    private let triggerCooldown: TimeInterval = 3.0

    // MARK: - Authorization
    func requestAuthorization() async -> Bool {
        // Mikrofon
        let micStatus = AVAudioApplication.shared.recordPermission
        if micStatus == .undetermined {
            return await withCheckedContinuation { cont in
                AVAudioApplication.requestRecordPermission { granted in
                    cont.resume(returning: granted)
                }
            }
        }
        return micStatus == .granted
    }

    // MARK: - Start
    func start() {
        guard !isRunning else { return }

        // Load CoreML model
        guard let modelURL = Bundle.main.url(forResource: "HeyNovaClassifier", withExtension: "mlmodelc")
                ?? Bundle.main.url(forResource: "HeyNovaClassifier", withExtension: "mlmodel") else {
            lastError = "Model HeyNovaClassifier nenalezen"
            dlog("[wake] model not found in bundle")
            return
        }

        do {
            // CPU + Neural Engine — GPU není povoleno na pozadí
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine
            let mlModel = try MLModel(contentsOf: modelURL, configuration: config)
            request = try SNClassifySoundRequest(mlModel: mlModel)
            request?.windowDuration = CMTime(seconds: 1.5, preferredTimescale: 16000)
            request?.overlapFactor = 0.5
        } catch {
            lastError = "Model load failed: \(error.localizedDescription)"
            dlog("[wake] model load failed: \(error)")
            return
        }

        // Audio session
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement,
                                    options: [.mixWithOthers, .allowBluetooth, .defaultToSpeaker])
            try session.setActive(true)
        } catch {
            lastError = "Audio session: \(error.localizedDescription)"
            dlog("[wake] audio session error: \(error)")
            return
        }

        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else { return }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        analyzer = SNAudioStreamAnalyzer(format: format)
        guard let analyzer = analyzer, let request = request else { return }

        let observer = WakeWordObserver { [weak self] label, confidence in
            Task { @MainActor in
                self?.handleDetection(label: label, confidence: confidence)
            }
        }

        do {
            try analyzer.add(request, withObserver: observer)
        } catch {
            lastError = "Analyzer setup failed: \(error.localizedDescription)"
            dlog("[wake] analyzer add failed: \(error)")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 8192, format: format) { [weak self] buffer, time in
            self?.analysisQueue.async {
                self?.analyzer?.analyze(buffer, atAudioFramePosition: time.sampleTime)
            }
            // Adaptivní threshold — počítej ambient RMS a aktualizuj práh
            if let rms = WakeWordService.computeRMS(buffer) {
                Task { @MainActor in
                    self?.updateAmbientRMS(rms)
                }
            }
        }

        do {
            engine.prepare()
            try engine.start()
            isRunning = true
            lastError = nil
            dlog("[wake] ✅ started — CoreML SoundAnalysis, adaptive threshold \(minThreshold)–\(maxThreshold)")
        } catch {
            lastError = "Engine start: \(error.localizedDescription)"
            dlog("[wake] engine start failed: \(error)")
        }
    }

    // MARK: - Stop
    func stop() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        analyzer = nil
        isRunning = false
        dlog("[wake] stopped")
    }

    // MARK: - Detection
    private func handleDetection(label: String, confidence: Double) {
        guard label == "hey_nova" && confidence >= currentThreshold else { return }

        let now = Date()
        guard now.timeIntervalSince(lastTriggerAt) > triggerCooldown else { return }
        lastTriggerAt = now

        lastHeardText = "Hey Nova (\(Int(confidence * 100))%)"
        dlog("[wake] 🔥 HEY NOVA detected! confidence: \(Int(confidence * 100))% (threshold: \(String(format: "%.2f", currentThreshold)))")

        HapticManager.shared.conversationToggle()
        onWakeDetected?()
    }

    // MARK: - Adaptive Threshold

    /// Spočítá RMS jednoho audio bufferu. Statická → bezpečná z analysisQueue.
    private static func computeRMS(_ buffer: AVAudioPCMBuffer) -> Float? {
        guard let channelData = buffer.floatChannelData?[0] else { return nil }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return nil }
        var sum: Float = 0
        for i in 0..<frameLength {
            let s = channelData[i]
            sum += s * s
        }
        return sqrt(sum / Float(frameLength))
    }

    /// Aktualizuje ambient RMS (EMA) a přepočítá adaptivní threshold.
    /// Kvalitní mikrofon: ticho ~0.003-0.008, normální místnost ~0.01-0.02, hlasitý ambient 0.04+.
    private func updateAmbientRMS(_ rms: Float) {
        ambientRMS = ambientRMS * (1 - rmsAlpha) + rms * rmsAlpha
        let quietRMS: Float = 0.005
        let loudRMS: Float = 0.04
        let normalized = max(0.0, min(1.0, (ambientRMS - quietRMS) / (loudRMS - quietRMS)))
        currentThreshold = minThreshold + Double(normalized) * (maxThreshold - minThreshold)
    }
}

// MARK: - SoundAnalysis Observer
private class WakeWordObserver: NSObject, SNResultsObserving {
    let onDetection: (String, Double) -> Void

    init(onDetection: @escaping (String, Double) -> Void) {
        self.onDetection = onDetection
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classificationResult = result as? SNClassificationResult else { return }
        guard let top = classificationResult.classifications.first else { return }
        onDetection(top.identifier, Double(top.confidence))
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        dlog("[wake] analysis error: \(error.localizedDescription)")
    }
}
