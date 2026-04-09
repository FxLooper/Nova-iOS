import Foundation
import AVFoundation
import Speech
import Combine

@MainActor
class NovaService: ObservableObject {
    // MARK: - Published State
    @Published var messages: [Message] = []
    @Published var state: NovaState = .idle
    @Published var isConnected = false
    @Published var isMuted = false
    @Published var interimText = ""
    @Published var pendingConfirmation: PendingConfirmation?

    struct PendingConfirmation: Identifiable {
        let id = UUID()
        let action: ActionResponse
        let speech: String
    }

    // MARK: - Server Config
    private var serverURL = ""
    private var token = ""
    private var webSocket: URLSessionWebSocketTask?

    // MARK: - Audio
    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "cs-CZ"))
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private let synthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?

    enum NovaState: String {
        case idle, listening, thinking, speaking
    }

    // MARK: - Init
    init() {
        loadConfig()
        loadMessages()
    }

    // MARK: - Config (Keychain)
    func loadConfig() {
        serverURL = KeychainHelper.load(key: "nova_server") ?? ""
        token = KeychainHelper.load(key: "nova_token") ?? ""
    }

    func configure(server: String, token: String) {
        self.serverURL = server
        self.token = token
        KeychainHelper.save(key: "nova_server", value: server)
        KeychainHelper.save(key: "nova_token", value: token)
        connectWebSocket()
    }

    var isConfigured: Bool {
        !serverURL.isEmpty && !token.isEmpty
    }

    // MARK: - Messages Persistence
    private let messagesKey = "nova_messages"

    func loadMessages() {
        if let data = UserDefaults.standard.data(forKey: messagesKey),
           let saved = try? JSONDecoder().decode([Message].self, from: data) {
            messages = saved.suffix(100)
        }
    }

    func saveMessages() {
        let recent = Array(messages.suffix(100))
        if let data = try? JSONEncoder().encode(recent) {
            UserDefaults.standard.set(data, forKey: messagesKey)
        }
    }

    func clearMessages() {
        messages.removeAll()
        UserDefaults.standard.removeObject(forKey: messagesKey)
    }

    // MARK: - API Communication
    func sendMessage(_ text: String) async {
        guard !text.isEmpty else { return }

        let userMsg = Message(role: "user", content: text)
        messages.append(userMsg)
        saveMessages()
        state = .thinking

        do {
            let payload: [String: Any] = [
                "messages": messages.suffix(20).map { ["role": $0.role == "user" ? "user" : "assistant", "content": $0.content] },
                "profile": ["lang": "cs", "name": "Ondřej", "city": "Plzeň", "agentName": "Nova"]
            ]
            let jsonData = try JSONSerialization.data(withJSONObject: payload)

            var request = URLRequest(url: URL(string: "\(serverURL)/api/chat")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(token, forHTTPHeaderField: "X-Nova-Token")
            request.httpBody = jsonData
            request.timeoutInterval = 60

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Server error"])
            }

            let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
            let reply = chatResponse.content ?? "Omlouvám se, něco se pokazilo."

            let aiMsg = Message(role: "ai", content: reply)
            messages.append(aiMsg)
            saveMessages()

            // Handle action if present
            if let action = chatResponse.action {
                await handleAction(action)
            }

            // TTS
            state = .speaking
            await playTTS(reply)
            state = .idle

        } catch {
            let errorMsg = Message(role: "ai", content: "Chyba: \(error.localizedDescription)")
            messages.append(errorMsg)
            saveMessages()
            state = .idle
        }
    }

    // MARK: - TTS
    func playTTS(_ text: String) async {
        guard let url = URL(string: "\(serverURL)/api/tts") else { return }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(token, forHTTPHeaderField: "X-Nova-Token")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["text": text, "voice": "cs-vlasta"])

            let (data, _) = try await URLSession.shared.data(for: request)

            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.play()

            // Wait for playback to finish
            while audioPlayer?.isPlaying == true {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        } catch {
            // Fallback: iOS native TTS
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "cs-CZ")
            utterance.rate = 0.55
            synthesizer.speak(utterance)
        }
    }

    // MARK: - Speech Recognition
    func startListening() {
        guard !isMuted else { return }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return }

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard status == .authorized else { return }
            Task { @MainActor in
                self?.beginRecognition()
            }
        }
    }

    private func beginRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil

        // Audio session setup
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[speech] audio session failed: \(error)")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0) // Remove old tap if exists
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            request.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            state = .listening
        } catch {
            print("[speech] engine start failed: \(error)")
            return
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                if let result = result {
                    let text = result.bestTranscription.formattedString
                    self?.interimText = text
                    if result.isFinal {
                        self?.interimText = ""
                        self?.stopListening()
                        await self?.sendMessage(text)
                    }
                } else if error != nil {
                    self?.stopListening()
                }
            }
        }
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        if state == .listening { state = .idle }
    }

    func toggleMute() {
        isMuted.toggle()
        if isMuted { stopListening() }
    }

    // MARK: - WebSocket
    func connectWebSocket() {
        guard !serverURL.isEmpty else { return }
        let wsURL = serverURL.replacingOccurrences(of: "http", with: "ws")
        guard let url = URL(string: wsURL) else { return }

        let session = URLSession(configuration: .default)
        webSocket = session.webSocketTask(with: url)
        webSocket?.resume()
        isConnected = true
        receiveWebSocket()
    }

    private func receiveWebSocket() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                if case .string(let text) = message,
                   let data = text.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    Task { @MainActor in
                        self?.handleWSMessage(json)
                    }
                }
                self?.receiveWebSocket()
            case .failure:
                Task { @MainActor in
                    self?.isConnected = false
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    self?.connectWebSocket()
                }
            }
        }
    }

    private func handleWSMessage(_ json: [String: Any]) {
        guard let type = json["type"] as? String else { return }
        switch type {
        case "message":
            if let role = json["role"] as? String, let text = json["text"] as? String {
                if json["source"] as? String == "api" { return } // Ignore own echoes
                let msg = Message(role: role, content: text)
                messages.append(msg)
                saveMessages()
            }
        case "state":
            if let s = json["state"] as? String {
                state = NovaState(rawValue: s) ?? .idle
            }
        default: break
        }
    }

    // MARK: - Action Handling
    func handleAction(_ action: ActionResponse) async {
        let needsConfirm = ["send_message", "add_calendar", "facetime_call", "dev"].contains(action.action)
        if needsConfirm {
            pendingConfirmation = PendingConfirmation(action: action, speech: action.speech ?? "Mám to udělat?")
        } else {
            await executeAction(action)
        }
    }

    func confirmAction(_ confirmed: Bool) async {
        guard let pending = pendingConfirmation else { return }
        pendingConfirmation = nil
        if confirmed {
            let msg = Message(role: "user", content: "Ano.")
            messages.append(msg)
            await executeAction(pending.action)
        } else {
            let msg = Message(role: "ai", content: "Dobře, nic nedělám.")
            messages.append(msg)
            saveMessages()
        }
    }

    private func executeAction(_ action: ActionResponse) async {
        state = .thinking
        let endpointMap: [String: String] = [
            "open_url": "/api/action/open-url",
            "open_app": "/api/action/open-app",
            "send_message": "/api/action/send-message",
            "add_calendar": "/api/action/calendar",
            "facetime_call": "/api/action/facetime",
            "read_calendar": "/api/action/read-calendar",
            "read_email": "/api/action/read-email",
            "weather": "/api/action/weather",
            "read_news": "/api/action/read-news",
        ]
        guard let endpoint = endpointMap[action.action],
              let url = URL(string: "\(serverURL)\(endpoint)") else {
            state = .idle
            return
        }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(token, forHTTPHeaderField: "X-Nova-Token")
            if let params = action.params {
                let dict = params.mapValues { $0.value }
                request.httpBody = try JSONSerialization.data(withJSONObject: dict)
            }
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let content = json["content"] as? String {
                let msg = Message(role: "ai", content: content)
                messages.append(msg)
                saveMessages()
                state = .speaking
                await playTTS(content)
            }
        } catch {
            let msg = Message(role: "ai", content: "Akce selhala: \(error.localizedDescription)")
            messages.append(msg)
            saveMessages()
        }
        state = .idle
    }
}
