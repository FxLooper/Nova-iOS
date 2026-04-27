import SwiftUI
import AVFoundation
import PhotosUI
import PDFKit

struct ContentView: View {
    @EnvironmentObject var nova: NovaService

    var body: some View {
        if (nova.isConfigured && !nova.needsSetup) || nova.demoMode {
            ChatView()
        } else {
            SetupView()
        }
    }
}

// MARK: - Setup View (first launch — premium welcome)
struct SetupView: View {
    @EnvironmentObject var nova: NovaService
    @State private var server = ""
    @State private var token = ""
    @State private var step: Int = 0  // 0=welcome, 1=profil, 2=hlas, 3=connection, 4=ready
    @State private var orbScale: CGFloat = 0.8
    @State private var orbOpacity: Double = 0
    @State private var userName = ""
    @State private var userCity = ""
    @State private var selectedLang = Self.detectSystemLanguage()
    @State private var selectedGender = "female"

    private let languages = SettingsView.languages
    private let totalSteps = 5

    /// Detekuj jazyk iPhonu — pokud ho Nova podporuje, použij ho; jinak EN
    private static func detectSystemLanguage() -> String {
        let supported = ["cs","en","de","fr","es","it","pt","pl","sk","ru","ja","zh","ko","ar","tr","hi"]
        let preferred = Locale.preferredLanguages.first ?? "en"
        let langCode = String(preferred.prefix(2))
        return supported.contains(langCode) ? langCode : "en"
    }

    /// Lokalizace pro onboarding — používá vybraný jazyk (ne UserDefaults, ten se nastaví až při connect)
    private func t(_ key: String) -> String {
        L10n.strings[selectedLang]?[key] ?? L10n.strings["en"]?[key] ?? key
    }

    var body: some View {
        ZStack {
            NovaBackground()

            VStack(spacing: 0) {
                // Progress dots (kromě welcome)
                if step > 0 && step < 4 {
                    HStack(spacing: 8) {
                        ForEach(1..<4, id: \.self) { i in
                            Circle()
                                .fill(Color(hex: "1a1a2e").opacity(i <= step ? 0.6 : 0.12))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .padding(.top, 60)
                }

                Group {
                    switch step {
                    case 0: welcomeStep
                    case 1: profileStep
                    case 2: voiceStep
                    case 3: connectionStep
                    default: readyStep
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.5), value: step)
    }

    // ── Step 0: Welcome ──
    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer()
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
                Text(t("personal_ai"))
                    .font(.system(size: 15, weight: .light))
                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))
            }
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                welcomeFeature(icon: "waveform.circle", text: t("feature_voice"))
                welcomeFeature(icon: "brain.head.profile", text: t("feature_memory"))
                welcomeFeature(icon: "chevron.left.forwardslash.chevron.right", text: t("feature_dev"))
                welcomeFeature(icon: "lock.icloud", text: t("feature_private"))
            }
            .padding(.horizontal, 40)
            Spacer()
            nextButton(t("start")) { step = 1 }
        }
    }

    // ── Step 1: Profil ──
    private var profileStep: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 8) {
                Text("👋")
                    .font(.system(size: 48))
                Text(t("whats_your_name"))
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.8))
            }
            Spacer().frame(height: 40)
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(t("name").uppercased())
                        .font(.system(size: 11, weight: .medium))
                        .tracking(2)
                        .foregroundColor(Color(hex: "1a1a2e").opacity(0.4))
                    TextField(t("name_placeholder"), text: $userName)
                        .textFieldStyle(NovaTextFieldStyle())
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(t("city").uppercased())
                        .font(.system(size: 11, weight: .medium))
                        .tracking(2)
                        .foregroundColor(Color(hex: "1a1a2e").opacity(0.4))
                    TextField(t("city_placeholder"), text: $userCity)
                        .textFieldStyle(NovaTextFieldStyle())
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(t("language").uppercased())
                        .font(.system(size: 11, weight: .medium))
                        .tracking(2)
                        .foregroundColor(Color(hex: "1a1a2e").opacity(0.4))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(languages, id: \.code) { lang in
                                Button(action: { selectedLang = lang.code }) {
                                    Text("\(lang.flag) \(lang.name)")
                                        .font(.system(size: 13, weight: selectedLang == lang.code ? .medium : .light))
                                        .foregroundColor(Color(hex: "1a1a2e").opacity(selectedLang == lang.code ? 0.9 : 0.4))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color(hex: "1a1a2e").opacity(selectedLang == lang.code ? 0.08 : 0.02))
                                        .cornerRadius(20)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 40)
            Spacer()
            nextButton(t("continue_btn")) { step = 2 }
        }
    }

    // ── Step 2: Hlas ──
    private var voiceStep: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 8) {
                Text("🎙")
                    .font(.system(size: 48))
                Text(t("voice_preference"))
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.8))
                Text(t("voice_subtitle"))
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.4))
            }
            Spacer().frame(height: 40)
            HStack(spacing: 20) {
                voiceOption(label: t("female"), icon: "person.fill", gender: "female")
                voiceOption(label: t("male"), icon: "person.fill", gender: "male")
            }
            .padding(.horizontal, 40)
            Spacer()
            nextButton(t("continue_btn")) { step = 3 }
        }
    }

    private func voiceOption(label: String, icon: String, gender: String) -> some View {
        Button(action: { selectedGender = gender }) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 32, weight: .light))
                Text(label)
                    .font(.system(size: 15, weight: selectedGender == gender ? .medium : .light))
            }
            .foregroundColor(Color(hex: "1a1a2e").opacity(selectedGender == gender ? 0.8 : 0.3))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(Color(hex: "1a1a2e").opacity(selectedGender == gender ? 0.06 : 0.02))
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color(hex: "1a1a2e").opacity(selectedGender == gender ? 0.2 : 0.06), lineWidth: 1)
            )
        }
    }

    @State private var showQRScanner = false
    @State private var qrConnected = false
    @State private var showNoServerInfo = false

    // ── Step 3: Connection (QR + ruční) ──
    private var connectionStep: some View {
        VStack(spacing: 32) {
            Spacer()
            VStack(spacing: 8) {
                Text("🔗")
                    .font(.system(size: 48))
                Text(t("connect_mac"))
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.8))
                Text(t("connect_mac_desc"))
                    .font(.system(size: 13, weight: .light))
                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            // QR scan button — hlavní akce
            Button(action: { showQRScanner = true }) {
                HStack(spacing: 12) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 24))
                    Text(t("scan_qr"))
                        .font(.system(size: 16, weight: .medium))
                }
                .foregroundColor(Color(hex: "f5f0e8"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color(hex: "1a1a2e").opacity(0.85))
                .cornerRadius(999)
            }
            .padding(.horizontal, 40)

            // Ruční zadání — fallback
            VStack(spacing: 4) {
                Text(t("or_manual"))
                    .font(.system(size: 12, weight: .light))
                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.3))
            }

            VStack(spacing: 16) {
                TextField("http://server.local:3000", text: $server)
                    .textFieldStyle(NovaTextFieldStyle())
                    .autocapitalization(.none)
                    .keyboardType(.URL)
                SecureField(L10n.t("token_label"), text: $token)
                    .textFieldStyle(NovaTextFieldStyle())
            }
            .padding(.horizontal, 40)

            Spacer()

            VStack(spacing: 12) {
                Button(action: { connectAndFinish() }) {
                    Text(t("connect"))
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

                // "Ještě nemám server" — guest/demo cesta pro uživatele bez Mac serveru
                Button(action: { showNoServerInfo = true }) {
                    Text(t("no_server_yet"))
                        .font(.system(size: 13, weight: .light))
                        .underline()
                        .foregroundColor(Color(hex: "1a1a2e").opacity(0.45))
                }
                .padding(.top, 4)

                backButton { step = 2 }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .sheet(isPresented: $showQRScanner) {
            QRScannerView { result in
                showQRScanner = false
                if let data = result.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                   let s = json["server"], let t = json["token"] {
                    server = s
                    token = t
                    HapticManager.shared.novaResponseChord()
                    connectAndFinish()
                }
            }
        }
        .sheet(isPresented: $showNoServerInfo) {
            NoServerInfoSheet(
                onDemo: {
                    showNoServerInfo = false
                    // Uložíme zatím zadaný profil, ať má Nova jméno/jazyk i v demo režimu
                    UserDefaults.standard.set(userName, forKey: "nova_user_name")
                    UserDefaults.standard.set(userCity, forKey: "nova_city")
                    UserDefaults.standard.set(selectedLang, forKey: "nova_lang")
                    UserDefaults.standard.set(selectedGender, forKey: "nova_voice_gender")
                    HapticManager.shared.selectionChanged()
                    nova.enterDemoMode()
                }
            )
        }
    }

    private func connectAndFinish() {
        HapticManager.shared.selectionChanged()
        UserDefaults.standard.set(userName, forKey: "nova_user_name")
        UserDefaults.standard.set(userCity, forKey: "nova_city")
        UserDefaults.standard.set(selectedLang, forKey: "nova_lang")
        UserDefaults.standard.set(selectedGender, forKey: "nova_voice_gender")
        let voices = SettingsView.voiceMap[selectedLang] ?? ("cs-vlasta", "cs-antonin")
        let voice = selectedGender == "female" ? voices.female : voices.male
        UserDefaults.standard.set(voice, forKey: "nova_voice")
        nova.configure(server: server, token: token)
    }

    // ── Step 4: Ready ──
    private var readyStep: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green.opacity(0.7))
            Spacer().frame(height: 24)
            Text(t("setup_complete"))
                .font(.system(size: 24, weight: .light))
                .foregroundColor(Color(hex: "1a1a2e").opacity(0.8))
            Text(t("say_hi_nova"))
                .font(.system(size: 14, weight: .light))
                .foregroundColor(Color(hex: "1a1a2e").opacity(0.4))
                .padding(.top, 8)
            Spacer()
        }
    }

    // ── Helpers ──
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

    private func nextButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            HapticManager.shared.selectionChanged()
            withAnimation { action() }
        }) {
            Text(title)
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

    private func backButton(action: @escaping () -> Void) -> some View {
        Button(action: {
            withAnimation { action() }
        }) {
            Text(t("back"))
                .font(.system(size: 13, weight: .light))
                .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))
        }
    }
}

