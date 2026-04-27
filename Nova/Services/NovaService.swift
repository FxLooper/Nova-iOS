import Foundation
import AVFoundation
import Speech
import Combine
import UIKit

@MainActor
class NovaService: ObservableObject {
    // MARK: - Published State
    @Published var messages: [Message] = []
    @Published var state: NovaState = .idle {
        didSet {
            updateLiveActivityForState()
        }
    }
    @Published var isConnected = false
    @Published var isMuted = false
    @Published var ttsEnabled: Bool = UserDefaults.standard.object(forKey: "nova_tts_enabled") == nil ? true : UserDefaults.standard.bool(forKey: "nova_tts_enabled")
    /// Earpiece mode — hlas přes sluchátko (jako telefonát), lepší barge-in
    @Published var earpieceMode: Bool = UserDefaults.standard.bool(forKey: "nova_earpiece_mode")
    @Published var interimText = ""
    @Published var pendingConfirmation: PendingConfirmation?
    @Published var conversationActive = false // Tap orb = zapni/vypni konverzaci
    @Published var pushToTalkActive = false    // Hold mic button = push-to-talk
    private var pttAccumulated = ""            // Akumulovaný text z PTT vět
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
    /// Text co Nova právě říká přes TTS
    var currentTTSText: String = ""
    /// Barge-in flag — interruptAndListen() ho nastaví na true, playTTS smyčka ho kontroluje a utne zbylou frontu vět
    private var ttsInterrupted: Bool = false
    /// VAD barge-in — sleduje amplitude během TTS
    private var bargeInVoiceStart: Date? = nil
    private let bargeInAmplitudeThreshold: Float = 0.015  // AEC tlumí vše — hlas je 0.015-0.022, ambient 0.001-0.005
    private let bargeInDurationThreshold: TimeInterval = 0.1  // 100ms — rychlá reakce na krátké slovo "Novo!"

    // MARK: - Whisper STT (experimentální)
    private let whisper = WhisperService()
    // WhisperKit default ON — výrazně lepší čeština než DictationTranscriber
    @Published var useWhisper: Bool = {
        if UserDefaults.standard.object(forKey: "nova_use_whisper") == nil {
            return true  // Default ON pro nové instalace
        }
        return UserDefaults.standard.bool(forKey: "nova_use_whisper")
    }()
    @Published var whisperState: WhisperService.WhisperState = .unloaded
    @Published var whisperLoadProgress: Double = 0.0
    private var whisperStateObserver: AnyCancellable?
    private var whisperProgressObserver: AnyCancellable?

    // MARK: - Voice ID (biometric speaker verification)
    let voiceProfile = VoiceProfileService()
    let serverHealth = ServerHealthMonitor()
    let networkMonitor = NetworkMonitor()
    @Published var voiceVerificationEnforced: Bool = UserDefaults.standard.bool(forKey: "nova_voice_verify_enforce")
    @Published var lastVerificationFailed: Bool = false  // UI indicator

    // MARK: - Wake Word ("Hi Nova" / "Ahoj Nova")
    let wakeWord = WakeWordService()
    @Published var wakeWordEnabled: Bool = UserDefaults.standard.bool(forKey: "nova_wake_word_enabled") {
        didSet {
            UserDefaults.standard.set(wakeWordEnabled, forKey: "nova_wake_word_enabled")
            if wakeWordEnabled {
                Task { await self.startWakeWordIfAllowed() }
            } else {
                wakeWord.stop()
            }
        }
    }

    // MARK: - Thinking stage (granular progress shown in chat bubble)
    struct ThinkingStage: Equatable {
        let key: String
        let detail: String?
    }
    @Published var thinkingStage: ThinkingStage? {
        didSet {
            // Auto-detekce dev/web mode podle stage
            updateModeFromStage()
        }
    }
    @Published var isDevMode: Bool = false
    @Published var isWebMode: Bool = false
    @Published var devLogs: [String] = []
    @Published var devHistory: [String] = []

