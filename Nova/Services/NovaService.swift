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
    @Published var conversationActive = false // Tap orb = zapni/vypni konverzaci
    private var speechDebounceTask: Task<Void, Never>?

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
        // SpeechAnalyzer použije speechLocale property automaticky
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

            // Po odpovědi → pokračuj v konverzaci
            continueConversation()

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

    // MARK: - Conversation Mode (SpeechAnalyzer — iOS 26)
    // Tap orb = zapni konverzaci. Nova poslouchá continuous → odpoví → poslouchá dál.

    private var analyzer: SpeechAnalyzer?
    private var analyzerTask: Task<Void, Never>?
    private var silenceTask: Task<Void, Never>?
    private var currentUtterance = ""

    func toggleConversation() {
        print("[speech] toggleConversation called, active: \(conversationActive)")
        if conversationActive {
            endConversation()
        } else {
            startConversation()
        }
    }

    func startConversation() {
        guard !isMuted else { return }
        conversationActive = true
        startDictation()
    }

    func endConversation() {
        conversationActive = false
        analyzerTask?.cancel()
        analyzerTask = nil
        analyzer = nil
        dictationTranscriber = nil
        silenceTask?.cancel()
        speechDebounceTask?.cancel()
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        currentUtterance = ""
        interimText = ""
        state = .idle
        print("[speech] conversation ended")
    }

    func continueConversation() {
        guard conversationActive && !isMuted else {
            state = .idle
            return
        }
        Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard conversationActive else { return }
            startDictation()
        }
    }

    private var dictationTranscriber: DictationTranscriber?

    // MARK: - DictationTranscriber (server-based, funguje na všech zařízeních)
    private func startDictation() {
        // Zastav předchozí session
        analyzerTask?.cancel()
        analyzerTask = nil
        analyzer = nil
        dictationTranscriber = nil
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)

        // Audio session
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[speech] audio session error: \(error)")
            return
        }

        let locale = Locale(identifier: speechLocale)
        dictationTranscriber = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
        guard let transcriber = dictationTranscriber else {
            print("[speech] DictationTranscriber init failed")
            return
        }
        analyzer = SpeechAnalyzer(modules: [transcriber])
        guard let analyzer = analyzer else {
            print("[speech] SpeechAnalyzer init failed")
            return
        }

        state = .listening
        currentUtterance = ""
        print("[speech] DictationTranscriber started (\(locale))")

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)

        analyzerTask = Task { [weak self] in
            do {
                guard let targetFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                    print("[speech] no compatible audio format")
                    return
                }
                let hwFormat = inputNode.inputFormat(forBus: 0)
                print("[speech] hw format: \(hwFormat), target format: \(targetFormat)")

                guard let converter = AVAudioConverter(from: hwFormat, to: targetFormat) else {
                    print("[speech] failed to create audio converter")
                    return
                }

                var bufferCount = 0
                let inputStream = AsyncStream<AnalyzerInput> { continuation in
                    inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { buffer, _ in
                        let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * targetFormat.sampleRate / hwFormat.sampleRate)
                        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return }
                        var error: NSError?
                        converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                            outStatus.pointee = .haveData
                            return buffer
                        }
                        if error == nil {
                            bufferCount += 1
                            if bufferCount <= 3 || bufferCount % 100 == 0 {
                                print("[speech] buffer #\(bufferCount), frames: \(convertedBuffer.frameLength)")
                            }
                            continuation.yield(AnalyzerInput(buffer: convertedBuffer))
                        } else {
                            print("[speech] convert error: \(error!)")
                        }
                    }
                    continuation.onTermination = { _ in
                        inputNode.removeTap(onBus: 0)
                    }
                }

                // Alokuj locale modely
                try await analyzer.prepareToAnalyze(in: targetFormat)
                print("[speech] analyzer prepared")

                self?.audioEngine.prepare()
                try self?.audioEngine.start()
                print("[speech] engine running: \(self?.audioEngine.isRunning ?? false)")

                // Čti výsledky souběžně
                let resultsTask = Task { [weak self] in
                    for try await result in transcriber.results {
                        guard !Task.isCancelled else { break }
                        let text = String(result.text.characters)
                        print("[speech] transcript: \(text)")
                        await MainActor.run {
                            guard let self = self else { return }
                            self.currentUtterance = text
                            self.interimText = text
                            self.silenceTask?.cancel()
                            self.silenceTask = Task { @MainActor [weak self] in
                                try? await Task.sleep(nanoseconds: 2_000_000_000)
                                guard !Task.isCancelled, let self = self else { return }
                                await self.handleUtteranceEnd()
                            }
                        }
                    }
                }

                print("[speech] calling analyzer.start()...")
                try await analyzer.start(inputSequence: inputStream)
                print("[speech] analyzer.start() returned")
                resultsTask.cancel()
            } catch {
                print("[speech] DictationTranscriber error: \(error)")
                await MainActor.run { self?.state = .idle }
            }
        }
    }

    private func handleUtteranceEnd() async {
        let text = currentUtterance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        currentUtterance = ""
        interimText = ""

        analyzerTask?.cancel()
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)

        await sendMessage(text)
    }

    private var speechLocale: String {
        let lang = UserDefaults.standard.string(forKey: "nova_lang") ?? "cs"
        let map = ["cs":"cs-CZ","en":"en-US","de":"de-DE","sk":"sk-SK","fr":"fr-FR","es":"es-ES","it":"it-IT","pl":"pl-PL","ja":"ja-JP","zh":"zh-CN","ko":"ko-KR","ar":"ar-SA","tr":"tr-TR","hi":"hi-IN","pt":"pt-BR","ru":"ru-RU"]
        return map[lang] ?? "cs-CZ"
    }

    // Legacy
    func startListening() { startConversation() }
    func stopListening() { endConversation() }

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
