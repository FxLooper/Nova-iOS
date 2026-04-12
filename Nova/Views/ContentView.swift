import SwiftUI
import PhotosUI

struct ContentView: View {
    @EnvironmentObject var nova: NovaService

    var body: some View {
        if nova.isConfigured && !nova.needsSetup {
            ChatView()
        } else {
            SetupView()
        }
    }
}

// MARK: - Setup View (first launch — premium welcome)
struct SetupView: View {
    @EnvironmentObject var nova: NovaService
    @State private var server = "http://192.168.0.183:3000"
    @State private var token = ""
    @State private var step: Int = 0  // 0=welcome, 1=connection
    @State private var orbScale: CGFloat = 0.8
    @State private var orbOpacity: Double = 0

    var body: some View {
        ZStack {
            NovaBackground()

            if step == 0 {
                welcomeStep
            } else {
                connectionStep
            }
        }
        .animation(.easeInOut(duration: 0.5), value: step)
    }

    // Krok 1: Welcome screen — premium first impression
    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer()

            // Animated orb logo — same orb as in main app
            OrbView(state: .idle, audioLevel: 0)
                .frame(width: 200, height: 200)
                .scaleEffect(orbScale)
                .opacity(orbOpacity)
                .onAppear {
                    withAnimation(.easeOut(duration: 1.5)) {
                        orbScale = 1.0
                        orbOpacity = 1.0
                    }
                }

            Spacer().frame(height: 40)