// MARK: - No Server Info Sheet (demo / BYOS vysvětlení)
struct NoServerInfoSheet: View {
    let onDemo: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            NovaBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("🖥")
                            .font(.system(size: 48))
                        Text(L10n.t("how_nova_works"))
                            .font(.system(size: 24, weight: .light))
                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.85))
                        Text(L10n.t("how_nova_works_desc"))
                            .font(.system(size: 14, weight: .light))
                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.6))
                    }
                    .padding(.top, 30)

                    VStack(alignment: .leading, spacing: 14) {
                        infoRow(icon: "1.circle", title: L10n.t("step1_title"), text: L10n.t("step1_desc"))
                        infoRow(icon: "2.circle", title: L10n.t("step2_title"), text: L10n.t("step2_desc"))
                        infoRow(icon: "3.circle", title: L10n.t("step3_title"), text: L10n.t("step3_desc"))
                    }

                    Divider().padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.t("just_trying"))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.8))
                        Text(L10n.t("just_trying_desc"))
                            .font(.system(size: 13, weight: .light))
                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.55))
                    }

                    VStack(spacing: 12) {
                        Button(action: onDemo) {
                            Text(L10n.t("explore_demo"))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(Color(hex: "f5f0e8"))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color(hex: "1a1a2e").opacity(0.85))
                                .cornerRadius(999)
                        }
                        Button(action: { dismiss() }) {
                            Text(L10n.t("back_to_connect"))
                                .font(.system(size: 14, weight: .light))
                                .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 40)
            }
        }
    }

    private func infoRow(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .light))
                .foregroundColor(Color(hex: "1a1a2e").opacity(0.7))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.85))
                Text(text)
                    .font(.system(size: 13, weight: .light))
                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.55))
            }
        }
    }
}

// MARK: - Chat View
struct ChatView: View {
    @EnvironmentObject var nova: NovaService
    @Environment(\.scenePhase) private var scenePhase
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
    @State private var showPhotoPicker = false
    @State private var showFilePicker = false
    @State private var showTerminal = false
    @State private var showSchedule = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showVoiceConversation = false
    @State private var quickActions: [QuickAction] = QuickAction.load()

    var body: some View {
        ZStack {
            NovaBackground()

            VStack(spacing: 0) {
                // Compact header — nova title + settings + health
                HStack {
                    HStack(spacing: 14) {
                        Button(action: { showSettings = true }) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 14, weight: .light))
                                .foregroundColor(Color(hex: "1a1a2e").opacity(0.25))
                        }
                        Button(action: { showSchedule = true }) {
                            Image(systemName: "clock")
                                .font(.system(size: 14, weight: .light))
                                .foregroundColor(Color(hex: "1a1a2e").opacity(0.25))
                        }
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        Text("nova")
                            .font(.system(size: 18, weight: .ultraLight))
                            .tracking(8)
                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))

