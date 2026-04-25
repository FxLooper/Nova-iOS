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

    /// Confidence threshold — jak moc si musí být model jistý
    private let confidenceThreshold: Double = 0.7

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
        }

        do {
            engine.prepare()
            try engine.start()
            isRunning = true
            lastError = nil
            dlog("[wake] ✅ started — CoreML SoundAnalysis, threshold: \(confidenceThreshold)")
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
        guard label == "hey_nova" && confidence >= confidenceThreshold else { return }

        let now = Date()
        guard now.timeIntervalSince(lastTriggerAt) > triggerCooldown else { return }
        lastTriggerAt = now

        lastHeardText = "Hey Nova (\(Int(confidence * 100))%)"
        dlog("[wake] 🔥 HEY NOVA detected! confidence: \(Int(confidence * 100))%")

        HapticManager.shared.conversationToggle()
        onWakeDetected?()
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