            VStack(spacing: 12) {
                Text("nova")
                    .font(.system(size: 48, weight: .light))
                    .tracking(14)
                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.85))

                Text("Tvoje osobní AI asistentka")
                    .font(.system(size: 15, weight: .light))
                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))
            }

            Spacer()

            // Feature highlights
            VStack(alignment: .leading, spacing: 16) {
                welcomeFeature(icon: "waveform.circle", text: "Hlasová konverzace v 16 jazycích")
                welcomeFeature(icon: "lock.shield.fill", text: "Voice ID — Nova pozná tvůj hlas")
                welcomeFeature(icon: "lock.icloud", text: "100% privátní, žádný cloud")
                welcomeFeature(icon: "bolt.heart", text: "Premium UX s haptic feedback")
            }
            .padding(.horizontal, 40)

            Spacer()

            Button(action: {
                HapticManager.shared.selectionChanged()
                withAnimation { step = 1 }
            }) {
                Text("Začít")
                    .font(.system(size: 16, weight: .medium))
                    .tracking(2)
                    .foregroundColor(Color(hex: "f5f0e8"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(hex: "1a1a2e").opacity(0.85))
                    .cornerRadius(999)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
    }

    private func welcomeFeature(icon: String, text: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .light))
                .foregroundColor(Color(hex: "1a1a2e").opacity(0.6))
                .frame(width: 28)
            Text(text)
                .font(.system(size: 14, weight: .light))
                .foregroundColor(Color(hex: "1a1a2e").opacity(0.7))
            Spacer()
        }
    }

    // Krok 2: Connection setup
    private var connectionStep: some View {
        VStack(spacing: 32) {
            Spacer()

            Text("nova")
                .font(.system(size: 36, weight: .light))
                .tracking(10)
                .foregroundColor(Color(hex: "1a1a2e").opacity(0.85))

            VStack(spacing: 8) {
                Text("Připojení k Mac serveru")
                    .font(.system(size: 18, weight: .light))
                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.7))

                Text("Tvůj Mac server běží Claude Code")
                    .font(.system(size: 13, weight: .light))
                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.45))
            }

            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Server URL")
                        .font(.system(size: 11, weight: .medium))
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundColor(Color(hex: "1a1a2e").opacity(0.4))
                    TextField("http://100.105.26.7:3000", text: $server)
                        .textFieldStyle(NovaTextFieldStyle())
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("API Token")
                        .font(.system(size: 11, weight: .medium))
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundColor(Color(hex: "1a1a2e").opacity(0.4))
                    SecureField("z keychain: NOVA_API_TOKEN", text: $token)
                        .textFieldStyle(NovaTextFieldStyle())
                }
            }
            .padding(.horizontal, 40)

            Spacer()

            VStack(spacing: 12) {
                Button(action: {
                    HapticManager.shared.selectionChanged()
                    nova.configure(server: server, token: token)
                }) {
                    Text("Připojit")
                        .font(.system(size: 16, weight: .medium))
                        .tracking(2)
                        .foregroundColor(Color(hex: "f5f0e8"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(hex: "1a1a2e").opacity(0.85))
                        .cornerRadius(999)
                }
                .disabled(server.isEmpty || token.isEmpty)
                .opacity(server.isEmpty || token.isEmpty ? 0.4 : 1)

                Button(action: {
                    withAnimation { step = 0 }
                }) {
                    Text("Zpět")
                        .font(.system(size: 13, weight: .light))
                        .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Chat View
struct ChatView: View {
    @EnvironmentObject var nova: NovaService
    @State private var inputText = ""
    @State private var showSettings = false
    @FocusState private var isInputFocused: Bool

    // Voice-to-Text Dictation states
    enum DictationState {
        case idle       // Normal input bar
        case dictating  // Recording, live transcript
        case review     // Stopped, editable text, send button
    }
    @State private var dictationState: DictationState = .idle
    @State private var dictatedText = ""
    @State private var recordingPulse = false
    @State private var showCamera = false
    @State private var showVoiceConversation = false

    var body: some View {
        ZStack {
            NovaBackground()

            VStack(spacing: 0) {
                // Header: nova title above orb + state label
                VStack(spacing: 0) {
                    // Top bar: settings + mute
                    HStack {
                        Button(action: { showSettings = true }) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 14, weight: .light))
                                .foregroundColor(Color(hex: "1a1a2e").opacity(0.25))
                        }
                        Spacer()
                        Button(action: { nova.toggleMute() }) {
                            Image(systemName: nova.isMuted ? "mic.slash" : "mic")
                                .font(.system(size: 16, weight: .light))
                                .foregroundColor(Color(hex: "1a1a2e").opacity(nova.isMuted ? 0.6 : 0.25))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                    // Nova title centered above orb + server health dot
                    HStack(spacing: 8) {
                        Text("nova")
                            .font(.system(size: 22, weight: .ultraLight))
                            .tracking(10)
                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.55))

                        Circle()
                            .fill(serverHealthColor)
                            .frame(width: 6, height: 6)
                            .opacity(0.8)
                            .animation(.easeInOut(duration: 0.5), value: nova.serverHealth.status)
                    }

                    // Orb (Three.js — identický jako desktop)
                    OrbWebView(state: nova.state.rawValue, audioLevel: 0)
                        .frame(height: 180)
                        .onTapGesture {
                            showVoiceConversation = true
                        }
                        .contextMenu {
                            Button {
                                nova.toggleMute()
                                HapticManager.shared.selectionChanged()
                            } label: {
                                Label(nova.isMuted ? "Zrušit ztlumení" : "Ztlumit Novu",
                                      systemImage: nova.isMuted ? "speaker.wave.2" : "speaker.slash")
                            }

                            Button {
                                showVoiceConversation = true
                            } label: {
                                Label("Hlasová konverzace", systemImage: "waveform")
                            }

                            Button {
                                showSettings = true
                            } label: {
                                Label("Nastavení", systemImage: "gearshape")
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Začít hlasovou konverzaci s Novou")
                        .accessibilityHint("Klepnutím otevři hlasový režim. Dlouhým podržením otevři menu.")
                        .accessibilityAddTraits(.isButton)

                    // State label pod orbem
                    Text(stateLabel)
                        .font(.system(size: 11, weight: .light))
                        .tracking(3)
                        .foregroundColor(Color(hex: "1a1a2e").opacity(nova.state == .idle ? 0.2 : 0.45))
                        .padding(.bottom, 4)
                        .animation(.easeInOut(duration: 0.3), value: nova.state)

                    // Voice ID verification feedback
                    if nova.lastVerificationFailed {
                        HStack(spacing: 6) {
                            Image(systemName: "person.crop.circle.badge.xmark")
                                .font(.system(size: 11))
                            Text("Hlas nepoznán")
                                .font(.system(size: 11, weight: .medium))
                                .tracking(2)
                        }
                        .foregroundColor(.red.opacity(0.8))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.1))
                        .clipShape(Capsule())
                        .padding(.bottom, 8)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.8)),
                            removal: .opacity
                        ))
                    } else {
                        Spacer().frame(height: 8)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: nova.lastVerificationFailed)
                .background(.ultraThinMaterial)

                Divider().opacity(0.15)

                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            // Empty state — welcome screen když nejsou žádné zprávy
                            if nova.messages.isEmpty && nova.interimText.isEmpty {
                                emptyWelcomeView
                                    .padding(.top, 40)
                                    .padding(.horizontal, 32)
                            }

                            ForEach(nova.messages) { msg in
                                MessageBubble(message: msg)
                                    .id(msg.id)
                            }

                            // Interim speech text (PTT dictation preview)
                            if !nova.interimText.isEmpty && dictationState == .dictating {
                                HStack {
                                    Text(nova.interimText)
                                        .font(.system(size: 14, weight: .light))
                                        .foregroundColor(Color(hex: "1a1a2e").opacity(0.3))
                                        .italic()
                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                            }

                            // Confirm buttons
                            if nova.pendingConfirmation != nil {
                                ConfirmButtons(yesLabel: "Ano", noLabel: "Ne") { confirmed in
                                    Task { await nova.confirmAction(confirmed) }
                                }
                                .padding(.horizontal, 20)
                            }

                            // Streaming AI response — premium live typing
                            if nova.isStreaming && !nova.streamingText.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    // Streaming text bubble s typing kurzorem
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Nova")
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(Color(hex: "1a1a2e").opacity(0.3))

                                            StreamingTextView(text: nova.streamingText)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 10)
                                                .background(Color(hex: "1a1a2e").opacity(0.03))
                                                .cornerRadius(16)
                                        }
                                        Spacer(minLength: 60)
                                    }
                                    .padding(.horizontal, 16)

                                    // Kompaktní stage bar pod streaming textem
                                    if nova.thinkingStage != nil {
                                        CompactStageBar()
                                            .transition(.asymmetric(
                                                insertion: .opacity.combined(with: .move(edge: .top)),
                                                removal: .opacity
                                            ))
                                    }
                                }
                                .id("streaming-bubble")
                            }

                            // Thinking bubble — Zen spinner PŘED streamingem (čekáme na první token)
                            if nova.state == .thinking && !nova.isStreaming {
                                ThinkingBubbleView()
                                    .id("thinking-bubble")
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.92).combined(with: .opacity),
                                        removal: .scale(scale: 0.85).combined(with: .opacity)
                                    ))
                            }
                        }
                        .padding(.vertical, 16)
                        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: nova.state)
                        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: nova.thinkingStage)
                    }
                    .onAppear {
                        if let last = nova.messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                    .onChange(of: nova.messages.count) {
                        if let last = nova.messages.last {
                            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: nova.state) { _, newState in
                        if newState == .thinking {
                            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                                proxy.scrollTo("thinking-bubble", anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: nova.streamingText) {
                        if nova.isStreaming {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                proxy.scrollTo("streaming-bubble", anchor: .bottom)
                            }
                        }
                    }
                }

                Divider().opacity(0.15)

                // ─── Premium Input Bar ──────────────────────────────────
                VStack(spacing: 0) {
                    // Dictation live transcript bar (appears above input when dictating)
                    if dictationState == .dictating && !nova.interimText.isEmpty {
                        HStack(spacing: 8) {
                            // Recording pulse indicator
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                                .opacity(recordingPulse ? 1.0 : 0.3)
                                .onAppear {
                                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                                        recordingPulse = true
                                    }
                                }

                            ScrollView(.horizontal, showsIndicators: false) {
                                Text(nova.interimText)
                                    .font(.system(size: 14, weight: .light))
                                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.6))
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }

                    // Main input bar — changes based on state
                    HStack(spacing: 12) {
                        switch dictationState {
                        case .idle:
                            // ── IDLE: [TextField] [Mic 🎙 / Send ▶] ──
                            // Text input
                            TextField(L10n.t("write_nova"), text: $inputText)
                                .font(.system(size: 15, weight: .light))
                                .focused($isInputFocused)
                                .onSubmit { sendText() }

                            if inputText.isEmpty {
                                // Mic button — tap to start dictation (PTT)
                                Button(action: { startDictation() }) {
                                    Image(systemName: "mic")
                                        .font(.system(size: 22))
                                        .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))
                                        .frame(width: 36, height: 36)
                                }
                            } else {
                                // Send button (when text typed)
                                Button(action: { sendText() }) {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.system(size: 28))
                                        .foregroundColor(Color(hex: "1a1a2e").opacity(0.7))
                                }
                            }

                        case .dictating:
                            // ── DICTATING: [Cancel] [Live text] [Stop] ──
                            Button(action: { cancelDictation() }) {
                                Image(systemName: "xmark.circle")
                                    .font(.system(size: 24))
                                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.4))
                            }

                            // Live transcript (scrollable, growing)
                            Text(nova.interimText.isEmpty ? "Mluvte..." : nova.interimText)
                                .font(.system(size: 15, weight: .light))
                                .foregroundColor(nova.interimText.isEmpty
                                    ? Color(hex: "1a1a2e").opacity(0.25)
                                    : Color(hex: "1a1a2e").opacity(0.7))
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            // Stop button (pulsing red)
                            Button(action: { stopDictation() }) {
                                ZStack {
                                    Circle()
                                        .fill(Color.red.opacity(0.15))
                                        .frame(width: 36, height: 36)
                                    Circle()
                                        .fill(Color.red.opacity(0.8))
                                        .frame(width: 14, height: 14)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                            }

                        case .review:
                            // ── REVIEW: [Cancel] [Editable text] [Send ▶] ──
                            Button(action: { cancelDictation() }) {
                                Image(systemName: "xmark.circle")
                                    .font(.system(size: 24))
                                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.4))
                            }

                            // Editable text field with dictated content
                            TextField("", text: $dictatedText)
                                .font(.system(size: 15, weight: .light))
                                .foregroundColor(Color(hex: "1a1a2e").opacity(0.8))
                                .focused($isInputFocused)
                                .onSubmit { sendDictatedText() }
                                .onAppear { isInputFocused = true }

                            // Send button
                            Button(action: { sendDictatedText() }) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(dictatedText.isEmpty
                                        ? Color(hex: "1a1a2e").opacity(0.15)
                                        : Color(hex: "1a1a2e").opacity(0.7))
                            }
                            .disabled(dictatedText.isEmpty)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: dictationState)
                }
                .background(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(Color(hex: "1a1a2e").opacity(0.08)),
                    alignment: .top
                )
            }
        }
        .onAppear {
            nova.connectWebSocket()
        }
        .fullScreenCover(isPresented: $showVoiceConversation) {
            VoiceConversationView(isPresented: $showVoiceConversation)
                .environmentObject(nova)
        }
        .fullScreenCover(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(nova)
        }
        .sheet(isPresented: $showCamera) {
            CameraCaptureView { image in
                showCamera = false
                guard let image = image else { return }
                // TODO: Send image to Nova for analysis
                // For now: save to message context
                Task {
                    await nova.sendMessage("[Fotka pořízena — popis: \(image.size.width)x\(image.size.height)]")
                }
            }
        }
    }

    private var stateLabel: String {
        switch nova.state {
        case .idle: return L10n.t("ready")
        case .listening: return L10n.t("listening")
        case .thinking: return L10n.t("thinking")
        case .speaking: return L10n.t("speaking")
        }
    }

    private var serverHealthColor: Color {
        switch nova.serverHealth.status {
        case .online:
            return .green
        case .degraded:
            return .yellow
        case .offline:
            return .red
        case .unknown:
            return Color(hex: "1a1a2e").opacity(0.2)
        }
    }

    // MARK: - Empty State

    private var personalizedGreeting: String {
        let userName = UserDefaults.standard.string(forKey: "nova_user_name") ?? ""
        let vocative = L10n.vocative(userName)
        let nameSuffix = vocative.isEmpty ? "" : ", \(vocative)"

        let hour = Calendar.current.component(.hour, from: Date())
        let timeGreeting: String
        switch hour {
        case 5..<10:
            timeGreeting = "Dobré ráno"
        case 10..<12:
            timeGreeting = "Krásné dopoledne"
        case 12..<14:
            timeGreeting = "Krásné poledne"
        case 14..<18:
            timeGreeting = "Hezké odpoledne"
        case 18..<22:
            timeGreeting = "Dobrý večer"
        default:
            timeGreeting = "Dobrou noc"
        }

        return "\(timeGreeting)\(nameSuffix)"
    }

    private var emptyWelcomeView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text(personalizedGreeting)
                    .font(.system(size: 22, weight: .light))
                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.75))
                    .multilineTextAlignment(.center)

                Text("Co dnes potřebuješ?")
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.45))
            }

            // Quick action chips — predesignované prompty
            VStack(spacing: 8) {
                Text("Zkus říct nebo napsat")
                    .font(.system(size: 11, weight: .light))
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.4))

                quickActionChip(text: "Jaké je počasí v Plzni?", icon: "cloud.sun")
                quickActionChip(text: "Přečti mi nejnovější zprávy", icon: "newspaper")
                quickActionChip(text: "Co dávají dnes v kině?", icon: "film")
                quickActionChip(text: "Kolik je hodin?", icon: "clock")
            }
            .padding(.top, 4)

            // Quick hints
            VStack(alignment: .leading, spacing: 12) {
                emptyStateHint(icon: "circle.fill", text: "Tap orb pro hlasovou konverzaci")
                emptyStateHint(icon: "mic.fill", text: "Drž mic pro Push-to-Talk")
                emptyStateHint(icon: "lock.shield.fill", text: "Voice ID v Nastavení pro bezpečnost")
            }
            .padding(.top, 16)

            Spacer().frame(height: 20)
        }
    }

    private func quickActionChip(text: String, icon: String) -> some View {
        Button(action: {
            HapticManager.shared.selectionChanged()
            inputText = text
            sendText()
        }) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .light))
                Text(text)
                    .font(.system(size: 14, weight: .light))
                Spacer()
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 13, weight: .light))
                    .opacity(0.4)
            }
            .foregroundColor(Color(hex: "1a1a2e").opacity(0.7))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.6))
            .cornerRadius(12)
        }
    }

    private func emptyStateHint(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .light))
                .foregroundColor(Color(hex: "1a1a2e").opacity(0.4))
                .frame(width: 16)
            Text(text)
                .font(.system(size: 13, weight: .light))
                .foregroundColor(Color(hex: "1a1a2e").opacity(0.55))
            Spacer()
        }
    }

    private func sendText() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        isInputFocused = false
        Task { await nova.sendMessage(text) }
    }

    // MARK: - Dictation Controls

    private func startDictation() {
        dictationState = .dictating
        dictatedText = ""
        recordingPulse = false
        HapticManager.shared.pushToTalkStart()
        nova.startPushToTalk()
    }

    private func stopDictation() {
        // Stop recording, keep text for review
        nova.endPushToTalk()
        dictatedText = nova.interimText.trimmingCharacters(in: .whitespacesAndNewlines)
        HapticManager.shared.selectionChanged()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            dictationState = .review
        }
    }

    private func cancelDictation() {
        nova.endPushToTalk()
        dictatedText = ""
        HapticManager.shared.selectionChanged()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            dictationState = .idle
        }
    }

    private func sendDictatedText() {
        let text = dictatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        dictatedText = ""
        isInputFocused = false
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            dictationState = .idle
        }
        Task { await nova.sendMessage(text) }
    }
}

