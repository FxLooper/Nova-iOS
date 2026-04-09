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
    @Published var voiceMode: VoiceMode = .wakeWord
    private var speechDebounceTask: Task<Void, Never>?
    private var silenceTimer: Task<Void, Never>?
    private var sessionPrefix = ""

    enum VoiceMode {
        case wakeWord   // Čeká na "Nova"/"Novo"/"Hey Nova"
        case active     // Aktivně poslouchá příkaz
        case off        // Vypnuto (muted)
    }

    private let wakeWords = ["nova", "novo", "nová", "hey nova", "hej nova"]

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
    private var speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: "cs-CZ"))
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
        loadProfile()
    }

    // MARK: - Config (Keychain)
    func loadConfig() {
        serverURL = KeychainHelper.load(key: "nova_server") ?? ""
        token = KeychainHelper.load(key: "nova_token") ?? ""
    }

    @Published var needsSetup = false

    func resetConfig() {
        serverURL = ""
        token = ""
        KeychainHelper.delete(key: "nova_server")
        KeychainHelper.delete(key: "nova_token")
        needsSetup = true
    }

    func configure(server: String, token: String) {
        self.serverURL = server
        self.token = token
        self.needsSetup = false
        KeychainHelper.save(key: "nova_server", value: server)
        KeychainHelper.save(key: "nova_token", value: token)
        connectWebSocket()
    }

    var isConfigured: Bool {
        !serverURL.isEmpty && !token.isEmpty
    }

    // MARK: - Profile
    @Published var profile: [String: String] = [:]

    func updateProfile(lang: String, city: String, name: String, voice: String, voiceGender: String) {
        profile = [
            "lang": lang, "city": city, "name": name,
            "voice": voice, "voiceGender": voiceGender, "agentName": "Nova"
        ]
        // Update speech recognizer language
        let langMap = ["cs":"cs-CZ","en":"en-US","de":"de-DE","sk":"sk-SK","fr":"fr-FR","es":"es-ES","it":"it-IT","pl":"pl-PL","ja":"ja-JP","zh":"zh-CN","ko":"ko-KR","ar":"ar-SA","tr":"tr-TR","hi":"hi-IN","pt":"pt-BR","ru":"ru-RU"]
        if let locale = langMap[lang] {
            speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: locale))
        }
    }

    func loadProfile() {
        let lang = UserDefaults.standard.string(forKey: "nova_lang") ?? "cs"
        let city = UserDefaults.standard.string(forKey: "nova_city") ?? "Plzeň"
        let name = UserDefaults.standard.string(forKey: "nova_user_name") ?? "Ondřej"
        let voice = UserDefaults.standard.string(forKey: "nova_voice") ?? "cs-vlasta"
        let gender = UserDefaults.standard.string(forKey: "nova_voice_gender") ?? "female"
        updateProfile(lang: lang, city: city, name: name, voice: voice, voiceGender: gender)
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
                "profile": profile.isEmpty ? ["lang": "cs", "name": "Ondřej", "city": "Plzeň", "agentName": "Nova"] : profile
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

            // Po odpovědi → conversation mode (10s na follow-up, pak zpět na wake word)
            if !isMuted {
                voiceMode = .active
                sessionPrefix = ""
                // Pauza po TTS než se restartne mic
                try? await Task.sleep(nanoseconds: 500_000_000)
                startListening()
                silenceTimer?.cancel()
                silenceTimer = Task {
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    guard !Task.isCancelled else { return }
                    if self.state == .listening {
                        self.voiceMode = .wakeWord
                        self.stopListening()
                        self.startListening() // Restart v wake word mode
                    }
                }
            } else {
                state = .idle
            }

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
        guard !isMuted else { print("[speech] muted"); return }
        guard let recognizer = speechRecognizer else { print("[speech] no recognizer"); return }
        guard recognizer.isAvailable else { print("[speech] recognizer not available"); return }

        let authStatus = SFSpeechRecognizer.authorizationStatus()
        if authStatus == .authorized {
            beginRecognition()
        } else {
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                print("[speech] auth status: \(status.rawValue)")
                guard status == .authorized else { return }
                Task { @MainActor in
                    self?.beginRecognition()
                }
            }
        }
    }

    private func beginRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil

        // Audio session setup
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
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
            if voiceMode == .wakeWord {
                state = .idle // Wake word mode — orb ukazuje idle
                print("[speech] wake word mode started")
            } else {
                state = .listening
                print("[speech] active listening started")
            }
        } catch {
            print("[speech] engine start failed: \(error)")
            state = .idle
            return
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                if let result = result {
                    let text = result.bestTranscription.formattedString.lowercased()

                    if self?.voiceMode == .wakeWord {
                        // Wake word detection
                        if self?.wakeWords.contains(where: { text.contains($0) }) == true {
                            print("[speech] wake word detected: \(text)")
                            self?.voiceMode = .active
                            self?.state = .listening
                            self?.interimText = ""
                            self?.sessionPrefix = text
                            // Restart recognition v active mode s malou pauzou
                            self?.stopListening()
                            Task {
                                try? await Task.sleep(nanoseconds: 300_000_000)
                                self?.beginRecognition()
                            }
                        }
                        return
                    }

                    // Active mode — zobraz interim a pošli po pauze
                    // Odstraň session prefix (Apple SR kumuluje text)
                    var clean = text
                    if !self!.sessionPrefix.isEmpty && text.hasPrefix(self!.sessionPrefix) {
                        clean = String(text.dropFirst(self!.sessionPrefix.count)).trimmingCharacters(in: .whitespaces)
                    }
                    self?.interimText = clean.isEmpty ? text : clean

                    self?.speechDebounceTask?.cancel()
                    self?.speechDebounceTask = Task {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        guard !Task.isCancelled else { return }
                        let finalText = self?.interimText ?? ""
                        if !finalText.isEmpty {
                            self?.interimText = ""
                            self?.stopListening()
                            await self?.sendMessage(finalText)
                        }
                    }

                    if result.isFinal {
                        self?.speechDebounceTask?.cancel()
                        let finalText = self?.interimText ?? ""
                        self?.interimText = ""
                        self?.stopListening()
                        if !finalText.isEmpty { await self?.sendMessage(finalText) }
                    }
                } else if error != nil {
                    // Pošli co máme pokud je interim text
                    let partial = self?.interimText ?? ""
                    if !partial.isEmpty {
                        self?.interimText = ""
                        self?.stopListening()
                        await self?.sendMessage(partial)
                    } else {
                        self?.stopListening()
                    }
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

    // MARK: - Dev Mode
    private func executeDevAction(_ action: ActionResponse) async {
        do {
            let task = action.params?["task"]?.value as? String ?? ""
            let devMessages = messages.suffix(10).map { ["role": $0.role == "user" ? "user" : "assistant", "content": $0.content] } + [["role": "user", "content": task]]

            // Step 1: Plan
            var planRequest = URLRequest(url: URL(string: "\(serverURL)/api/dev/plan")!)
            planRequest.httpMethod = "POST"
            planRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            planRequest.setValue(token, forHTTPHeaderField: "X-Nova-Token")
            planRequest.httpBody = try JSONSerialization.data(withJSONObject: ["messages": devMessages])
            planRequest.timeoutInterval = 120

            let (planData, _) = try await URLSession.shared.data(for: planRequest)
            let planJson = try JSONSerialization.jsonObject(with: planData) as? [String: Any]
            let planContent = planJson?["content"] as? String ?? "Nemůžu navrhnout plán."
            let needsConfirm = planJson?["needsConfirm"] as? Bool ?? true

            let planMsg = Message(role: "ai", content: planContent)
            messages.append(planMsg)
            saveMessages()

            if !needsConfirm {
                // Read-only — hotovo
                state = .speaking
                await playTTS(planContent)
                state = .idle
                return
            }

            // Needs confirmation — show buttons
            state = .idle
            pendingDevPlan = DevPlan(task: task, planContent: planContent, devMessages: devMessages)
            pendingConfirmation = PendingConfirmation(action: action, speech: planContent)

        } catch {
            let msg = Message(role: "ai", content: "Dev mode chyba: \(error.localizedDescription)")
            messages.append(msg)
            saveMessages()
            state = .idle
        }
    }

    struct DevPlan {
        let task: String
        let planContent: String
        let devMessages: [[String: String]]
    }
    var pendingDevPlan: DevPlan?

    func confirmDevAction() async {
        guard let plan = pendingDevPlan else { return }
        pendingDevPlan = nil
        state = .thinking

        let confirmMsg = Message(role: "user", content: "Ano, udělej to.")
        messages.append(confirmMsg)

        do {
            var devMsgs = plan.devMessages
            devMsgs.append(["role": "assistant", "content": plan.planContent])
            devMsgs.append(["role": "user", "content": "Ano, proveď to."])

            var execRequest = URLRequest(url: URL(string: "\(serverURL)/api/dev/execute")!)
            execRequest.httpMethod = "POST"
            execRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            execRequest.setValue(token, forHTTPHeaderField: "X-Nova-Token")
            execRequest.httpBody = try JSONSerialization.data(withJSONObject: ["messages": devMsgs])
            execRequest.timeoutInterval = 120

            let (execData, _) = try await URLSession.shared.data(for: execRequest)
            let execJson = try JSONSerialization.jsonObject(with: execData) as? [String: Any]
            let execContent = execJson?["content"] as? String ?? "Hotovo."

            let resultMsg = Message(role: "ai", content: execContent)
            messages.append(resultMsg)
            saveMessages()

            state = .speaking
            await playTTS(execContent)
        } catch {
            let msg = Message(role: "ai", content: "Chyba při provádění: \(error.localizedDescription)")
            messages.append(msg)
            saveMessages()
        }
        state = .idle
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
            if pending.action.action == "dev" && pendingDevPlan != nil {
                await confirmDevAction()
            } else {
                let msg = Message(role: "user", content: "Ano.")
                messages.append(msg)
                await executeAction(pending.action)
            }
        } else {
            let msg = Message(role: "ai", content: "Dobře, nic nedělám.")
            messages.append(msg)
            saveMessages()
        }
    }

    private func executeAction(_ action: ActionResponse) async {
        state = .thinking

        // Dev mode — dvoustupňový flow (plan → execute)
        if action.action == "dev" {
            await executeDevAction(action)
            return
        }

        let endpointMap: [String: String] = [
            "open_url": "/api/action/open-url",
            "open_app": "/api/action/open-app",
            "send_message": "/api/action/send-message",
            "add_calendar": "/api/action/calendar",
            "facetime_call": "/api/action/facetime",
            "read_calendar": "/api/action/read-calendar",
            "read_email": "/api/action/read-email",
            "weather": "/api/action/weather",
            "web_search": "/api/action/web-search",
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