    private var webModeTimer: Timer?
    func updateModeFromStage() {
        guard let key = thinkingStage?.key else {
            // Při ukončení nech WEB ještě 1.5s svítit (pokud je aktivní)
            if isWebMode {
                webModeTimer?.invalidate()
                webModeTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
                    Task { @MainActor in self?.isWebMode = false }
                }
            }
            return
        }
        // Web-related stages
        let webStages: Set<String> = [
            "searching_web", "browsing_results", "searching_deeper", "preparing_report",
            "fetching_news", "analyzing_news", "checking_weather", "searching_wiki",
            "checking_exchange", "searching_cinema", "searching_places", "calling_api",
            "reading_web"
        ]
        if webStages.contains(key) {
            webModeTimer?.invalidate()
            if !isWebMode {
                dlog("[mode] WEB ON (stage: \(key))")
                isWebMode = true
            }
        }
    }

    // Načti historii dev logů ze serveru
    func loadDevHistory() async {
        guard let url = URL(string: "\(serverURL)/api/dev/history") else { return }
        var req = URLRequest(url: url)
        req.setValue(token, forHTTPHeaderField: "X-Nova-Token")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let logs = json["logs"] as? [String] {
                devHistory = logs
            }
        } catch {
            dlog("[devHistory] error: \(error.localizedDescription)")
        }
    }

    // Načti nové cron výsledky a přidej do chatu jako Nova zprávy
    private var lastCronCheck: Date = Date()
    // MARK: - Project Session
    @Published var activeSession: String? = nil  // název aktivního projektu

    func resetSession() async {
        activeSession = nil
        guard let url = URL(string: "\(serverURL)/api/session/reset") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(token, forHTTPHeaderField: "X-Nova-Token")
        _ = try? await URLSession.shared.data(for: req)
        dlog("[session] reset from iOS")
    }

    func checkSession() async {
        guard let url = URL(string: "\(serverURL)/api/session") else { return }
        var req = URLRequest(url: url)
        req.setValue(token, forHTTPHeaderField: "X-Nova-Token")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let active = json["active"] as? Bool ?? false
                activeSession = active ? (json["project"] as? String) : nil
            }
        } catch {
            dlog("[checkSession] failed: \(error.localizedDescription)")
        }
    }

    func checkCronResults() async {
        guard let url = URL(string: "\(serverURL)/api/scheduled/results") else { return }
        var req = URLRequest(url: url)
        req.setValue(token, forHTTPHeaderField: "X-Nova-Token")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]] else { return }
            let formatter = ISO8601DateFormatter()
            for result in results.reversed() {
                guard let timestamp = result["timestamp"] as? String,
                      let ts = formatter.date(from: timestamp),
                      ts > lastCronCheck,
                      let resultText = result["result"] as? String,
                      let taskName = result["taskName"] as? String else { continue }
                let msg = Message(role: "ai", content: "📅 \(taskName)\n\n\(resultText)")
                if !messages.contains(where: { $0.content == msg.content }) {
                    messages.append(msg)
                    // Banner notifikace
                    showBanner(.cron, title: taskName, detail: resultText.prefix(80) + "...", autoDismiss: 10)
                }
            }
            saveMessages()
            lastCronCheck = Date()
        } catch { dlog("[cron] check error: \(error)") }
    }

    func clearDevHistory() async {
        guard let url = URL(string: "\(serverURL)/api/dev/history/clear") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(token, forHTTPHeaderField: "X-Nova-Token")
        _ = try? await URLSession.shared.data(for: req)
        devHistory = []
        devLogs = []  // smaž i live logy
    }

    // MARK: - Memory (Nova si pamatuje fakta o uživateli)
    @Published var memoryFacts: [String] = []
    @Published var memoryLoading = false

    func fetchMemory() async {
        guard let url = URL(string: "\(serverURL)/api/memory") else { return }
        var req = URLRequest(url: url)
        req.setValue(token, forHTTPHeaderField: "X-Nova-Token")
        memoryLoading = true
        defer { memoryLoading = false }
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let facts = json["facts"] as? [String] {
                memoryFacts = facts
            }
        } catch { dlog("[memory] fetch error: \(error)") }
    }

    func deleteMemoryFact(at index: Int) async {
        guard let url = URL(string: "\(serverURL)/api/memory/\(index)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue(token, forHTTPHeaderField: "X-Nova-Token")
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                await fetchMemory()
            }
        } catch { dlog("[memory] delete error: \(error)") }
    }

    func clearAllMemory() async {
        guard let url = URL(string: "\(serverURL)/api/memory/clear") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(token, forHTTPHeaderField: "X-Nova-Token")
        do {
            let (_, _) = try await URLSession.shared.data(for: req)
            memoryFacts = []
        } catch { dlog("[memory] clear error: \(error)") }
    }

    // MARK: - Recap (automatické připomenutí po neaktivitě)
    @Published var recapText: String? = nil
    @Published var activeBanners: [BannerItem] = []

    func showBanner(_ type: BannerItem.BannerType, title: String, detail: String? = nil, autoDismiss: TimeInterval? = 5.0) {
        let banner = BannerItem(type: type, title: title, detail: detail, autoDismiss: autoDismiss)
        activeBanners.append(banner)
        // Max 3 bannery najednou
        if activeBanners.count > 3 { activeBanners.removeFirst() }
        // Auto-dismiss
        if let delay = autoDismiss {
            let bannerId = banner.id
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                activeBanners.removeAll { $0.id == bannerId }
            }
        }
    }

    func dismissBanner(_ banner: BannerItem) {
        activeBanners.removeAll { $0.id == banner.id }
    }
    private var lastActivityTime: Date = Date()
    /// Čas kdy se whisper naposledy restartoval — ignoruj transcripty prvních 1.5s (echo)
    private var listeningResumeTime: Date = .distantPast
    private let recapInactivityThreshold: TimeInterval = 30 * 60 // 30 minut

    func checkAndShowRecap() async {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastActivityTime)
        lastActivityTime = now

        // Jen pokud uplynulo 30+ minut a máme historii
        guard elapsed > recapInactivityThreshold, messages.count >= 2 else { return }
        // Nepokazuj recap pokud už jeden visí
        guard recapText == nil else { return }

        // Vezmi posledních pár zpráv pro kontext
        let recentMessages = messages.suffix(6)
        let summary = recentMessages.map { msg in
            let role = msg.role == "user" ? "Ondřej" : "Nova"
            return "\(role): \(msg.content.prefix(200))"
        }.joined(separator: "\n")

        // Vygeneruj recap přes Claude
        guard let url = URL(string: "\(serverURL)/api/chat") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "X-Nova-Token")
        request.timeoutInterval = 15

        let recapPrompt = "Napiš JEDNU krátkou českou větu (max 15 slov) shrnující na čem jsme naposledy pracovali. Bez markdown, bez emoji, jen prostý text. Kontext:\n\(summary)"
        let payload: [String: Any] = [
            "messages": [["user", recapPrompt]],
            "profile": profile
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let requestId = json["requestId"] as? String {
                // Poll pro výsledek (max 10s)
                for _ in 0..<20 {
                    try await Task.sleep(nanoseconds: 500_000_000)
                    guard let pollUrl = URL(string: "\(serverURL)/api/poll/\(requestId)") else { break }
                    var pollReq = URLRequest(url: pollUrl)
                    pollReq.setValue(token, forHTTPHeaderField: "X-Nova-Token")
                    let (pollData, _) = try await URLSession.shared.data(for: pollReq)
                    if let pollJson = try? JSONSerialization.jsonObject(with: pollData) as? [String: Any],
                       let status = pollJson["status"] as? String,
                       status == "done",
                       let text = pollJson["text"] as? String,
                       !text.isEmpty {
                        recapText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        dlog("[recap] \(recapText ?? "")")
                        // Auto-hide po 15s
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 15_000_000_000)
                            self.recapText = nil
                        }
                        return
                    }
                }
            }
        } catch {
            dlog("[recap] error: \(error.localizedDescription)")
        }
    }

    func markActivity() {
        lastActivityTime = Date()
    }

    // MARK: - Streaming chat
    @Published var streamingText: String = ""
    @Published var isStreaming: Bool = false
    private var streamReplacedText: String? = nil  // Clean speech text z stream-replace
    private var activeRequestId: String?
    private var streamCompletion: CheckedContinuation<String, Error>?

    // Rolling audio buffer (last 5s) for voice verification
    private var _ringBuffer: [Float] = []  // Accessed ONLY via audioRingBufferQueue
    private let audioRingBufferMaxSize = 16000 * 5  // 5 seconds @ 16kHz
    private let audioRingBufferQueue = DispatchQueue(label: "com.fxlooper.nova.audioring")

    enum NovaState: String {
        case idle, listening, thinking, speaking
    }

    // MARK: - Init
    init() {
        loadConfig()
        loadMessages()
        loadProfile()
        setupWhisperObservers()
        // Whisper se loaduje vždy — auto-detect jazyka, lepší kvalita STT
        if !useWhisper { setUseWhisper(true) }
        Task { await loadWhisperModel() }
        // Start GPS
        LocationService.shared.startUpdating()
        // Configure voice profile service with current server/token
        voiceProfile.configure(serverURL: serverURL, token: token)
        // Start monitoring Mac server health
        serverHealth.startMonitoring(serverURL: serverURL, token: token)
        // Network reachability — auto-reconnect WebSocket on network changes
        networkMonitor.onConnectionChange = { [weak self] isConnected in
            guard let self = self else { return }
            dlog("[network] connection changed: \(isConnected ? "ONLINE" : "OFFLINE")")
            if isConnected {
                // Network is back — force ping + reconnect WebSocket
                Task {
                    await self.serverHealth.pingNow()
                    self.connectWebSocket()
                }
            }
        }
        // Wake word: když zachytí "Hi Nova" / "Ahoj Nova", rovnou startuj konverzaci.
        wakeWord.onWakeDetected = { [weak self] in
            guard let self = self else { return }
            dlog("[wake] ▶️ triggering startConversation")
            HapticManager.shared.conversationToggle()
            self.startConversation()
        }
        if wakeWordEnabled {
            Task { await self.startWakeWordIfAllowed() }
        }
    }

    /// Request Speech auth (one-time) a nastart wake word listener. Bezpečně ignoruje chyby.
    func startWakeWordIfAllowed() async {
        guard wakeWordEnabled else { return }
        // Demo mode bez serveru: wake word může klidně běžet, jen startConversation zobrazí banner.
        let ok = await wakeWord.requestAuthorization()
        guard ok else {
            dlog("[wake] speech auth denied — wake word disabled")
            return
        }
        wakeWord.start()
    }

    // MARK: - Config (Keychain)
    func loadConfig() {
        serverURL = KeychainHelper.load(key: "nova_server") ?? ""
        token = KeychainHelper.load(key: "nova_token") ?? ""
    }

    // Public accessors for voice profile service
    func getServerURL() -> String { serverURL }
    func getToken() -> String { token }

    @Published var needsSetup = false

    // Demo režim — appka funguje bez Mac serveru pro prohlížení UI a seznámení.
    // Zprávy se lokálně odpoví tipem, že je potřeba připojit server pro plný provoz.
    @Published var demoMode: Bool = UserDefaults.standard.bool(forKey: "nova_demo_mode")

    func resetConfig() {
        serverURL = ""
        token = ""
        KeychainHelper.delete(key: "nova_server")
        KeychainHelper.delete(key: "nova_token")
        demoMode = false
        UserDefaults.standard.set(false, forKey: "nova_demo_mode")
        needsSetup = true
    }

    func enterDemoMode() {
        demoMode = true
        needsSetup = false
        UserDefaults.standard.set(true, forKey: "nova_demo_mode")
    }

    func exitDemoMode() {
        demoMode = false
        UserDefaults.standard.set(false, forKey: "nova_demo_mode")
        needsSetup = true
    }

    func configure(server: String, token: String) {
        self.serverURL = server
        self.token = token
        self.needsSetup = false
        self.demoMode = false
        UserDefaults.standard.set(false, forKey: "nova_demo_mode")
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
            messages = saved.suffix(200)
        }
    }

    func saveMessages() {
        let recent = Array(messages.suffix(200))
        if let data = try? JSONEncoder().encode(recent) {
            UserDefaults.standard.set(data, forKey: messagesKey)
        }
    }

    func clearMessages() {
        messages.removeAll()
        UserDefaults.standard.removeObject(forKey: messagesKey)
        // Reset server sessions (chat + dev) — Nova začne s čistou hlavou
        Task {
            if let url = URL(string: "\(serverURL)/api/chat/reset") {
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue(token, forHTTPHeaderField: "X-Nova-Token")
                try? await URLSession.shared.data(for: req)
            }
            if let url = URL(string: "\(serverURL)/api/dev/reset") {
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.setValue(token, forHTTPHeaderField: "X-Nova-Token")
                req.httpBody = try? JSONSerialization.data(withJSONObject: [:])
                try? await URLSession.shared.data(for: req)
            }
        }
    }

    // MARK: - API Communication (streaming přes WebSocket)
    private var isSending = false
    private var lastSendTime: Date = .distantPast
    private var activeTask: Task<Void, Never>?

    // Pošli obrázek Nově — vision
    func sendImage(_ image: UIImage) async {
        // Validace: max 4096x4096 px (větší zmenšit)
        var processedImage = image
        let maxDim: CGFloat = 4096
        if image.size.width > maxDim || image.size.height > maxDim {
            let scale = min(maxDim / image.size.width, maxDim / image.size.height)
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            if let resized = UIGraphicsGetImageFromCurrentImageContext() {
                processedImage = resized
            }
            UIGraphicsEndImageContext()
        }
        guard let jpegData = processedImage.jpegData(compressionQuality: 0.7) else { return }
        // Validace: max 10 MB
        guard jpegData.count < 10_000_000 else {
            let msg = Message(role: "ai", content: "Obrázek je moc velký (\(jpegData.count / 1_000_000) MB). Zkus menší.")
            messages.append(msg)
            saveMessages()
            return
        }
        let base64 = jpegData.base64EncodedString()

        // Přidej user zprávu s obrázkem placeholder
        let userMsg = Message(role: "user", content: "[Fotka 📷]")
        messages.append(userMsg)
        saveMessages()
        state = .thinking
        thinkingStage = ThinkingStage(key: "processing_image", detail: nil)

        do {
            guard let url = URL(string: "\(serverURL)/api/vision") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(token, forHTTPHeaderField: "X-Nova-Token")
            request.timeoutInterval = 60

            let profileDict = profile.isEmpty ? ["lang": "cs", "name": "Ondřej"] : profile
            let payload: [String: Any] = [
                "image": base64,
                "prompt": "Popiš co vidíš na obrázku. Pokud je tam text, přečti ho. Buď stručná ale konkrétní.",
                "profile": profileDict
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let content = json["content"] as? String {
                thinkingStage = nil
                let aiMsg = Message(role: "ai", content: content)
                messages.append(aiMsg)
                saveMessages()
                HapticManager.shared.novaResponseChord()
                state = .speaking
                await playTTS(content)
                state = .idle
            }
        } catch {
            thinkingStage = nil
            let errorMsg = Message(role: "ai", content: "Nepodařilo se zpracovat fotku: \(error.localizedDescription)")
            messages.append(errorMsg)
            saveMessages()
            state = .idle
        }
    }

    // MARK: - Video analýza
    func sendVideo(_ data: Data, filename: String) async {
        // Validace: max 200 MB
        guard data.count < 200_000_000 else {
            let msg = Message(role: "ai", content: "Video je moc velké (\(data.count / 1_000_000) MB). Maximum je 200 MB.")
            messages.append(msg)
            saveMessages()
            return
        }

        // Okamžitý feedback — uživatel vidí že Nova pracuje
        let userMsg = Message(role: "user", content: "[Video 🎬 \(filename) — \(data.count / 1_000_000) MB]")
        messages.append(userMsg)
        saveMessages()
        state = .thinking
        thinkingStage = ThinkingStage(key: "processing_video", detail: "Nahrávám \(data.count / 1_000_000) MB...")
        HapticManager.shared.selectionChanged()

        // Base64 encoding (může trvat u velkých videí)
        let base64 = data.base64EncodedString()
        thinkingStage = ThinkingStage(key: "processing_video", detail: filename)

        do {
            guard let url = URL(string: "\(serverURL)/api/video") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(token, forHTTPHeaderField: "X-Nova-Token")
            request.timeoutInterval = 180

            let payload: [String: Any] = [
                "video": base64,
                "filename": filename,
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (responseData, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
               let content = json["content"] as? String {
                thinkingStage = nil
                let aiMsg = Message(role: "ai", content: content)
                messages.append(aiMsg)
                saveMessages()
                HapticManager.shared.novaResponseChord()
                state = .speaking
                await playTTS(content)
                state = .idle
            }
        } catch {
            thinkingStage = nil
            let errorMsg = Message(role: "ai", content: "Nepodařilo se zpracovat video: \(error.localizedDescription)")
            messages.append(errorMsg)
            saveMessages()
            state = .idle
        }
    }

    func sendMessage(_ text: String) async {
        guard !text.isEmpty else { return }

        // Demo režim — bez serveru. Ukaž uživateli vzornou odpověď, ne error.
        if demoMode {
            let userMsg = Message(role: "user", content: text)
            messages.append(userMsg)
            saveMessages()
            let reply = Message(
                role: "ai",
                content: "Jsem v ukázkovém režimu 🌙 Zobrazuje se ti rozhraní Novy, ale pro plnou AI odpověď potřebuju připojení k tvému Nova serveru na Macu. V nastavení můžeš připojit server a začít konverzaci doopravdy."
            )
            messages.append(reply)
            saveMessages()
            HapticManager.shared.novaResponseChord()
            return
        }

        markActivity()
        recapText = nil  // Skryj recap při nové zprávě
        // Refresh session po každé zprávě (async)
        Task { await checkSession() }

        // Vždy zastav předchozí práci
        activeTask?.cancel()
        audioPlayer?.stop()
        audioPlayer = nil
        isSending = false

        // Debounce — ignoruj taps rychlejší než 1s
        let now = Date()
        guard now.timeIntervalSince(lastSendTime) > 1.0 else { return }

        isSending = true
        lastSendTime = now
        dlog("[chat] === SENDING: \(text.prefix(40)) ===")

        // Whisper běží ale transcripty se ignorují (guard state == .listening)
        // Whisper běží pro VAD barge-in, ale transcripty se ignorují (guard state == .listening)
        if conversationActive {
            currentUtterance = ""
            interimText = ""
            dlog("[chat] whisper on (VAD barge-in, threshold \(bargeInAmplitudeThreshold), duration \(bargeInDurationThreshold)s)")
        }

        // Zastav TTS pokud Nova právě mluví
        audioPlayer?.stop()
        audioPlayer = nil

        let userMsg = Message(role: "user", content: text)
        messages.append(userMsg)
        saveMessages()
        state = .thinking
        thinkingStage = ThinkingStage(key: "understanding", detail: nil)
        dlog("[stage] set to: understanding (sendMessage start)")
        streamingText = ""
        isStreaming = false
        streamReplacedText = nil

        do {
            var profileDict = profile.isEmpty ? ["lang": "cs", "name": "Ondřej", "city": "Plzeň", "agentName": "Nova"] : profile
            // Přidej GPS souřadnice pokud jsou dostupné
            if let loc = LocationService.shared.locationDict {
                profileDict["latitude"] = "\(loc["latitude"] ?? "")"
                profileDict["longitude"] = "\(loc["longitude"] ?? "")"
                if let gpsCity = loc["city"] as? String { profileDict["city"] = gpsCity }
                dlog("[GPS] sending: location attached")
            } else {
                dlog("[GPS] no location available")
            }
            var payload: [String: Any] = [
                "messages": messages.suffix(50).map { ["role": $0.role == "user" ? "user" : "assistant", "content": $0.content] },
                "profile": profileDict
            ]
            // Vynucený routing z nastavení — backend to může respektovat (auto/web/dev)
            let forceRouting = UserDefaults.standard.string(forKey: "nova_force_routing") ?? "auto"
            if forceRouting != "auto" {
                payload["forceMode"] = forceRouting
            }
            let jsonData = try JSONSerialization.data(withJSONObject: payload)

            guard let chatURL = URL(string: "\(serverURL)/api/chat") else {
                throw NSError(domain: "nova", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"])
            }
            var request = URLRequest(url: chatURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(token, forHTTPHeaderField: "X-Nova-Token")
            request.httpBody = jsonData
            request.timeoutInterval = 60

            dlog("[chat] POST \(serverURL)/api/chat, wsConnected=\(isConnected)")
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as? HTTPURLResponse
            dlog("[chat] response status: \(httpResponse?.statusCode ?? -1)")
            guard httpResponse?.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? ""
                dlog("[chat] error body: \(body)")
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Server error (\(httpResponse?.statusCode ?? -1))"])
            }

            // Server vrátí { streaming: true, requestId: "..." }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let requestId = json["requestId"] as? String {
                activeRequestId = requestId
                // Pokud server auto-detekoval dev akci, zobraz DEV indikátor
                if json["forceAction"] as? String == "dev" {
                    isDevMode = true
                }
            }

            // Vždy použij HTTP polling — WebSocket je nespolehlivý na iOS
            let reply: String = try await pollForResponse(requestId: activeRequestId ?? "")

            // Stream dokončen — finalizuj zprávu
            isStreaming = false
            streamingText = ""
            activeRequestId = nil

            // Server zpracoval akce sám — polling vrací hotový výsledek
            streamReplacedText = nil
            var displayText = reply

            // Detekuj __OPEN_URL__ token — otevři URL na iPhone
            if let range = displayText.range(of: "__OPEN_URL__") {
                let urlString = String(displayText[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                displayText = String(displayText[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                // Whitelist bezpečných URL schémat
                let allowedSchemes: Set<String> = ["https", "http", "maps", "tel", "facetime", "facetime-audio", "mailto", "sms"]
                if let url = URL(string: urlString),
                   let scheme = url.scheme?.lowercased(),
                   allowedSchemes.contains(scheme) {
                    dlog("[openURL] \(scheme): \(url.host ?? "")")
                    await UIApplication.shared.open(url)
                } else {
                    dlog("[openURL] BLOCKED unsafe scheme: \(urlString.prefix(30))")
                }
            }

            // Detekuj __IMAGE_URL__ token — zobraz obrázek v bublině
            var imageURL: String? = nil
            if let range = displayText.range(of: "__IMAGE_URL__") {
                imageURL = String(displayText[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                displayText = String(displayText[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let aiMsg = Message(role: "ai", content: displayText, imageURL: imageURL)
            messages.append(aiMsg)
            saveMessages()
            HapticManager.shared.novaResponseChord()

            // Pokud byl task zrušen (nová zpráva přerušila), nedělej TTS
            guard !Task.isCancelled else {
                isSending = false
                return
            }

            // Reset indikátorů — práce skončila
            isDevMode = false
            isWebMode = false

            // TTS — přečte speech text, ne raw JSON
            state = .speaking
            await playTTS(displayText)

            guard !Task.isCancelled else {
                isSending = false
                return
            }

            // Debounce po TTS — zastav whisper, počkej až echo dozní, restartuj
            whisper.stopListening()
            try? await Task.sleep(nanoseconds: 1_200_000_000) // 1.2s — echo z reproduktoru (zkráceno z 3s, AEC to zvládne)

            // Vyčisti echo zbytky před restart listening
            currentUtterance = ""
            interimText = ""

            // Po odpovědi → pokračuj v konverzaci
            isSending = false
            continueConversation()

        } catch {
            isSending = false
            isStreaming = false
            streamingText = ""
            activeRequestId = nil
            let errorMsg = Message(role: "ai", content: "Chyba: \(error.localizedDescription)")
            messages.append(errorMsg)
            saveMessages()
            state = .idle
        }
    }

    // MARK: - HTTP Polling Fallback
    private func pollForResponse(requestId: String) async throws -> String {
        guard !requestId.isEmpty else {
            throw NSError(domain: "nova", code: -1, userInfo: [NSLocalizedDescriptionKey: "No requestId"])
        }
        let pollURL = URL(string: "\(serverURL)/api/poll/\(requestId)")!
        var request = URLRequest(url: pollURL)
        request.setValue(token, forHTTPHeaderField: "X-Nova-Token")

        // Nastav výchozí stage hned
        thinkingStage = ThinkingStage(key: "understanding", detail: nil)

        // Adaptivní backoff: rychlé první dotazy ušetří ~700ms u rychlých odpovědí,
        // pomalý polling u dlouhých zachová server-friendly chování.
        // Limit 620 iterací pokrývá 5+ minut: 5×150 + 15×300 + 600×500 = ~305s.
        for i in 0..<620 {
            try Task.checkCancellation()
            let delayNs: UInt64
            if i < 5 {
                delayNs = 150_000_000  // 150ms — rychlé odpovědi
            } else if i < 20 {
                delayNs = 300_000_000  // 300ms — střední
            } else {
                delayNs = 500_000_000  // 500ms — pomalá generace / dev mode
            }
            try await Task.sleep(nanoseconds: delayNs)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let status = json["status"] as? String {
                let text = json["text"] as? String ?? ""
                if !text.isEmpty { streamingText = text; isStreaming = true }
                // Stage update — drž vždy nějaký stage viditelný
                let stageKey = json["stage"] as? String ?? ""
                let stageDetail = json["stageDetail"] as? String
                if !stageKey.isEmpty {
                    let newStage = ThinkingStage(key: stageKey, detail: stageDetail)
                    if thinkingStage != newStage {
                        thinkingStage = newStage
                        updateModeFromStage()  // explicitní fallback
                        dlog("[stage] received: \(stageKey)")
                        HapticManager.shared.selectionChanged()
                    }
                } else if !text.isEmpty && thinkingStage?.key != "generating_response" && thinkingStage?.key != "composing" {
                    // Text přichází ale stage je starý — přepni na formuluji
                    thinkingStage = ThinkingStage(key: "generating_response", detail: nil)
                } else if i > 3 && thinkingStage?.key == "understanding" {
                    thinkingStage = ThinkingStage(key: "analyzing", detail: nil)
                }
                // Update dev logs (pro terminal view)
                if let logs = json["logs"] as? [String], !logs.isEmpty {
                    devLogs = logs
                }
                if status == "done" {
                    thinkingStage = ThinkingStage(key: "finishing", detail: nil)
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    thinkingStage = nil
                    return text
                }
            }
        }
        throw NSError(domain: "nova", code: -1, userInfo: [NSLocalizedDescriptionKey: "Timeout čekání na odpověď"])
    }

    // MARK: - TTS

    /// Rozseká text na věty pro streamované TTS. Bezpečné na desetinná čísla a krátké zkratky.
    private func splitIntoSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            current.append(c)
            if c == "." || c == "!" || c == "?" {
                let prev = i > 0 ? chars[i - 1] : " "
                let next = i + 1 < chars.count ? chars[i + 1] : " "
                // Desetinné číslo: cifra . cifra → nerozdělovat
                if c == "." && prev.isNumber && next.isNumber {
                    i += 1
                    continue
                }
                // Rozdělit jen pokud následuje whitespace nebo konec textu
                if next.isWhitespace || i == chars.count - 1 {
                    let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        sentences.append(trimmed)
                    }
                    current = ""
                }
            }
            i += 1
        }
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { sentences.append(trimmed) }
        return sentences
    }

    /// Stáhne TTS audio pro jeden text chunk. Vrací nil při chybě.
    private func fetchTTSAudio(_ text: String) async -> Data? {
        guard let url = URL(string: "\(serverURL)/api/tts") else { return nil }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(token, forHTTPHeaderField: "X-Nova-Token")
            let selectedVoice = UserDefaults.standard.string(forKey: "nova_voice") ?? profile["voice"] ?? "cs-vlasta"
            let speedPct = Int(UserDefaults.standard.double(forKey: "nova_tts_speed"))
            let rate = speedPct >= 0 ? "+\(speedPct)%" : "\(speedPct)%"
            request.httpBody = try JSONSerialization.data(withJSONObject: ["text": text, "voice": selectedVoice, "rate": rate])

            let (data, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as? HTTPURLResponse
            let contentType = httpResponse?.value(forHTTPHeaderField: "Content-Type") ?? ""
            guard httpResponse?.statusCode == 200, contentType.contains("audio"), data.count > 200 else {
                dlog("[TTS] chunk fetch error: HTTP \(httpResponse?.statusCode ?? 0), type=\(contentType), size=\(data.count)")
                return nil
            }
            return data
        } catch {
            dlog("[TTS] chunk fetch exception: \(error.localizedDescription)")
            return nil
        }
    }

    /// Přehraje jeden audio buffer. Vrací true pokud doběhl normálně, false při přerušení nebo chybě.
    private func playTTSChunk(_ data: Data) async -> Bool {
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.play()
            while audioPlayer?.isPlaying == true {
                if !ttsEnabled || ttsInterrupted {
                    audioPlayer?.stop()
                    audioPlayer = nil
                    return false
                }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            return true
        } catch {
            dlog("[TTS] chunk playback error: \(error.localizedDescription)")
            return false
        }
    }

    func playTTS(_ text: String) async {
        guard ttsEnabled else {
            // TTS vypnutý — přeskoč mluvení, rovnou pokračuj
            state = .idle
            return
        }

        let sentences = splitIntoSentences(text)
        guard !sentences.isEmpty else {
            state = .idle
            return
        }

        // Audio session setup jednou pro celé streamování
        do {
            let session = AVAudioSession.sharedInstance()
            if session.category != .playAndRecord {
                try session.setCategory(.playAndRecord, mode: .voiceChat, options: earpieceMode ? [] : [.defaultToSpeaker])
                try session.setActive(true)
            }
        } catch {
            dlog("[TTS] session setup error: \(error.localizedDescription)")
        }

        let selectedVoice = UserDefaults.standard.string(forKey: "nova_voice") ?? profile["voice"] ?? "cs-vlasta"
        dlog("[TTS] streaming \(sentences.count) sentence(s), voice: \(selectedVoice)")
        currentTTSText = text.lowercased()
        ttsInterrupted = false  // reset flag — barge-in ho nastaví na true během streamingu

        // Jediná věta → bez paralelizace, jeden fetch a play
        if sentences.count == 1 {
            if let data = await fetchTTSAudio(sentences[0]) {
                _ = await playTTSChunk(data)
            }
            audioPlayer = nil
            currentTTSText = ""
            return
        }

        // Streaming: paralelní fetch všech vět, sekvenční přehrávání
        var fetchTasks: [Task<Data?, Never>] = []
        for sentence in sentences {
            let task = Task<Data?, Never> { [weak self] in
                await self?.fetchTTSAudio(sentence)
            }
            fetchTasks.append(task)
        }

        for (idx, task) in fetchTasks.enumerated() {
            // Přerušení (toggle TTS off NEBO barge-in) → zruš zbytek a skonči
            if !ttsEnabled || ttsInterrupted {
                dlog("[TTS] streaming aborted at sentence \(idx + 1)/\(sentences.count) (ttsEnabled=\(ttsEnabled), interrupted=\(ttsInterrupted))")
                for t in fetchTasks[idx...] { t.cancel() }
                audioPlayer = nil
                currentTTSText = ""
                return
            }
            guard let data = await task.value else {
                dlog("[TTS] sentence \(idx + 1)/\(sentences.count) failed — skipping")
                continue
            }
            let played = await playTTSChunk(data)
            if !played {
                // playTTSChunk vrátí false jen při přerušení (ttsEnabled off, ttsInterrupted, error) → ukonči streaming
                dlog("[TTS] chunk \(idx + 1)/\(sentences.count) interrupted — aborting queue")
                for t in fetchTasks[(idx + 1)...] { t.cancel() }
                audioPlayer = nil
                currentTTSText = ""
                return
            }
        }

        audioPlayer = nil
        currentTTSText = ""
    }

    // MARK: - Conversation Mode (SpeechAnalyzer — iOS 26)
    // Tap orb = zapni konverzaci. Nova poslouchá continuous → odpoví → poslouchá dál.

    private var analyzer: SpeechAnalyzer?
    private var analyzerTask: Task<Void, Never>?
    private var silenceTask: Task<Void, Never>?
    private var currentUtterance = ""

    func toggleConversation() {
        HapticManager.shared.conversationToggle()
        if conversationActive {
            endConversation()
        } else {
            startConversation()
        }
    }

    func startConversation() {
        guard !isMuted else { return }
        guard !conversationActive else { return } // Prevent double-start
        // Demo režim — bez serveru nelze poslouchat ani odpovídat. Místo crashe ukaž jasnou hlášku.
        if demoMode {
            let info = Message(
                role: "ai",
                content: "Hlasová konverzace vyžaduje připojení k Nova serveru na Macu. V ukázkovém režimu si můžeš prohlédnout rozhraní, ale poslech a AI odpovědi se zapnou až po připojení."
            )
            messages.append(info)
            saveMessages()
            HapticManager.shared.novaResponseChord()
            return
        }
        // Wake word posluchač má vlastní AVAudioEngine + tap na input. Živá konverzace potřebuje
        // exkluzivní přístup k mikrofonu, takže wake word na chvíli pauzneme a po ukončení
        // konverzace (v endConversation) ho obnovíme.
        if wakeWord.isRunning {
            wakeWord.stop()
        }
        conversationActive = true
        updateLiveActivityForState()  // Start Dynamic Island
        if useWhisper && whisperState == .ready {
            whisper.languageHint = nil  // Live konverzace: auto-detect jazyka
            startWhisperListening()
        } else {
            // Live konverzace: auto-load Whisper pro auto-detect jazyka
            if !useWhisper {
                setUseWhisper(true)
            }
            startDictation()
        }
    }

    // MARK: - Push-to-Talk
    // Drž mic tlačítko → spustí SR, uvolnění → pošle finální text
    func startPushToTalk() {
        dlog("[ptt] startPushToTalk called — muted: \(isMuted), conversationActive: \(conversationActive), whisper: \(whisperState), useWhisper: \(useWhisper)")
        guard !isMuted else { dlog("[ptt] BLOCKED: muted"); return }
        guard !conversationActive else { dlog("[ptt] BLOCKED: conversation active"); return }
        HapticManager.shared.pushToTalkStart()
        pushToTalkActive = true
        currentUtterance = ""
        interimText = ""
        pttAccumulated = ""
        state = .listening
        if useWhisper && whisperState == .ready {
            // PTT: nastav jazyk podle uživatelského nastavení (auto-detect na krátkých větách selhává)
            let lang = UserDefaults.standard.string(forKey: "nova_lang") ?? "cs"
            whisper.languageHint = lang
            dlog("[ptt] using Whisper STT (lang: \(lang))")
            startWhisperListening()
        } else {
            dlog("[ptt] using DictationTranscriber fallback")
            startDictation()
        }
    }

    func endPushToTalk() {
        guard pushToTalkActive else { return }
        HapticManager.shared.pushToTalkEnd()
        pushToTalkActive = false

        // Zachovej interimText pro review v UI (dictation mode)
        let text = currentUtterance.trimmingCharacters(in: .whitespacesAndNewlines)

        // Stop recognition
        analyzerTask?.cancel()
        analyzerTask = nil
        analyzer = nil
        dictationTranscriber = nil
        silenceTask?.cancel()
        whisper.stopListening()
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)

        currentUtterance = ""
        // interimText zůstává — UI ho přečte pro dictation review
        // Pokud se nepoužívá dictation mode, vyčistí ho volající

        if text.isEmpty {
            dlog("[ptt] no text captured")
            interimText = ""
            state = .idle
        } else {
            dlog("[ptt] captured: \(text)")
            interimText = text  // Uchovej pro review
            state = .idle  // UI rozhodne co dál
        }
    }

    // MARK: - Whisper Management

    func setUseWhisper(_ enabled: Bool) {
        useWhisper = enabled
        if enabled && whisperState == .unloaded {
            Task { await loadWhisperModel() }
        }
    }

    func loadWhisperModel() async {
        // nil = device-aware auto selection (tiny/base pro SE, small+ pro novější)
        await whisper.loadModel(nil)
    }

    private func setupWhisperObservers() {
        // Mirror whisper state to NovaService published properties
        whisperStateObserver = whisper.$state.sink { [weak self] state in
            Task { @MainActor in
                self?.whisperState = state
            }
        }
        whisperProgressObserver = whisper.$loadProgress.sink { [weak self] progress in
            Task { @MainActor in
                self?.whisperLoadProgress = progress
            }
        }

        // Whisper raw audio → Voice ID ring buffer + VAD barge-in
        whisper.onRawAudio = { [weak self] samples in
            self?.appendToAudioRing(samples)
            // VAD barge-in: během TTS sleduj amplitude
            Task { @MainActor [weak self] in
                guard let self = self,
                      self.state == .speaking,
                      self.conversationActive else {
                    self?.bargeInVoiceStart = nil
                    return
                }
                // Spočítej RMS amplitude
                let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(max(samples.count, 1)))
                if rms > self.bargeInAmplitudeThreshold {
                    if self.bargeInVoiceStart == nil {
                        self.bargeInVoiceStart = Date()
                    } else if Date().timeIntervalSince(self.bargeInVoiceStart!) >= self.bargeInDurationThreshold {
                        // Uživatel mluví 100ms+ → barge-in
                        dlog("[barge-in] VAD detected user voice (RMS: \(String(format: "%.4f", rms))) — stopping TTS")
                        self.bargeInVoiceStart = nil
                        self.interruptAndListen()
                    }
                } else {
                    self.bargeInVoiceStart = nil
                }
            }
        }

        // Whisper transcript callback
        whisper.onTranscript = { [weak self] text, isFinal, language in
            guard let self = self else { return }
            Task { @MainActor in
                guard self.state == .listening else { return }
                if self.pushToTalkActive {
                    // PTT: akumuluj věty za sebe
                    if isFinal {
                        let accumulated = self.pttAccumulated.isEmpty
                            ? text
                            : self.pttAccumulated + " " + text
                        self.pttAccumulated = accumulated
                        self.currentUtterance = accumulated
                        self.interimText = accumulated
                        dlog("[whisper-ptt] accumulated: \(accumulated)")
                    } else {
                        // Interim: ukaž dosavadní + aktuální rozpracovanou
                        let preview = self.pttAccumulated.isEmpty
                            ? text
                            : self.pttAccumulated + " " + text
                        self.currentUtterance = preview
                        self.interimText = preview
                    }
                } else {
                    // Live konverzace — ignoruj transcripty když Nova přemýšlí/mluví
                    guard self.state == .listening else { return }
                    // Echo guard — krátké okno po restartu whisperu (rezidua echa).
                    // 0.8s stačí, protože před tím byla 1.2s pauza v sendMessage = celkem 2s mute.
                    guard Date().timeIntervalSince(self.listeningResumeTime) > 0.8 else { return }
                    self.currentUtterance = text
                    self.interimText = text
                    if isFinal {
                        dlog("[whisper] final (\(language ?? "?")): \(text)")
                        await self.handleUtteranceEnd()
                    }
                }
            }
        }
    }

    private func startWhisperListening() {
        do {
            try whisper.startListening()
            // WhisperService.startListening může tichounce returnnout (guard case .ready)
            // pokud state visí v .transcribing nebo .listening. Verifikuj, že fakticky běží.
            if whisper.state == .listening {
                state = .listening
                dlog("[whisper] listening started ✅")
            } else {
                dlog("[whisper] start was no-op (state: \(whisper.state)) — fallback na DictationTranscriber")
                startDictation()
            }
        } catch {
            dlog("[whisper] start error: \(error) — fallback na DictationTranscriber")
            startDictation()
        }
    }

    private func stopWhisperListening() {
        whisper.stopListening()
    }

    func endConversation() {
        conversationActive = false
        // Zastav TTS streaming + player
        ttsInterrupted = true
        audioPlayer?.stop()
        audioPlayer = nil
        // Zruš aktivní úlohy
        activeTask?.cancel()
        isSending = false
        isStreaming = false
        streamingText = ""
        thinkingStage = nil
        analyzerTask?.cancel()
        analyzerTask = nil
        analyzer = nil
        dictationTranscriber = nil
        silenceTask?.cancel()
        speechDebounceTask?.cancel()
        whisper.stopListening()
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        currentUtterance = ""
        interimText = ""
        state = .idle
        dlog("[speech] conversation ended")
        // Obnov wake word posluchače — aby mohl Ondřej hned říct "Hi Nova" znovu.
        if wakeWordEnabled && !wakeWord.isRunning {
            Task { await self.startWakeWordIfAllowed() }
        }
    }

    /// Přeruš TTS a začni poslouchat (VAD barge-in nebo tap na orb)
    func interruptAndListen() {
        dlog("[speech] INTERRUPT — stopping TTS, clearing buffer, restarting whisper")
        // Zastav TTS — flag musí být nastaven PŘED stop(), ať playTTS smyčka utne i frontu zbylých vět
        ttsInterrupted = true
        audioPlayer?.stop()
        audioPlayer = nil
        currentTTSText = ""
        // Zruš aktivní task (polling/TTS)
        activeTask?.cancel()
        isSending = false
        isStreaming = false
        streamingText = ""
        thinkingStage = nil
        currentUtterance = ""
        interimText = ""
        // Stop whisper → čeká 500ms (vyčistí audio buffer od echa) → restart
        whisper.stopListening()
        state = .thinking  // dočasný state během čištění
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms — echo vymizí
            guard self.conversationActive else { return }
            self.currentUtterance = ""
            self.interimText = ""
            if self.useWhisper {
                self.whisper.languageHint = nil
                self.startWhisperListening()
            } else {
                self.state = .listening
            }
            dlog("[speech] buffer cleared, listening again")
        }
    }

    func continueConversation() {
        guard conversationActive && !isMuted else {
            state = .idle
            return
        }
        // Vyčisti reziduální state z TTS období (echo prevention)
        currentUtterance = ""
        interimText = ""
        silenceTask?.cancel()
        silenceTask = nil

        // Hard reset whisperu — idempotentně srovná state na .ready, kdyby ještě
        // visel v .transcribing po canceled tasku. Bez tohohle by startListening
        // tichounce returnoval (guard case .ready) a Nova by neslyšela další turn.
        whisper.stopListening()

        // Reset audio session — TTS mohl nechat session v špatném stavu
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: earpieceMode ? [] : [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            dlog("[speech] audio session reset error: \(error)")
        }

        // Restartuj whisper (byl zastaven po TTS pro echo prevention)
        currentUtterance = ""
        interimText = ""
        listeningResumeTime = Date() // Ignoruj echo 0.8s po restartu (zkráceno z 2.0s, AEC + 1.2s post-TTS pauza stačí)
        if useWhisper {
            whisper.languageHint = nil
            startWhisperListening()
        } else {
            state = .listening
        }
        dlog("[speech] 🎤 listening resumed for next turn (whisper: \(whisper.state))")
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
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: earpieceMode ? [] : [.defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            dlog("[speech] audio session error: \(error)")
            return
        }

        let locale = Locale(identifier: speechLocale)
        dictationTranscriber = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
        guard let transcriber = dictationTranscriber else {
            dlog("[speech] DictationTranscriber init failed")
            return
        }
        analyzer = SpeechAnalyzer(modules: [transcriber])
        guard let analyzer = analyzer else {
            dlog("[speech] SpeechAnalyzer init failed")
            return
        }

        state = .listening
        currentUtterance = ""
        dlog("[speech] DictationTranscriber started (\(locale))")

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)

        analyzerTask = Task { [weak self] in
            do {
                guard let targetFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                    dlog("[speech] no compatible audio format")
                    return
                }
                let hwFormat = inputNode.inputFormat(forBus: 0)
                dlog("[speech] hw format: \(hwFormat), target format: \(targetFormat)")

                guard let converter = AVAudioConverter(from: hwFormat, to: targetFormat) else {
                    dlog("[speech] failed to create audio converter")
                    return
                }

                let inputStream = AsyncStream<AnalyzerInput> { [weak self] continuation in
                    // Pro voice verification: dodatečný 16kHz Float32 format
                    let verifyFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
                    let verifyConverter = AVAudioConverter(from: hwFormat, to: verifyFormat)

                    inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { buffer, _ in
                        // 1) Konverze pro DictationTranscriber (jeho formát)
                        let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * targetFormat.sampleRate / hwFormat.sampleRate)
                        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return }
                        var error: NSError?
                        converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                            outStatus.pointee = .haveData
                            return buffer
                        }
                        if error == nil {
                            continuation.yield(AnalyzerInput(buffer: convertedBuffer))
                        }

                        // 2) Duplicitní konverze do 16kHz Float32 pro voice ring buffer
                        if let verifyConverter = verifyConverter {
                            let verifyFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * 16000.0 / hwFormat.sampleRate)
                            if let verifyBuffer = AVAudioPCMBuffer(pcmFormat: verifyFormat, frameCapacity: verifyFrameCount) {
                                var verifyError: NSError?
                                verifyConverter.convert(to: verifyBuffer, error: &verifyError) { _, outStatus in
                                    outStatus.pointee = .haveData
                                    return buffer
                                }
                                if verifyError == nil, let floatData = verifyBuffer.floatChannelData?[0] {
                                    let samples = Array(UnsafeBufferPointer(start: floatData, count: Int(verifyBuffer.frameLength)))
                                    self?.appendToAudioRing(samples)
                                }
                            }
                        }
                    }
                    continuation.onTermination = { _ in
                        inputNode.removeTap(onBus: 0)
                    }
                }

                // Alokuj locale modely
                try await analyzer.prepareToAnalyze(in: targetFormat)
                dlog("[speech] analyzer prepared")

                self?.audioEngine.prepare()
                try self?.audioEngine.start()
                dlog("[speech] engine running: \(self?.audioEngine.isRunning ?? false)")

                // Čti výsledky souběžně
                let resultsTask = Task { [weak self] in
                    for try await result in transcriber.results {
                        guard !Task.isCancelled else { break }
                        let text = String(result.text.characters)
                        await MainActor.run {
                            guard let self = self else { return }
                            // Ignoruj transkripty během TTS (echo prevention)
                            guard self.state == .listening else { return }
                            self.currentUtterance = text
                            self.interimText = text
                            // V PTT módu auto-send nepoužíváme — text se pošle až po release
                            if !self.pushToTalkActive {
                                self.silenceTask?.cancel()
                                self.silenceTask = Task { @MainActor [weak self] in
                                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                                    guard !Task.isCancelled, let self = self else { return }
                                    guard self.state == .listening else { return }
                                    await self.handleUtteranceEnd()
                                }
                            }
                        }
                    }
                }

                try await analyzer.start(inputSequence: inputStream)

                // Čekej na resultsTask (nekanceluj — start() neblokuje)
                try? await resultsTask.value
            } catch {
                dlog("[speech] DictationTranscriber error: \(error)")
                await MainActor.run { self?.state = .idle }
            }
        }
    }

    private func handleUtteranceEnd() async {
        // Echo prevention — nezasílej pokud už probíhá zpracování nebo TTS
        guard state == .listening else {
            dlog("[speech] utterance ignored (state: \(state))")
            return
        }
        let text = currentUtterance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        currentUtterance = ""
        interimText = ""
        dlog("[speech] utterance end: \(text)")

        // Voice ID verifikace — pokud profil existuje a enforcement je ON
        if voiceVerificationEnforced && voiceProfile.state == .enrolled {
            let verified = await verifyRecentAudio()
            if !verified {
                dlog("[voice-id] ❌ verification failed — ignoring utterance")
                lastVerificationFailed = true
                HapticManager.shared.voiceVerificationFailed()
                // Zobraz červenou indikaci na ~2s
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    self.lastVerificationFailed = false
                }
                return
            }
            dlog("[voice-id] ✅ verified — proceeding with utterance")
            HapticManager.shared.voiceVerificationSuccess()
        }

        // NEZASTAVUJ analyzer — běží nepřetržitě, jen pošli text
        await sendMessage(text)
    }

    // MARK: - Audio Ring Buffer (for voice verification)

    /// Appends incoming audio samples to rolling buffer (thread-safe).
    /// Called from audio tap callback.
    /// Thread-safe ring buffer append — called from audio tap (realtime thread)
    nonisolated func appendToAudioRing(_ samples: [Float]) {
        audioRingBufferQueue.async { [weak self] in
            guard let self = self else { return }
            self._ringBuffer.append(contentsOf: samples)
            if self._ringBuffer.count > self.audioRingBufferMaxSize {
                let excess = self._ringBuffer.count - self.audioRingBufferMaxSize
                self._ringBuffer.removeFirst(excess)
            }
        }
    }

    /// Save last N seconds of audio ring buffer to a temporary WAV file.
    /// Returns file URL or nil if buffer is empty.
    private func saveRingBufferToWAV(seconds: Double = 3.0) -> URL? {
        let sampleRate: Double = 16000
        let targetSamples = Int(sampleRate * seconds)
        // Thread-safe read from ring buffer
        let ringSnapshot: [Float] = audioRingBufferQueue.sync { _ringBuffer }
        let samples: [Float]
        if ringSnapshot.count >= targetSamples {
            samples = Array(ringSnapshot.suffix(targetSamples))
        } else if ringSnapshot.count >= Int(sampleRate * 1.0) {
            samples = ringSnapshot  // alespoň 1s
        } else {
            return nil
        }

        // Write as 16-bit PCM WAV
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nova_verify_\(Date().timeIntervalSince1970).wav")

        var data = Data()
        // WAV header
        let pcmSampleCount = samples.count
        let byteRate = Int(sampleRate) * 2  // mono, 16-bit
        let dataSize = pcmSampleCount * 2

        func appendLE<T: FixedWidthInteger>(_ v: T, bytes: Int) {
            var value = v.littleEndian
            withUnsafeBytes(of: &value) { buf in
                data.append(buf.bindMemory(to: UInt8.self).baseAddress!, count: bytes)
            }
        }

        data.append("RIFF".data(using: .ascii)!)
        appendLE(UInt32(36 + dataSize), bytes: 4)
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        appendLE(UInt32(16), bytes: 4)           // fmt chunk size
        appendLE(UInt16(1), bytes: 2)            // PCM format
        appendLE(UInt16(1), bytes: 2)            // mono
        appendLE(UInt32(sampleRate), bytes: 4)   // sample rate
        appendLE(UInt32(byteRate), bytes: 4)     // byte rate
        appendLE(UInt16(2), bytes: 2)            // block align
        appendLE(UInt16(16), bytes: 2)           // bits per sample
        data.append("data".data(using: .ascii)!)
        appendLE(UInt32(dataSize), bytes: 4)

        // Float32 → Int16
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let int16Sample = Int16(clamped * 32767.0)
            appendLE(int16Sample, bytes: 2)
        }

        do {
            try data.write(to: url)
            return url
        } catch {
            dlog("[voice-id] failed to write WAV: \(error)")
            return nil
        }
    }

    /// Verify the most recent audio buffer against enrolled voice profile.
    /// Returns true if verification succeeds or if not enrolled (fail-open).
    private let livenessDetector = AudioLivenessDetector()

    private func verifyRecentAudio() async -> Bool {
        // 1. Anti-spoofing — liveness check (FAST, on-device)
        let ringSnapshot: [Float] = audioRingBufferQueue.sync { _ringBuffer }
        let recentSamples = Array(ringSnapshot.suffix(Int(16000 * 3.0)))
        if recentSamples.count >= 16000 {
            let liveness = livenessDetector.analyze(samples: recentSamples)
            dlog("[liveness] flatness=\(String(format: "%.3f", liveness.spectralFlatness)) variance=\(String(format: "%.4f", liveness.energyVariance)) rmsCV=\(String(format: "%.3f", liveness.rmsCV)) → live=\(liveness.isLive)")

            if !liveness.isLive {
                dlog("[voice-id] ❌ liveness check failed: \(liveness.reason ?? "unknown")")
                return false
            }
        }

        // 2. Speaker verification (Mac server ECAPA-TDNN)
        guard let wavURL = saveRingBufferToWAV(seconds: 3.0) else {
            dlog("[voice-id] no audio in ring buffer for verification")
            return false  // fail-close: bez audia nepustím nikoho
        }
        defer {
            try? FileManager.default.removeItem(at: wavURL)
        }
        let result = await voiceProfile.verify(audioFileURL: wavURL, strict: false)
        return result.verified
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

    func toggleTTS() {
        ttsEnabled.toggle()
        UserDefaults.standard.set(ttsEnabled, forKey: "nova_tts_enabled")
        // Okamžitě zastav přehrávání pokud se TTS vypíná
        if !ttsEnabled {
            audioPlayer?.stop()
            audioPlayer = nil
            if state == .speaking { state = .idle }
        }
    }

    // MARK: - WebSocket
    private var wsSession: URLSession?
    private var isReconnecting = false
    private var wsReconnectCount = 0
    private let wsMaxReconnects = 5

    func connectWebSocket() {
        // WS disabled — používáme HTTP polling. Dead code below kept for possible future revival.
        return
    }

    #if false
    private func _connectWebSocketImpl() {
        guard !serverURL.isEmpty, !isReconnecting, wsReconnectCount < wsMaxReconnects else { return }
        isReconnecting = true

        // Clean up previous connection
        webSocket?.cancel(with: .goingAway, reason: nil)
        wsSession?.invalidateAndCancel()

        // Prefix-only scheme replacement (http→ws, https→wss)
        let wsURL: String
        if serverURL.hasPrefix("https") {
            wsURL = "wss" + serverURL.dropFirst(5)
        } else {
            wsURL = "ws" + serverURL.dropFirst(4)
        }
        guard let url = URL(string: "\(wsURL)?token=\(token)") else {
            isReconnecting = false
            return
        }
        dlog("[ws] connecting to: \(url.absoluteString)")

        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: config)
        wsSession = session
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        webSocket = session.webSocketTask(with: request)
        webSocket?.resume()
        isReconnecting = false
        // isConnected set to true after first successful receive
        receiveWebSocket()
    }
    #endif

    private func receiveWebSocket() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                Task { @MainActor in
                    // Mark connected after first successful receive
                    if self?.isConnected == false {
                        self?.isConnected = true
                        self?.wsReconnectCount = 0
                    }
                }
                if case .string(let text) = message,
                   let data = text.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    Task { @MainActor in
                        self?.handleWSMessage(json)
                    }
                }
                Task { @MainActor in
                    self?.receiveWebSocket()
                }
            case .failure(let error):
                Task { @MainActor in
                    if self?.isConnected != false { self?.isConnected = false }
                    self?.wsReconnectCount += 1
                    dlog("[ws] receive failed (\(self?.wsReconnectCount ?? 0)/\(self?.wsMaxReconnects ?? 3)): \(error.localizedDescription)")
                    // Resume pending stream continuation only if one exists (user was waiting for response)
                    if let completion = self?.streamCompletion {
                        completion.resume(throwing: NSError(domain: "nova.ws", code: -1, userInfo: [NSLocalizedDescriptionKey: "Spojení se serverem se přerušilo"]))
                        self?.streamCompletion = nil
                    }
                    guard (self?.wsReconnectCount ?? 99) < (self?.wsMaxReconnects ?? 3) else {
                        dlog("[ws] max reconnects reached, stopping")
                        return
                    }
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
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
        case "stage":
            if let key = json["key"] as? String {
                let detail = json["detail"] as? String
                let newStage = ThinkingStage(key: key, detail: detail)
                if thinkingStage != newStage {
                    thinkingStage = newStage
                    HapticManager.shared.selectionChanged()
                    updateLiveActivityForState()
                }
            } else {
                thinkingStage = nil
            }
        case "stream-start":
            if let rid = json["requestId"] as? String, rid == activeRequestId {
                isStreaming = true
                streamingText = ""
                state = .thinking
            }
        case "stream-token":
            if let rid = json["requestId"] as? String, rid == activeRequestId,
               let token = json["token"] as? String {
                streamingText += token
                // Po prvním tokenu přepneme stav — už máme text
                if !isStreaming { isStreaming = true }
            }
        case "stream-end":
            if let rid = json["requestId"] as? String, rid == activeRequestId,
               let text = json["text"] as? String {
                streamCompletion?.resume(returning: text)
                streamCompletion = nil
            }
        case "stream-replace":
            // Server detekoval JSON akci — nahraď ošklivý JSON čistým textem
            if let rid = json["requestId"] as? String, rid == activeRequestId,
               let cleanText = json["text"] as? String {
                streamingText = cleanText
                streamReplacedText = cleanText  // Pro TTS — přečte speech, ne JSON
            }
        case "stream-error":
            if let rid = json["requestId"] as? String, rid == activeRequestId {
                let errorText = json["error"] as? String ?? "Stream error"
                streamCompletion?.resume(throwing: NSError(domain: "nova.stream", code: -1, userInfo: [NSLocalizedDescriptionKey: errorText]))
                streamCompletion = nil
            }
        case "stream-action":
            if let rid = json["requestId"] as? String, rid == activeRequestId,
               let actionData = json["action"] {
                // Akce přijde po stream-end, zpracuje se v sendMessage flow
                if let actionJson = try? JSONSerialization.data(withJSONObject: actionData),
                   let action = try? JSONDecoder().decode(ActionResponse.self, from: actionJson) {
                    Task { await handleAction(action) }
                }
            }
        default: break
        }
    }

    // MARK: - Dev Mode
    private func executeDevAction(_ action: ActionResponse) async {
        isDevMode = true
        defer { isDevMode = false }
        do {
            let task = action.params?["task"]?.value as? String ?? ""
            let devMessages = messages.suffix(50).map { ["role": $0.role == "user" ? "user" : "assistant", "content": $0.content] } + [["role": "user", "content": task]]

            // Step 1: Plan
            guard let planURL = URL(string: "\(serverURL)/api/dev/plan") else { return }
            var planRequest = URLRequest(url: planURL)
            planRequest.httpMethod = "POST"
            planRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            planRequest.setValue(token, forHTTPHeaderField: "X-Nova-Token")
            // Auto-detection: server sám pozná projekt z kontextu zpráv
            planRequest.httpBody = try JSONSerialization.data(withJSONObject: ["messages": devMessages])
            planRequest.timeoutInterval = 600

            let (planData, _) = try await URLSession.shared.data(for: planRequest)
            let planJson = try JSONSerialization.jsonObject(with: planData) as? [String: Any]

            let planContent: String
            let needsConfirm: Bool

            // Async flow: server vrací {streaming: true, requestId}
            if planJson?["streaming"] as? Bool == true,
               let requestId = planJson?["requestId"] as? String {
                needsConfirm = planJson?["needsConfirm"] as? Bool ?? true
                pendingConfirmToken = planJson?["confirmToken"] as? String
                thinkingStage = ThinkingStage(key: "analyzing", detail: nil)
                state = .thinking
                planContent = try await pollForResponse(requestId: requestId)
            } else {
                planContent = planJson?["content"] as? String ?? "Nemůžu navrhnout plán."
                needsConfirm = planJson?["needsConfirm"] as? Bool ?? true
                pendingConfirmToken = planJson?["confirmToken"] as? String
            }

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
    var pendingConfirmToken: String?

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

            guard let execURL = URL(string: "\(serverURL)/api/dev/execute") else { return }
            var execRequest = URLRequest(url: execURL)
            execRequest.httpMethod = "POST"
            execRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            execRequest.setValue(token, forHTTPHeaderField: "X-Nova-Token")
            // Auto-detection: server sám pozná projekt z kontextu zpráv
            var execPayload: [String: Any] = ["messages": devMsgs]
            if let confirmToken = pendingConfirmToken {
                execPayload["confirmToken"] = confirmToken
                pendingConfirmToken = nil
            }
            execRequest.httpBody = try JSONSerialization.data(withJSONObject: execPayload)
            execRequest.timeoutInterval = 600

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

    // MARK: - Live Activity (Dynamic Island)
    private func updateLiveActivityForState() {
        if #available(iOS 16.2, *) {
            if conversationActive {
                // Voice konverzace — Dynamic Island aktivní
                let label: String
                switch state {
                case .listening: label = L10n.t("listening")
                case .thinking: label = L10n.t("thinking")
                case .speaking: label = L10n.t("speaking")
                case .idle: label = L10n.t("ready")
                }

                if LiveActivityManager.shared.isActive {
                    LiveActivityManager.shared.update(state: state.rawValue, label: label)
                } else {
                    LiveActivityManager.shared.startVoiceConversation(state: state.rawValue, label: label)
                }
            } else {
                // Konverzace skončila — ukliď Dynamic Island
                if LiveActivityManager.shared.isActive {
                    LiveActivityManager.shared.end()
                }
            }
        }
    }
}