// MARK: - Message Bubble
struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.role == "user" { Spacer(minLength: 60) }

            VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 4) {
                Text(message.role == "user" ? L10n.t("you") : "Nova")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.3))

                // Markdown rendering pro AI, plain text pro user
                Group {
                    if message.role != "user", let md = try? AttributedString(markdown: message.content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                        Text(md)
                    } else {
                        Text(message.content)
                    }
                }
                .font(.system(size: 15, weight: .light))
                .foregroundColor(Color(hex: "1a1a2e").opacity(0.8))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    message.role == "user"
                        ? Color(hex: "1a1a2e").opacity(0.06)
                        : Color(hex: "1a1a2e").opacity(0.03)
                )
                .cornerRadius(16)
                .textSelection(.enabled)
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = message.content
                    } label: {
                        Label("Kopírovat", systemImage: "doc.on.doc")
                    }
                    ShareLink(item: message.content) {
                        Label("Sdílet", systemImage: "square.and.arrow.up")
                    }
                }

                Text(timeString)
                    .font(.system(size: 10, weight: .light))
                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.2))
            }

            if message.role != "user" { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 16)
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: message.timestamp)
    }
}

// MARK: - Streaming Text with Typing Cursor
struct StreamingTextView: View {
    let text: String
    @State private var cursorVisible = true

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            Text(text)
                .font(.system(size: 15, weight: .light))
                .foregroundColor(Color(hex: "1a1a2e").opacity(0.8))
                .textSelection(.enabled)