                        Circle()
                            .fill(serverHealthColor)
                            .frame(width: 5, height: 5)
                            .opacity(0.8)
                    }

                    Spacer()

                    HStack(spacing: 10) {
                        // WEB indikátor — svítí když Nova něco stahuje z netu
                        Text("WEB")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(nova.isWebMode
                                ? Color(red: 0.3, green: 0.85, blue: 0.45)
                                : Color(hex: "1a1a2e").opacity(0.2))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(nova.isWebMode
                                        ? Color(red: 0.3, green: 0.85, blue: 0.45).opacity(0.1)
                                        : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(nova.isWebMode
                                        ? Color(red: 0.3, green: 0.85, blue: 0.45).opacity(0.4)
                                        : Color(hex: "1a1a2e").opacity(0.15), lineWidth: 1)
                            )
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: nova.isWebMode)

                        // Dev mode indikátor + click pro terminal
                        Button(action: { showTerminal = true }) {
                            Text("DEV")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .tracking(1)
                                .foregroundColor(nova.isDevMode
                                    ? Color(red: 0.2, green: 0.6, blue: 1.0)
                                    : Color(hex: "1a1a2e").opacity(0.2))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(nova.isDevMode
                                            ? Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.1)
                                            : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(nova.isDevMode
                                            ? Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.4)
                                            : Color(hex: "1a1a2e").opacity(0.15), lineWidth: 1)
                                )
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: nova.isDevMode)
                        }

                        // Terminal tlačítko
                        Button(action: { showTerminal = true }) {
                            Image(systemName: "terminal")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(nova.devLogs.isEmpty
                                    ? Color(hex: "1a1a2e").opacity(0.2)
                                    : Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.7))
                        }

                        Button(action: { nova.toggleTTS() }) {
                            Image(systemName: nova.ttsEnabled ? "speaker.wave.2" : "speaker.slash")
                                .font(.system(size: 14, weight: .light))
                                .foregroundColor(Color(hex: "1a1a2e").opacity(nova.ttsEnabled ? 0.25 : 0.6))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)

                Divider().opacity(0.15)

                // Demo režim banner — decentní pruh s CTA na připojení serveru (schovej v screenshot modu)
                if nova.demoMode && !nova.screenshotMode {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.55))
                        Text(L10n.t("demo_mode_banner"))
                            .font(.system(size: 12, weight: .light))
                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.6))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 8)
                        Button(action: {
                            HapticManager.shared.selectionChanged()
                            nova.exitDemoMode()
                        }) {
                            Text(L10n.t("connect"))
                                .font(.system(size: 12, weight: .medium))
                                .tracking(1)
                                .foregroundColor(Color(hex: "f5f0e8"))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(Color(hex: "1a1a2e").opacity(0.85))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(hex: "1a1a2e").opacity(0.04))
                    Divider().opacity(0.1)
                }

                // Quick Actions strip — vždy viditelný
                if !quickActions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(quickActions) { action in
                                Button(action: {
                                    HapticManager.shared.selectionChanged()
                                    Task { await nova.sendMessage(action.prompt) }
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: action.icon)
                                            .font(.system(size: 11, weight: .medium))
                                        Text(action.label)
                                            .font(.system(size: 13, weight: .light))
                                            .lineLimit(1)
                                    }
                                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.6))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color(hex: "1a1a2e").opacity(0.04))
                                    .clipShape(Capsule())
                                }
                                .opacity(nova.state == .speaking ? 0.5 : 1.0)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }

                // Setup banner — zobrazí se vždy když WhisperKit loaduje
                if nova.useWhisper && nova.whisperState != .ready {
                    HStack(spacing: 10) {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(Color(hex: "1a1a2e").opacity(0.5))
                        Text(L10n.t("finishing_setup"))
                            .font(.system(size: 13, weight: .light))
                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))
                        Spacer()
                        if nova.whisperLoadProgress > 0 && nova.whisperLoadProgress < 1 {
                            Text("\(Int(nova.whisperLoadProgress * 100))%")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(hex: "1a1a2e").opacity(0.4))
                                .monospacedDigit()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color(hex: "1a1a2e").opacity(0.04))
                    .transition(.opacity)
                }

                // Project Session banner
                if let session = nova.activeSession {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color.blue.opacity(0.8))
                            .frame(width: 8, height: 8)
                        Text("DEV")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(2)
                            .foregroundColor(.blue.opacity(0.7))
                        Text("·")
                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.2))
                        Text(session)
                            .font(.system(size: 13, weight: .light))
                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.6))
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.06))
                    .cornerRadius(10)
                    .padding(.horizontal, 16)
                }

                // Server offline banner (schovej v screenshot modu)
                if nova.serverHealth.status == .offline && !nova.screenshotMode {
                    offlineBanner
                }

                // Univerzální notification bannery
                bannersList

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

                            // Recap — automatické připomenutí po neaktivitě
                            if let recap = nova.recapText {
                                HStack(spacing: 8) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.system(size: 12))
                                    Text(recap)
                                        .font(.system(size: 13, weight: .light))
                                        .italic()
                                }
                                .foregroundColor(Color(hex: "1a1a2e").opacity(0.35))
                                .padding(.horizontal, 24)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .onTapGesture {
                                    withAnimation(.easeOut(duration: 0.3)) { nova.recapText = nil }
                                }
                            }

                            ForEach(nova.messages) { msg in
                                MessageBubble(
                                    message: msg,
                                    isLatest: msg.id == nova.messages.last?.id
                                )
                                .id(msg.id)
                            }

                            // Interim speech text — jen při dictating, zobrazí se v bottom baru
                            // Zde nezobrazovat — duplicita s dictating barem

                            // Confirm buttons
                            if nova.pendingConfirmation != nil {
                                ConfirmButtons(yesLabel: L10n.t("yes"), noLabel: L10n.t("no")) { confirmed in
                                    Task { await nova.confirmAction(confirmed) }
                                }
                                .padding(.horizontal, 20)
                            }

                            // Live status — viditelný CELOU dobu co Nova pracuje
                            // Zobrazí se kdykoli je thinkingStage nastavený
                            if nova.thinkingStage != nil {
                                VStack(alignment: .leading, spacing: 6) {
                                    // Live stage indikátor — vždy nahoře
                                    LiveStageIndicator()

                                    // Streaming text pod ním — skryj JSON/akce úplně
                                    if nova.isStreaming && !nova.streamingText.isEmpty {
                                        let trimmed = nova.streamingText.trimmingCharacters(in: .whitespaces)
                                        let looksLikeJSON = trimmed.hasPrefix("{") || trimmed.hasPrefix("[") || trimmed.hasPrefix("```") || trimmed.hasPrefix("(") || trimmed.contains("\"action\"") || trimmed.contains("\"speech\"") || trimmed.contains("\"params\"")
                                        let cleanStreamText = looksLikeJSON ? Self.extractSpeechIfJSON(nova.streamingText) : nil
                                        let displayStream = cleanStreamText ?? (looksLikeJSON ? nil : nova.streamingText)

                                        if let displayStream = displayStream, !displayStream.isEmpty {
                                            HStack {
                                                StreamingTextView(text: displayStream)
                                                    .padding(.horizontal, 14)
                                                    .padding(.vertical, 10)
                                                    .background(Color(hex: "f0ece4").opacity(0.6))
                                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                            .stroke(Color(hex: "1a1a2e").opacity(0.04), lineWidth: 0.5)
                                                    )
                                                    .shadow(color: Color(hex: "1a1a2e").opacity(0.03), radius: 6, x: 0, y: 2)
                                                Spacer(minLength: 48)
                                            }
                                            .padding(.horizontal, 14)
                                        }
                                    }
                                }
                                .id("streaming-bubble")
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.92).combined(with: .opacity),
                                    removal: .opacity
                                ))
                            }

                            if nova.state == .listening && dictationState == .idle {
                                NovaStateBubble(
                                    icon: "waveform",
                                    label: L10n.t("listening"),
                                    color: Color.orange
                                )
                                .id("listening-bubble")
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.92).combined(with: .opacity),
                                    removal: .opacity
                                ))
                            }

                            if nova.state == .speaking {
                                NovaStateBubble(
                                    icon: "speaker.wave.2",
                                    label: L10n.t("speaking"),
                                    color: Color(hex: "3a5a6a")
                                )
                                .id("speaking-bubble")
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.92).combined(with: .opacity),
                                    removal: .opacity
                                ))
                            }

                            // Bottom anchor — vždy na konci
                            Color.clear.frame(height: 1).id("bottom-anchor")
                        }
                        .padding(.vertical, 16)
                        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: nova.state)
                        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: nova.thinkingStage)
                    }
                    .onAppear {
                        // Multi-fire scroll — vykreslení trvá různě dlouho podle počtu zpráv
                        let scrollAfter: [TimeInterval] = [0.05, 0.2, 0.5, 1.0]
                        for delay in scrollAfter {
                            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                if let last = nova.messages.last {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                    .onChange(of: nova.messages.count) {
                        scrollToBottom(proxy)
                    }
                    .onChange(of: nova.state) { _, _ in
                        scrollToBottom(proxy)
                    }
                    .onChange(of: nova.streamingText) {
                        if nova.isStreaming {
                            scrollToBottom(proxy)
                        }
                    }
                    .onChange(of: nova.thinkingStage?.key) { _, _ in
                        scrollToBottom(proxy)
                    }
                    .onChange(of: isInputFocused) { _, focused in
                        if focused {
                            // Klávesnice se objevila — scrollni dolů aby byla vidět poslední zpráva
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                scrollToBottom(proxy)
                            }
                        } else {
                            // Klávesnice zavřená — scrollni dolů
                            scrollToBottom(proxy)
                        }
                    }
                }

                Divider().opacity(0.15)

                // ─── Premium Input Bar ──────────────────────────────────
                VStack(spacing: 0) {
                    // Main input bar — changes based on state
                    HStack(spacing: 12) {
                        switch dictationState {
                        case .idle:
                            // ── IDLE: [≋ Voice] [TextField] [🎙 PTT / Send ▶] ──

                            // Voice conversation button (vlevo — palec levé ruky)
                            Button(action: { showVoiceConversation = true }) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 20))
                                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.4))
                                    .frame(width: 36, height: 36)
                            }

                            // Text input — multi-line, láme se pod sebe do max 6 řádků
                            TextField(L10n.t("write_nova"), text: $inputText, axis: .vertical)
                                .font(.system(size: 15, weight: .light))
                                .lineLimit(1...6)
                                .focused($isInputFocused)
                                .submitLabel(.send)
                                .onChange(of: inputText) { _, newValue in
                                    // Enter na konci = odeslání; nový řádek necháme přes Shift+Enter nebo když zpráva není ukončena
                                    if newValue.hasSuffix("\n") {
                                        inputText = String(newValue.dropLast())
                                        if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            sendText()
                                        }
                                    }
                                }

                            if inputText.isEmpty {
                                // Plus menu — kamera, fotky, soubory
                                Menu {
                                    Button(action: {
                                        HapticManager.shared.selectionChanged()
                                        showCamera = true
                                    }) {
                                        Label(L10n.t("camera"), systemImage: "camera")
                                    }
                                    Button(action: {
                                        HapticManager.shared.selectionChanged()
                                        showPhotoPicker = true
                                    }) {
                                        Label(L10n.t("photos"), systemImage: "photo.on.rectangle")
                                    }
                                    Button(action: {
                                        HapticManager.shared.selectionChanged()
                                        showFilePicker = true
                                    }) {
                                        Label(L10n.t("files"), systemImage: "doc")
                                    }
                                } label: {
                                    Image(systemName: "plus.circle")
                                        .font(.system(size: 24, weight: .light))
                                        .foregroundColor(Color(hex: "1a1a2e").opacity(0.45))
                                        .frame(width: 36, height: 36)
                                }

                                // PTT mic button (vpravo — palec pravé ruky, nejčastější akce)
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
                            // ── DICTATING: expandující live text ──
                            VStack(spacing: 8) {
                                // Live transcript — expanduje se podle obsahu
                                ScrollView {
                                    Text(nova.interimText.isEmpty ? L10n.t("speak_now") : nova.interimText)
                                        .font(.system(size: 15, weight: .light))
                                        .foregroundColor(nova.interimText.isEmpty
                                            ? Color(hex: "1a1a2e").opacity(0.25)
                                            : Color(hex: "1a1a2e").opacity(0.7))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(minHeight: 40, maxHeight: 200)

                                // Buttons row
                                HStack {
                                    Button(action: { cancelDictation() }) {
                                        Image(systemName: "xmark.circle")
                                            .font(.system(size: 22))
                                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.4))
                                    }

                                    Spacer()

                                    // Pulsing recording indicator
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(Color.red.opacity(0.8))
                                            .frame(width: 8, height: 8)
                                            .scaleEffect(recordingPulse ? 1.3 : 0.8)
                                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: recordingPulse)
                                            .onAppear { recordingPulse = true }
                                        Text(L10n.t("listening"))
                                            .font(.system(size: 12, weight: .light))
                                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.4))
                                    }

                                    Spacer()

                                    // Stop button
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
                                }
                            }

                        case .review:
                            // ── REVIEW: plný text + editace + send ──
                            VStack(spacing: 6) {
                                // Scrollable text editor — plná výška, nikdy neoříznutý
                                TextEditor(text: $dictatedText)
                                    .font(.system(size: 15, weight: .light))
                                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.8))
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 60, maxHeight: 250)
                                    .focused($isInputFocused)
                                    .onAppear { isInputFocused = true }

                                // Buttons row
                                HStack {
                                    Button(action: { cancelDictation() }) {
                                        Text(L10n.t("cancel"))
                                            .font(.system(size: 13, weight: .light))
                                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.4))
                                    }

                                    Spacer()

                                    Button(action: { sendDictatedText() }) {
                                        HStack(spacing: 4) {
                                            Text(L10n.t("send"))
                                                .font(.system(size: 14, weight: .medium))
                                            Image(systemName: "arrow.up.circle.fill")
                                                .font(.system(size: 18))
                                        }
                                        .foregroundColor(dictatedText.isEmpty
                                            ? Color(hex: "1a1a2e").opacity(0.15)
                                            : Color(hex: "1a1a2e").opacity(0.7))
                                    }
                                    .disabled(dictatedText.isEmpty)
                                }
                            }
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

            // Screenshot overlay — marketing text pro App Store
            if nova.screenshotMode {
                screenshotOverlay
            }
        }
        .onAppear {
            nova.connectWebSocket()
            Task { await nova.checkCronResults() }
            Task { await nova.checkSession() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await nova.checkCronResults() }
                Task { await nova.checkAndShowRecap() }
                Task { await nova.checkSession() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openScheduledTasks)) { _ in
            showSchedule = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openLiveConversation)) { _ in
            showVoiceConversation = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .siriAskNova)) { note in
            // Siri/Shortcuts předal Nově dotaz — pošli ho rovnou do chatu
            if let query = note.userInfo?["query"] as? String, !query.isEmpty {
                Task { await nova.sendMessage(query) }
            }
        }
        .fullScreenCover(isPresented: $showVoiceConversation) {
            VoiceConversationView(isPresented: $showVoiceConversation)
                .environmentObject(nova)
        }
        .fullScreenCover(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(nova)
        }
        .onChange(of: showSettings) { _, isShowing in
            if !isShowing {
                quickActions = QuickAction.load()
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraCaptureView { image in
                showCamera = false
                guard let image = image else { return }
                Task { await nova.sendImage(image) }
            }
        }
        .sheet(isPresented: $showTerminal) {
            TerminalView()
                .environmentObject(nova)
        }
        .sheet(isPresented: $showSchedule) {
            ScheduledTasksView()
                .environmentObject(nova)
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhoto, matching: .any(of: [.images, .videos]))
        .onChange(of: selectedPhoto) { _, newItem in
            guard let item = newItem else { return }
            Task {
                // Video
                if let movie = try? await item.loadTransferable(type: VideoTransferable.self) {
                    let data = try? Data(contentsOf: movie.url)
                    if let data = data {
                        let filename = movie.url.lastPathComponent
                        await nova.sendVideo(data, filename: filename)
                        selectedPhoto = nil
                        return
                    }
                }
                // Fotka
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await nova.sendImage(image)
                }
                selectedPhoto = nil
            }
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                guard url.startAccessingSecurityScopedResource() else {
                    dlog("[file] cannot access: \(url)")
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }
                guard let data = try? Data(contentsOf: url) else {
                    dlog("[file] cannot read: \(url)")
                    return
                }
                dlog("[file] loaded \(data.count) bytes from \(url.lastPathComponent)")
                // Video soubory
                let videoExtensions = ["mp4", "mov", "m4v", "avi", "mkv", "webm"]
                if videoExtensions.contains(url.pathExtension.lowercased()) {
                    Task { await nova.sendVideo(data, filename: url.lastPathComponent) }
                }
                // Zkus jako obrázek
                else if let image = UIImage(data: data) {
                    Task { await nova.sendImage(image) }
                } else if url.pathExtension.lowercased() == "pdf" {
                    // PDF — extrahuj text přes PDFKit
                    if let pdf = PDFDocument(data: data) {
                        let text = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
                        if !text.isEmpty {
                            Task { await nova.sendMessage("Z PDF \(url.lastPathComponent):\n\n\(text.prefix(5000))") }
                        } else {
                            Task { await nova.sendMessage("[PDF \(url.lastPathComponent) nemá textový obsah — je to naskenovaný dokument. Potřeboval bys OCR.]") }
                        }
                    } else {
                        Task { await nova.sendMessage("[PDF \(url.lastPathComponent) se nepodařilo otevřít]") }
                    }
                } else if let text = String(data: data, encoding: .utf8) {
                    Task { await nova.sendMessage("Přečetl jsem soubor \(url.lastPathComponent):\n\n\(text.prefix(3000))") }
                } else {
                    Task { await nova.sendMessage("[Soubor \(url.lastPathComponent) — \(data.count) B, neumím ho přečíst]") }
                }
            case .failure(let error):
                dlog("[file] error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Screenshot Overlay (App Store marketing text)
    private var screenshotOverlay: some View {
        let titles: [(String, String)] = [
            ("Řekni \"Hey Nova\" a jedeš", "Hands-free hlasový AI parťák"),
            ("Přeruš ji kdykoli", "Jako v reálné konverzaci"),
            ("Programuj hlasem", "Claude Code na tvém Macu"),
            ("Tvá data zůstávají u tebe", "100% soukromí, zero cloud"),
        ]
        let scene = max(0, min(nova.messages.count > 2 ? 1 : 0, titles.count - 1))
        // Determine scene from message content
        let sceneIndex: Int = {
            guard let first = nova.messages.first else { return 0 }
            if first.content.contains("briefing") { return 0 }
            if first.content.contains("počasí") || first.content.contains("weather") { return 1 }
            if first.content.contains("projekt") || first.content.contains("lokalizac") { return 2 }
            if first.content.contains("data") || first.content.contains("soukrom") { return 3 }
            return 0
        }()
        let (title, subtitle) = titles[sceneIndex]

        return VStack {
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.85))
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.45))
            }
            .padding(.top, 95)
            .padding(.horizontal, 30)
            Spacer()
        }
    }

    private var offlineBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 14))
                .foregroundColor(.red.opacity(0.7))
            Text(L10n.t("server_offline"))
                .font(.system(size: 13, weight: .light))
                .foregroundColor(.red.opacity(0.6))
            Spacer()
            Button(action: { Task { await nova.serverHealth.pingNow() } }) {
                Text(L10n.t("retry"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.06))
        .cornerRadius(10)
        .padding(.horizontal, 16)
    }

    private var bannersList: some View {
        ForEach(nova.activeBanners) { banner in
            HStack(spacing: 10) {
                Image(systemName: bannerIcon(banner.type))
                    .font(.system(size: 14))
                    .foregroundColor(bannerColor(banner.type))
                VStack(alignment: .leading, spacing: 2) {
                    Text(banner.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(hex: "1a1a2e").opacity(0.7))
                    if let detail = banner.detail {
                        Text(detail)
                            .font(.system(size: 11, weight: .light))
                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.4))
                            .lineLimit(2)
                    }
                }
                Spacer()
                Button(action: { withAnimation { nova.dismissBanner(banner) } }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(hex: "1a1a2e").opacity(0.3))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(bannerColor(banner.type).opacity(0.06))
            .overlay(Rectangle().fill(bannerColor(banner.type).opacity(0.3)).frame(width: 3), alignment: .leading)
            .cornerRadius(10)
            .padding(.horizontal, 16)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func bannerIcon(_ type: BannerItem.BannerType) -> String {
        switch type {
        case .info: return "info.circle"
        case .success: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "wifi.slash"
        case .dev: return "chevron.left.forwardslash.chevron.right"
        case .web: return "globe"
        case .cron: return "clock.arrow.circlepath"
        case .reminder: return "bell"
        }
    }

    private func bannerColor(_ type: BannerItem.BannerType) -> Color {
        switch type {
        case .info: return Color(hex: "1a1a2e")
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        case .dev: return .blue
        case .web: return .green
        case .cron: return .purple
        case .reminder: return .yellow
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
            timeGreeting = L10n.t("greeting_morning")
        case 10..<12:
            timeGreeting = L10n.t("greeting_late_morning")
        case 12..<14:
            timeGreeting = L10n.t("greeting_noon")
        case 14..<18:
            timeGreeting = L10n.t("greeting_afternoon")
        case 18..<24:
            timeGreeting = L10n.t("greeting_evening")
        default:
            timeGreeting = L10n.t("greeting_morning")
        }

        return "\(timeGreeting)\(nameSuffix)"
    }

    private var emptyWelcomeView: some View {
        VStack(spacing: 16) {
            if nova.whisperState != .ready && nova.useWhisper {
                // První spuštění — WhisperKit se stahuje/loaduje
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(Color(hex: "1a1a2e").opacity(0.4))

                    Text(L10n.t("finishing_setup"))
                        .font(.system(size: 16, weight: .light))
                        .foregroundColor(Color(hex: "1a1a2e").opacity(0.6))

                    if nova.whisperLoadProgress > 0 && nova.whisperLoadProgress < 1 {
                        ProgressView(value: nova.whisperLoadProgress)
                            .tint(Color(hex: "1a1a2e").opacity(0.5))
                            .frame(width: 180)
                        Text("\(Int(nova.whisperLoadProgress * 100))%")
                            .font(.system(size: 12, weight: .light))
                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.35))
                            .monospacedDigit()
                    }
                }
                .padding(.bottom, 12)
            } else {
                Text(personalizedGreeting)
                    .font(.system(size: 22, weight: .light))
                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.75))
                    .multilineTextAlignment(.center)

                if nova.whisperState == .ready && nova.useWhisper && nova.messages.isEmpty {
                    // Právě se doloadovalo — krátký "ready" text
                    Text(L10n.t("setup_complete"))
                        .font(.system(size: 13, weight: .light))
                        .foregroundColor(.green.opacity(0.6))
                        .transition(.opacity)
                }

                Text(L10n.t("what_today"))
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.4))
            }
        }
        .animation(.easeInOut(duration: 0.5), value: nova.whisperState == .ready)
    }

    private func sendText() {
        guard !nova.isStreaming && nova.state != .thinking else { return }
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        isInputFocused = false
        Task { await nova.sendMessage(text) }
    }

    // MARK: - Dictation Controls

    private func startDictation() {
        // Přeruš TTS pokud Nova mluví
        if nova.state == .speaking {
            nova.interruptAndListen()
        }
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

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            proxy.scrollTo("bottom-anchor", anchor: .bottom)
        }
    }

    /// Extract "speech" value from JSON string, returns nil if not JSON or no speech key
    static func extractSpeechIfJSON(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}"),
              let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let speech = json["speech"] as? String, !speech.isEmpty else {
            return nil
        }
        return speech
    }
}

