import SwiftUI
import AVFoundation

// Face ID-style voice enrollment wizard for Nova Voice ID.
// Records 3 samples (~10s each), uploads to Mac server for embedding extraction,
// averages the embeddings, and stores the voice profile in Keychain.

struct VoiceEnrollmentView: View {
    @EnvironmentObject var nova: NovaService
    @EnvironmentObject var voiceProfile: VoiceProfileService
    @Environment(\.dismiss) var dismiss

    @StateObject private var recorder = VoiceRecorder()
    @State private var showSuccessCheck = false

    // Enrollment prompts (one per step)
    private let prompts = [
        "Přečti tuhle větu přirozeným hlasem",
        "Řekni něco o svém dni, klidně 10 sekund",
        "Přečti tuhle větu znovu, ale trochu jinou intonací"
    ]

    private let sampleTexts = [
        "Dobrý den, jmenuji se Ondřej a jsem rád, že Nova rozpozná můj hlas.",
        "Dneska je krásný den a chystám se na něco produktivního.",
        "Nova, chci aby jsi poznala právě mě a nikoho jiného."
    ]

    var body: some View {
        ZStack {
            Color(hex: "f5f0e8").ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button("Zavřít") { dismiss() }
                        .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))
                    Spacer()
                    Text("Voice Profile")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(Color(hex: "1a1a2e").opacity(0.8))
                    Spacer()
                    Button("Zavřít") { }.opacity(0)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)

                Spacer()

                // Content based on state
                VStack(spacing: 24) {
                    switch voiceProfile.state {
                    case .notEnrolled:
                        enrollmentIntroView

                    case .enrolling(let step, let total):
                        enrollmentStepView(step: step, total: total)

                    case .uploading:
                        processingView(message: "Odesílám vzorky na Mac server...", progress: 0.5)

                    case .processing:
                        processingView(message: "Vytvářím tvůj hlasový profil...", progress: 0.8)

                    case .enrolled:
                        enrolledView

                    case .error(let msg):
                        errorView(message: msg)
                    }
                }
                .padding(.horizontal, 32)

                Spacer()
            }
        }
        .onAppear {
            recorder.onAutoStop = { url in
                Task {
                    await voiceProfile.addEnrollmentSample(url)
                }
            }
        }
    }

    // MARK: - Intro (not enrolled)

    private var enrollmentIntroView: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 80, weight: .ultraLight))
                .foregroundColor(Color(hex: "1a1a2e").opacity(0.6))

            Text("Face ID pro tvůj hlas")
                .font(.system(size: 24, weight: .light))
                .foregroundColor(Color(hex: "1a1a2e").opacity(0.85))

            Text("Nova se naučí tvůj hlas a bude reagovat jen na tebe. Nikdo cizí ji nespustí.")
                .font(.system(size: 14, weight: .light))
                .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 8) {
                Label("Nahraje se 3× ~10 sekund tvého hlasu", systemImage: "mic.fill")
                Label("Audio se analyzuje na tvém Mac serveru", systemImage: "desktopcomputer")
                Label("Profil se uloží do iOS Keychain (Secure Enclave)", systemImage: "lock.shield")
            }
            .font(.system(size: 13, weight: .light))
            .foregroundColor(Color(hex: "1a1a2e").opacity(0.55))

            Button(action: {
                voiceProfile.startEnrollment()
            }) {
                Text("Začít enrollment")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(Color(hex: "1a1a2e").opacity(0.85))
                    .cornerRadius(12)
            }
            .padding(.top, 12)
        }
    }

    // MARK: - Enrollment step

    private func enrollmentStepView(step: Int, total: Int) -> some View {
        VStack(spacing: 24) {
            // Step indicator
            HStack(spacing: 12) {
                ForEach(1...total, id: \.self) { i in
                    Circle()
                        .fill(i <= step ? Color(hex: "1a1a2e").opacity(0.85) : Color(hex: "1a1a2e").opacity(0.15))
                        .frame(width: 10, height: 10)
                }
            }

            Text("Krok \(step) z \(total)")
                .font(.system(size: 13, weight: .light))
                .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))

            Text(prompts[min(step - 1, prompts.count - 1)])
                .font(.system(size: 18, weight: .light))
                .foregroundColor(Color(hex: "1a1a2e").opacity(0.85))
                .multilineTextAlignment(.center)

            // Sample text box
            Text("„" + sampleTexts[min(step - 1, sampleTexts.count - 1)] + "“")
                .font(.system(size: 16, weight: .light))
                .italic()
                .foregroundColor(Color(hex: "1a1a2e").opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
                .background(Color.white.opacity(0.5))
                .cornerRadius(12)

            // Recording indicator
            ZStack {
                Circle()
                    .fill(recorder.isRecording ? Color.red.opacity(0.15) : Color(hex: "1a1a2e").opacity(0.05))
                    .frame(width: 140, height: 140)

                if recorder.isRecording {
                    Circle()
                        .stroke(Color.red.opacity(0.6), lineWidth: 2)
                        .frame(width: 140, height: 140)
                        .scaleEffect(1.0 + CGFloat(recorder.audioLevel) * 0.3)
                        .animation(.easeOut(duration: 0.15), value: recorder.audioLevel)
                }

                Image(systemName: recorder.isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 50, weight: .ultraLight))
                    .foregroundColor(recorder.isRecording ? .red : Color(hex: "1a1a2e").opacity(0.6))
            }

            if recorder.isRecording {
                Text(String(format: "%.1fs / 10s", recorder.currentDuration))
                    .font(.system(size: 15, weight: .light))
                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.6))
                    .monospacedDigit()
            }

            Button(action: {
                if recorder.isRecording {
                    if let url = recorder.stopRecording() {
                        Task {
                            await voiceProfile.addEnrollmentSample(url)
                        }
                    }
                } else {
                    try? recorder.startRecording()
                }
            }) {
                Text(recorder.isRecording ? "Zastavit" : "Nahrávat")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(recorder.isRecording ? Color.red.opacity(0.8) : Color(hex: "1a1a2e").opacity(0.85))
                    .cornerRadius(12)
            }
        }
    }

    // MARK: - Processing

    private func processingView(message: String, progress: Double) -> some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .padding(.bottom, 12)

            Text(message)
                .font(.system(size: 16, weight: .light))
                .foregroundColor(Color(hex: "1a1a2e").opacity(0.7))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Enrolled (success)

    private var enrolledView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 80, weight: .ultraLight))
                .foregroundColor(.green.opacity(0.7))

            Text("Hotovo!")
                .font(.system(size: 24, weight: .light))
                .foregroundColor(Color(hex: "1a1a2e").opacity(0.85))

            Text("Nova teď zná tvůj hlas. Bude reagovat jen na tebe.")
                .font(.system(size: 14, weight: .light))
                .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                Button(action: {
                    dismiss()
                }) {
                    Text("Dokončit")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background(Color(hex: "1a1a2e").opacity(0.85))
                        .cornerRadius(12)
                }

                Button(action: {
                    voiceProfile.deleteProfile()
                }) {
                    Text("Smazat profil a začít znovu")
                        .font(.system(size: 14, weight: .light))
                        .foregroundColor(Color.red.opacity(0.6))
                }
            }
            .padding(.top, 20)
        }
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60, weight: .ultraLight))
                .foregroundColor(.orange.opacity(0.7))

            Text("Něco se pokazilo")
                .font(.system(size: 20, weight: .light))
                .foregroundColor(Color(hex: "1a1a2e").opacity(0.85))

            Text(message)
                .font(.system(size: 13, weight: .light))
                .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Button(action: {
                voiceProfile.startEnrollment()
            }) {
                Text("Zkusit znovu")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(Color(hex: "1a1a2e").opacity(0.85))
                    .cornerRadius(12)
            }
        }
    }
}

// MARK: - VoiceRecorder

@MainActor
class VoiceRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var currentDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0

    /// Called when recording auto-stops at max duration, with the recorded file URL
    var onAutoStop: ((URL) -> Void)?

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var currentURL: URL?
    private let maxDuration: TimeInterval = 10.0

    func startRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)

        let filename = "nova_enroll_\(Date().timeIntervalSince1970).m4a"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        currentURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        audioRecorder = try AVAudioRecorder(url: url, settings: settings)
        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.record()

        isRecording = true
        currentDuration = 0

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let recorder = self.audioRecorder, recorder.isRecording else { return }
                self.currentDuration = recorder.currentTime
                recorder.updateMeters()
                let avgPower = recorder.averagePower(forChannel: 0)
                self.audioLevel = max(0, min(1, (avgPower + 60) / 60))

                if self.currentDuration >= self.maxDuration {
                    if let url = self.stopRecording() {
                        self.onAutoStop?(url)
                    }
                }
            }
        }
    }

    @discardableResult
    func stopRecording() -> URL? {
        audioRecorder?.stop()
        audioRecorder = nil
        timer?.invalidate()
        timer = nil
        isRecording = false
        audioLevel = 0
        return currentURL
    }
}