            // Blikající kurzor
            RoundedRectangle(cornerRadius: 1)
                .fill(Color(hex: "1a1a2e").opacity(cursorVisible ? 0.5 : 0))
                .frame(width: 2, height: 16)
                .padding(.leading, 1)
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: cursorVisible)
                .onAppear { cursorVisible = false }
        }
    }
}

// MARK: - Compact Stage Bar (pod streaming bublinou)
struct CompactStageBar: View {
    @EnvironmentObject var nova: NovaService

    private var label: String {
        L10n.stage(nova.thinkingStage?.key, detail: nova.thinkingStage?.detail)
    }

    private var transitionId: String {
        "\(nova.thinkingStage?.key ?? "")|\(nova.thinkingStage?.detail ?? "")"
    }

    var body: some View {
        HStack(spacing: 8) {
            // Mini spinner
            Circle()
                .trim(from: 0, to: 0.25)
                .stroke(
                    Color(hex: "1a1a2e").opacity(0.35),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                )
                .frame(width: 12, height: 12)
                .rotationEffect(.degrees(rotation))
                .onAppear {
                    withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }

            Text(label)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundColor(Color(hex: "1a1a2e").opacity(0.4))
                .lineLimit(1)
                .truncationMode(.tail)
                .id(transitionId)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .leading)),
                    removal: .opacity
                ))

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 4)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: transitionId)
    }

    @State private var rotation: Double = 0
}

// MARK: - Styles
struct NovaTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: 15, weight: .light))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(hex: "1a1a2e").opacity(0.04))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(hex: "1a1a2e").opacity(0.08), lineWidth: 1)
            )
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        r = Double((int >> 16) & 0xFF) / 255
        g = Double((int >> 8) & 0xFF) / 255
        b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