// MARK: - Message Bubble (Modern 2026)
struct MessageBubble: View {
    let message: Message
    let isLatest: Bool

    init(message: Message, isLatest: Bool = false) {
        self.message = message
        self.isLatest = isLatest
    }

    @State private var appeared = false

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isUser { Spacer(minLength: 48) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 3) {
                // Sender + time inline
                HStack(spacing: 6) {
                    if !isUser {
                        Text("Nova")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.35))
                    }
                    Text(timeString)
                        .font(.system(size: 10, weight: .light, design: .monospaced))
                        .foregroundColor(Color(hex: "1a1a2e").opacity(0.18))
                    if isUser {
                        Text(L10n.t("you"))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.35))
                    }
                }

                // Image bubble (pokud je URL obrázku)
                if let imgURL = message.imageURL, let url = URL(string: imgURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(hex: "1a1a2e").opacity(0.05))
                                .frame(width: 240, height: 240)
                                .overlay(ProgressView())
                        case .success(let image):
                            image.resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 280)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .shadow(color: Color(hex: "1a1a2e").opacity(0.1), radius: 8, x: 0, y: 4)
                                .contextMenu {
                                    Button {
                                        Task { await ImageSaver.save(from: url) }
                                    } label: {
                                        Label(L10n.t("save_to_photos"), systemImage: "square.and.arrow.down")
                                    }
                                    ShareLink(item: url) {
                                        Label(L10n.t("share"), systemImage: "square.and.arrow.up")
                                    }
                                    Button {
                                        UIPasteboard.general.string = imgURL
                                    } label: {
                                        Label(L10n.t("copy_url"), systemImage: "link")
                                    }
                                }
                        case .failure:
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(hex: "1a1a2e").opacity(0.05))
                                .frame(width: 240, height: 80)
                                .overlay(Text(L10n.t("image_load_error")).font(.system(size: 12)))
                        @unknown default: EmptyView()
                        }
                    }
                }

                // Bubble — extract speech from JSON if needed (fallback for missed stream-replace)
                if !message.content.isEmpty {
                VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
                    let displayContent = MessageBubble.cleanContent(message.content, isUser: isUser)
                    let highlighted = isUser ? displayContent : MessageBubble.highlightKeywords(displayContent)
                    let paragraphs = MessageBubble.splitParagraphs(highlighted)
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        if !isUser, let md = try? AttributedString(markdown: paragraph, options: .init(interpretedSyntax: .full)) {
                            Text(md)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
                        } else {
                            Text(paragraph)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
                        }
                    }
                }
                .font(.system(size: 15, weight: .light))
                .foregroundColor(Color(hex: "1a1a2e").opacity(isUser ? 0.85 : 0.75))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(bubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color(hex: "1a1a2e").opacity(isUser ? 0.0 : 0.04), lineWidth: 0.5)
                )
                .shadow(color: Color(hex: "1a1a2e").opacity(0.03), radius: 6, x: 0, y: 2)
                .textSelection(.enabled)
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = MessageBubble.cleanContent(message.content, isUser: isUser)
                    } label: {
                        Label(L10n.t("copy"), systemImage: "doc.on.doc")
                    }
                    ShareLink(item: MessageBubble.cleanContent(message.content, isUser: isUser)) {
                        Label(L10n.t("share"), systemImage: "square.and.arrow.up")
                    }
                }
                } // close if !message.content.isEmpty
            }

            if !isUser { Spacer(minLength: 48) }
        }
        .padding(.horizontal, 14)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                appeared = true
            }
        }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if isUser {
            LinearGradient(
                colors: [
                    Color(hex: "1a1a2e").opacity(0.07),
                    Color(hex: "1a1a2e").opacity(0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            Color(hex: "f0ece4").opacity(0.6)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private var timeString: String {
        Self.timeFormatter.string(from: message.timestamp)
    }

    /// For AI messages: if content is raw JSON with "speech" key, extract the speech text
    static func cleanContent(_ content: String, isUser: Bool) -> String {
        guard !isUser else { return content }
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let speech = json["speech"] as? String, !speech.isEmpty else {
            return content
        }
        return speech
    }

    /// Splits content into paragraphs on blank lines so SwiftUI can render
    /// visible vertical spacing between them (single-Text markdown collapses blanks).
    static func splitParagraphs(_ content: String) -> [String] {
        // Normalize line endings, then split on two-or-more newlines.
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")
        let trimmed = blocks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return trimmed.isEmpty ? [content] : trimmed
    }

    /// Automatically bolds important tokens in Nova's replies so names, places,
    /// acronyms, years and versions pop out without relying on the model.
    /// Skips code blocks, JSON payloads and segments that are already bold.
    static func highlightKeywords(_ content: String) -> String {
        guard !content.isEmpty else { return content }
        // Skip JSON-like or fenced code payloads — we never want to munge those.
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") { return content }
        if content.contains("```") { return content }

        // Split on existing bold markers and only transform the outside parts.
        let parts = content.components(separatedBy: "**")
        var out = ""
        for (idx, part) in parts.enumerated() {
            if idx % 2 == 1 {
                // Already inside ** ... ** — keep as is.
                out += "**" + part + "**"
            } else {
                out += applyHighlightPatterns(to: part)
            }
        }
        return out
    }

    private static let highlightPatterns: [String] = [
        // 1) Multi-word proper names (2+ consecutive Capitalized words, Czech-aware).
        //    Catches "Andrej Babiš", "Petr Pavel", "Donald Trump", "Wall Street".
        #"[A-ZÁČĎÉĚÍŇÓŘŠŤÚŮÝŽ][a-záčďéěíňóřšťúůýž]{2,}(?:\s+[A-ZÁČĎÉĚÍŇÓŘŠŤÚŮÝŽ][a-záčďéěíňóřšťúůýž]{2,}){1,3}"#,
        // 2) All-caps abbreviations of 2–6 chars — NATO, USA, FBI, ČR, HDP.
        #"(?<![A-ZÁČĎÉĚÍŇÓŘŠŤÚŮÝŽ])[A-ZÁČĎÉĚÍŇÓŘŠŤÚŮÝŽ]{2,6}(?![A-ZÁČĎÉĚÍŇÓŘŠŤÚŮÝŽa-záčďéěíňóřšťúůýž])"#,
        // 3) Version-style numbers: 10.4.8, 13.4.7, 2.0.
        #"(?<!\d)\d+\.\d+(?:\.\d+)+"#,
        // 4) Four-digit years (1900–2199).
        #"(?<!\d)(?:19|20|21)\d{2}(?!\d)"#
    ]

    private static func applyHighlightPatterns(to text: String) -> String {
        var current = text
        for pattern in highlightPatterns {
            current = wrapMatches(in: current, pattern: pattern, with: "**")
        }
        return current
    }

    private static func wrapMatches(in text: String, pattern: String, with marker: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return text }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: text, options: [], range: full)
        guard !matches.isEmpty else { return text }

        var result = ""
        var cursor = 0
        for m in matches {
            let r = m.range
            guard r.location >= cursor else { continue } // skip overlaps
            if r.location > cursor {
                result += ns.substring(with: NSRange(location: cursor, length: r.location - cursor))
            }
            let match = ns.substring(with: r)
            // Don't double-wrap if the neighbors already look like markdown emphasis.
            let before = r.location > 0 ? ns.substring(with: NSRange(location: r.location - 1, length: 1)) : ""
            let afterIdx = r.location + r.length
            let after = afterIdx < ns.length ? ns.substring(with: NSRange(location: afterIdx, length: 1)) : ""
            if before == "*" || after == "*" {
                result += match
            } else {
                result += marker + match + marker
            }
            cursor = r.location + r.length
        }
        if cursor < ns.length {
            result += ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))
        }
        return result
    }
}

