import SwiftUI

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
            Color(hex: "f5f0e8").ignoresSafeArea()

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

            // Animated orb logo
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hex: "1a1a2e").opacity(0.15),
                                Color(hex: "1a1a2e").opacity(0.02)
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 100
                        )
                    )
                    .frame(width: 200, height: 200)
                    .scaleEffect(orbScale)
                    .opacity(orbOpacity)

                Image(systemName: "sparkles")
                    .font(.system(size: 50, weight: .ultraLight))
                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.6))
                    .opacity(orbOpacity)
            }
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

    var body: some View {
        ZStack {
            Color(hex: "f5f0e8").ignoresSafeArea()

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
                            nova.toggleConversation()
                        }
                        .contextMenu {
                            Button {
                                nova.toggleMute()
                                HapticManager.shared.selectionChanged()
                            } label: {
                                Label(nova.isMuted ? "Zrušit ztlumení" : "Ztlumit Novu",
                                      systemImage: nova.isMuted ? "speaker.wave.2" : "speaker.slash")
                            }

                            if nova.conversationActive {
                                Button(role: .destructive) {
                                    nova.endConversation()
                                    HapticManager.shared.conversationToggle()
                                } label: {
                                    Label("Ukončit konverzaci", systemImage: "phone.down")
                                }
                            }

                            Button {
                                showSettings = true
                            } label: {
                                Label("Nastavení", systemImage: "gearshape")
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(nova.conversationActive ? "Zastavit konverzaci s Novou" : "Začít hlasovou konverzaci s Novou")
                        .accessibilityHint("Klepnutím spustíš nebo zastavíš hlasový režim. Dlouhým podržením otevři menu.")
                        .accessibilityValue(nova.state.rawValue)
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
                .background(Color(hex: "f5f0e8").opacity(0.95))

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

                            // Interim speech text
                            if !nova.interimText.isEmpty {
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

                            // Thinking indicator
                            if nova.state == .thinking {
                                HStack {
                                    ThinkingDots()
                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                        .padding(.vertical, 16)
                    }
                    .onAppear {
                        if let last = nova.messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                    .onChange(of: nova.messages.count) {
                        if let last = nova.messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                Divider().opacity(0.15)

                // Input bar
                HStack(spacing: 12) {
                    // Voice button (Live Conversation — tap = toggle continuous)
                    Button(action: {
                        nova.toggleConversation()
                    }) {
                        Image(systemName: nova.conversationActive ? "waveform.circle.fill" : "waveform.circle")
                            .font(.system(size: 28))
                            .foregroundColor(
                                nova.state == .listening ? Color.red.opacity(0.7) :
                                nova.conversationActive ? Color(hex: "1a1a2e").opacity(0.5) :
                                Color(hex: "1a1a2e").opacity(0.7)
                            )
                    }
                    .accessibilityLabel(nova.conversationActive ? "Vypnout živou konverzaci" : "Zapnout živou konverzaci")
                    .accessibilityHint("Continuous voice mode — Nova poslouchá nepřetržitě")

                    // Push-to-Talk button (hold to speak, release to send)
                    Image(systemName: nova.pushToTalkActive ? "mic.fill" : "mic")
                        .font(.system(size: 24))
                        .foregroundColor(
                            nova.pushToTalkActive ? Color.red.opacity(0.8) :
                            Color(hex: "1a1a2e").opacity(0.5)
                        )
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in
                                    if !nova.pushToTalkActive {
                                        nova.startPushToTalk()
                                    }
                                }
                                .onEnded { _ in
                                    nova.endPushToTalk()
                                }
                        )
                        .accessibilityLabel("Push to Talk mikrofon")
                        .accessibilityHint("Drž a mluv. Po uvolnění se zpráva odešle.")
                        .accessibilityAddTraits(.isButton)

                    TextField(L10n.t("write_nova"), text: $inputText)
                        .font(.system(size: 15, weight: .light))
                        .focused($isInputFocused)
                        .onSubmit { sendText() }

                    Button(action: { sendText() }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(inputText.isEmpty
                                ? Color(hex: "1a1a2e").opacity(0.15)
                                : Color(hex: "1a1a2e").opacity(0.7))
                    }
                    .disabled(inputText.isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(hex: "f5f0e8").opacity(0.95))
            }
        }
        .onAppear {
            nova.connectWebSocket()
        }
        .fullScreenCover(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(nova)
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
        let nameSuffix = userName.isEmpty ? "" : ", \(userName)"

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
            Image(systemName: "sparkles")
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundColor(Color(hex: "1a1a2e").opacity(0.3))

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

                Text(message.content)
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

// MARK: - Thinking Dots
struct ThinkingDots: View {
    @State private var dotCount = 0
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color(hex: "1a1a2e").opacity(i < dotCount ? 0.4 : 0.1))
                    .frame(width: 6, height: 6)
            }
        }
        .onReceive(timer) { _ in
            dotCount = (dotCount % 3) + 1
        }
    }
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