// MARK: - Streaming Text with Typewriter Effect
struct StreamingTextView: View {
    let text: String
    @State private var displayedCount: Int = 0
    @State private var cursorVisible = true
    @State private var prevText = ""

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            // Typewriter: zobraz jen displayedCount znaků
            let shown = String(text.prefix(displayedCount))
            if let md = try? AttributedString(markdown: shown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                Text(md)
                    .font(.system(size: 15, weight: .light))
                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.75))
                    .textSelection(.enabled)
            } else {
                Text(shown)
                    .font(.system(size: 15, weight: .light))
                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.75))
                    .textSelection(.enabled)
            }

            // Blikající kurzor
            RoundedRectangle(cornerRadius: 1)
                .fill(Color(hex: "1a1a2e").opacity(cursorVisible ? 0.45 : 0))
                .frame(width: 2, height: 15)
                .padding(.leading, 1)
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: cursorVisible)
                .onAppear { cursorVisible = false }
        }
        .onChange(of: text) { _, newText in
            typewriterCatchUp(to: newText)
        }
        .onAppear {
            displayedCount = 0
            typewriterCatchUp(to: text)
        }
    }

    @State private var typewriterTask: Task<Void, Never>?

    private func typewriterCatchUp(to newText: String) {
        let target = newText.count
        guard target > displayedCount else { return }

        // Cancel previous typewriter animation
        typewriterTask?.cancel()
        typewriterTask = Task { @MainActor in
            while displayedCount < target && !Task.isCancelled {
                displayedCount += 1
                try? await Task.sleep(nanoseconds: 35_000_000) // 35ms per char
            }
        }
    }
}

// MARK: - Live Stage Indicator (vždy viditelný když Nova pracuje)
struct LiveStageIndicator: View {
    @EnvironmentObject var nova: NovaService
    @State private var rotation: Double = 0

    private var label: String {
        if let stage = nova.thinkingStage {
            return L10n.stage(stage.key, detail: stage.detail)
        }
        if nova.isStreaming {
            return L10n.stage("generating_response")
        }
        return L10n.stage("thinking")
    }

    private var transitionId: String {
        "\(nova.thinkingStage?.key ?? "default")|\(nova.thinkingStage?.detail ?? "")"
    }

    private let accent = Color(red: 0.2, green: 0.6, blue: 1.0)

    var body: some View {
        HStack(spacing: 16) {
            // JARVIS REACTOR
            ZStack {
                // Layer 0 — ambient glow
                Circle()
                    .fill(accent.opacity(pulse1 * 0.12))
                    .frame(width: 42, height: 42)
                    .blur(radius: 8)

                // Layer 1 — outer ring, slow, wide arc
                Circle()
                    .trim(from: 0, to: 0.55)
                    .stroke(
                        accent.opacity(0.12 + pulse1 * 0.2),
                        style: StrokeStyle(lineWidth: 1, lineCap: .round)
                    )
                    .frame(width: 34, height: 34)
                    .rotationEffect(.degrees(ring1))

                // Layer 2 — main ring, medium speed
                Circle()
                    .trim(from: 0, to: 0.35)
                    .stroke(
                        accent.opacity(0.35 + pulse2 * 0.55),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .frame(width: 26, height: 26)
                    .rotationEffect(.degrees(ring2))

                // Layer 3 — inner ring, fast, counter-rotate
                Circle()
                    .trim(from: 0, to: 0.25)
                    .stroke(
                        accent.opacity(0.25 + pulse3 * 0.4),
                        style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
                    )
                    .frame(width: 18, height: 18)
                    .rotationEffect(.degrees(ring3))

                // Layer 4 — micro ring, fastest
                Circle()
                    .trim(from: 0, to: 0.15)
                    .stroke(
                        accent.opacity(0.2 + pulse1 * 0.3),
                        style: StrokeStyle(lineWidth: 1, lineCap: .round)
                    )
                    .frame(width: 12, height: 12)
                    .rotationEffect(.degrees(ring4))

                // Orbiting light pulse — světelný bod obíhá po hlavním prstenci
                Circle()
                    .fill(accent.opacity(0.6 + pulse2 * 0.4))
                    .frame(width: 4, height: 4)
                    .shadow(color: accent.opacity(0.5), radius: 4)
                    .offset(x: 13)
                    .rotationEffect(.degrees(orbitLight))

                // Druhý orbiting pulse — protiběžný, subtilnější
                Circle()
                    .fill(accent.opacity(0.3 + pulse3 * 0.3))
                    .frame(width: 3, height: 3)
                    .shadow(color: accent.opacity(0.3), radius: 3)
                    .offset(x: 17)
                    .rotationEffect(.degrees(-orbitLight * 0.6))

                // Core — pulzující střed s glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                accent.opacity(0.5 + pulse2 * 0.5),
                                accent.opacity(0.15 + pulse2 * 0.15),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 7
                        )
                    )
                    .frame(width: 14, height: 14)

                Circle()
                    .fill(accent.opacity(0.6 + pulse1 * 0.4))
                    .frame(width: 4, height: 4)
            }
            .frame(width: 42, height: 42)
            .onAppear {
                // Každý ring má jinou rychlost a směr
                withAnimation(.linear(duration: 6.0).repeatForever(autoreverses: false)) {
                    ring1 = 360
                }
                withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
                    ring2 = 360
                }
                withAnimation(.linear(duration: 3.5).repeatForever(autoreverses: false)) {
                    ring3 = -360
                }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    ring4 = 360
                }
                // Orbiting light — plynulý, ne moc rychlý
                withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                    orbitLight = 360
                }
                // Pulse — každý s jiným timingem pro organický feel
                withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                    pulse1 = 1.0
                }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true).delay(0.3)) {
                    pulse2 = 1.0
                }
                withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true).delay(0.6)) {
                    pulse3 = 1.0
                }
            }

            // Text — typewriter + shimmer + fade out
            JarvisTextView(text: label, accent: accent)
                .id(transitionId)
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .push(from: .top).combined(with: .opacity)
                ))

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: transitionId)
    }

    // Ring rotations — každý svou rychlostí
    @State private var ring1: Double = 0
    @State private var ring2: Double = 0
    @State private var ring3: Double = 0
    @State private var ring4: Double = 0
    @State private var orbitLight: Double = 0
    // Pulses — každý s jiným timingem
    @State private var pulse1: Double = 0
    @State private var pulse2: Double = 0
    @State private var pulse3: Double = 0
}

// MARK: - Image Saver
struct ImageSaver {
    static func save(from url: URL) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return }
            await MainActor.run {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                HapticManager.shared.novaResponseChord()
            }
        } catch {
            dlog("[save] error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Jarvis Text View (typewriter → shimmer → fade)
struct JarvisTextView: View {
    let text: String
    let accent: Color

    @State private var displayedChars: Int = 0
    @State private var shimmerX: CGFloat = -60
    @State private var phase: Phase = .typing
    @State private var textOpacity: Double = 1.0
    @State private var animTask: Task<Void, Never>?

    enum Phase {
        case typing, shimmer, visible, fadeOut
    }

    var visibleText: String {
        String(text.prefix(displayedChars))
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Base text
            Text(visibleText)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(hex: "1a1a2e").opacity(0.55 * textOpacity))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            // Shimmer overlay — jen ve fázi shimmer
            if phase == .shimmer || phase == .visible {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            Color.clear,
                            accent.opacity(0.25),
                            Color.white.opacity(0.7),
                            accent.opacity(0.25),
                            Color.clear,
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: 50)
                    .offset(x: shimmerX)
                    .blur(radius: 1)
                }
                .mask(
                    Text(visibleText)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                )
            }

            // Typing cursor
            if phase == .typing {
                Text(visibleText + "▌")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(.clear)
                    .lineLimit(3)
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(accent.opacity(0.6))
                            .frame(width: 2, height: 16)
                            .opacity(displayedChars % 2 == 0 ? 1 : 0.4)
                    }
            }
        }
        .onAppear { startAnimation() }
        .onChange(of: text) { _, _ in startAnimation() }
    }

    private func startAnimation() {
        animTask?.cancel()
        displayedChars = 0
        phase = .typing
        textOpacity = 1.0
        shimmerX = -60

        animTask = Task { @MainActor in
            // Phase 1: Typewriter — písmenko po písmenku
            for i in 1...text.count {
                if Task.isCancelled { return }
                displayedChars = i
                try? await Task.sleep(nanoseconds: 35_000_000) // 35ms per char
            }

            if Task.isCancelled { return }

            // Phase 2: Shimmer přejede přes text
            phase = .shimmer
            shimmerX = -60
            withAnimation(.linear(duration: 0.8)) {
                shimmerX = 300
            }

            try? await Task.sleep(nanoseconds: 800_000_000)
            if Task.isCancelled { return }

            // Phase 3: Visible — text zůstane viditelný dokud se nezmění stage
            phase = .visible
            // Žádný fade-out — text zůstává dokud nepřijde nový stage
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
// MARK: - Nova State Bubble (listening / speaking indicator v chatu)
struct NovaStateBubble: View {
    let icon: String
    let label: String
    let color: Color

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            // Animated icon
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 22, height: 22)
                    .scaleEffect(pulse ? 1.15 : 1.0)

                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(color.opacity(0.8))
            }

            Text(label)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundColor(Color(hex: "1a1a2e").opacity(0.65))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(color.opacity(0.12), lineWidth: 0.5)
                )
                .shadow(color: Color(hex: "1a1a2e").opacity(0.04), radius: 8, x: 0, y: 2)
        )
        .padding(.horizontal, 20)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Quick Action Model
struct QuickAction: Identifiable, Codable {
    let id: UUID
    var label: String   // Co se zobrazí na tlačítku
    var prompt: String  // Co se pošle Nově
    var icon: String    // SF Symbol name

    init(label: String, prompt: String, icon: String) {
        self.id = UUID()
        self.label = label
        self.prompt = prompt
        self.icon = icon
    }

    static let defaults: [QuickAction] = [
        QuickAction(label: L10n.t("qa_weather"), prompt: L10n.t("qa_weather_prompt"), icon: "cloud.sun"),
        QuickAction(label: L10n.t("qa_news"), prompt: L10n.t("qa_news_prompt"), icon: "newspaper"),
        QuickAction(label: L10n.t("qa_calendar"), prompt: L10n.t("qa_calendar_prompt"), icon: "calendar"),
        QuickAction(label: L10n.t("qa_email"), prompt: L10n.t("qa_email_prompt"), icon: "envelope"),
    ]

    static func load() -> [QuickAction] {
        guard let data = UserDefaults.standard.data(forKey: "nova_quick_actions"),
              let actions = try? JSONDecoder().decode([QuickAction].self, from: data),
              !actions.isEmpty else {
            return defaults
        }
        return actions
    }

    static func save(_ actions: [QuickAction]) {
        if let data = try? JSONEncoder().encode(actions) {
            UserDefaults.standard.set(data, forKey: "nova_quick_actions")
        }
    }
}

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

// MARK: - Video Transferable
struct VideoTransferable: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
            try FileManager.default.copyItem(at: received.file, to: tmp)
            return Self(url: tmp)
        }
    }
}

// MARK: - QR Scanner
struct QRScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    func makeUIViewController(context: Context) -> QRScannerController {
        let c = QRScannerController(); c.onScan = onScan; return c
    }
    func updateUIViewController(_ vc: QRScannerController, context: Context) {}
}

class QRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?
    private var session: AVCaptureSession?
    private var scanned = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let s = AVCaptureSession()
        guard let dev = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: dev) else { return }
        if s.canAddInput(input) { s.addInput(input) }
        let output = AVCaptureMetadataOutput()
        if s.canAddOutput(output) { s.addOutput(output); output.setMetadataObjectsDelegate(self, queue: .main); output.metadataObjectTypes = [.qr] }
        let preview = AVCaptureVideoPreviewLayer(session: s)
        preview.frame = view.bounds; preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        // Overlay
        let box = UIView(frame: CGRect(x: 0, y: 0, width: 250, height: 250))
        box.center = view.center; box.layer.borderColor = UIColor.white.withAlphaComponent(0.6).cgColor
        box.layer.borderWidth = 2; box.layer.cornerRadius = 16; box.backgroundColor = .clear
        view.addSubview(box)
        // Label
        let lbl = UILabel(); lbl.text = "Naskenuj QR kód z Mac obrazovky"
        lbl.textColor = .white.withAlphaComponent(0.7); lbl.font = .systemFont(ofSize: 14, weight: .light)
        lbl.textAlignment = .center; lbl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(lbl)
        NSLayoutConstraint.activate([lbl.centerXAnchor.constraint(equalTo: view.centerXAnchor), lbl.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -60)])
        session = s
        DispatchQueue.global().async { s.startRunning() }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !scanned, let obj = objects.first as? AVMetadataMachineReadableCodeObject, let val = obj.stringValue else { return }
        scanned = true; session?.stopRunning()
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        dismiss(animated: true) { self.onScan?(val) }
    }
}
