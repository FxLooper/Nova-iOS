import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var nova: NovaService
    @EnvironmentObject var voiceProfile: VoiceProfileService
    @Environment(\.dismiss) var dismiss

    @State private var selectedLang: String
    @State private var selectedCity: String
    @State private var selectedVoiceGender: String
    @State private var userName: String
    @State private var useWhisper: Bool
    @State private var showVoiceEnrollment = false
    @State private var voiceVerifyEnforced: Bool
    @State private var showClearHistoryAlert = false
    @State private var showClearMemoryAlert = false
    @State private var selectedDevProject: String
    @State private var editableQuickActions: [QuickAction]
    @State private var ttsSpeed: Double
    @State private var forceRouting: String

    init() {
        _selectedLang = State(initialValue: UserDefaults.standard.string(forKey: "nova_lang") ?? "cs")
        _selectedCity = State(initialValue: UserDefaults.standard.string(forKey: "nova_city") ?? "Plzeň")
        _selectedVoiceGender = State(initialValue: UserDefaults.standard.string(forKey: "nova_voice_gender") ?? "female")
        _userName = State(initialValue: UserDefaults.standard.string(forKey: "nova_user_name") ?? "Ondřej")
        _useWhisper = State(initialValue: UserDefaults.standard.bool(forKey: "nova_use_whisper"))
        _voiceVerifyEnforced = State(initialValue: UserDefaults.standard.bool(forKey: "nova_voice_verify_enforce"))
        _selectedDevProject = State(initialValue: UserDefaults.standard.string(forKey: "nova_dev_project") ?? "backend")
        _editableQuickActions = State(initialValue: QuickAction.load())
        _ttsSpeed = State(initialValue: UserDefaults.standard.object(forKey: "nova_tts_speed") == nil ? 0.0 : UserDefaults.standard.double(forKey: "nova_tts_speed"))
        _forceRouting = State(initialValue: UserDefaults.standard.string(forKey: "nova_force_routing") ?? "auto")
    }

    static let devProjects: [(key: String, label: String, icon: String)] = [
        ("backend",  "Nova Backend (Mac)", "server.rack"),
        ("nova-ios", "Nova iOS app",       "iphone"),
        ("fxlooper", "FxLooper",           "chart.line.uptrend.xyaxis"),
    ]

    static let languages: [(code: String, name: String, flag: String)] = [
        ("cs", "Čeština", "🇨🇿"),
        ("en", "English", "🇬🇧"),
        ("de", "Deutsch", "🇩🇪"),
        ("fr", "Français", "🇫🇷"),
        ("es", "Español", "🇪🇸"),
        ("it", "Italiano", "🇮🇹"),
        ("pt", "Português", "🇧🇷"),
        ("pl", "Polski", "🇵🇱"),
        ("sk", "Slovenčina", "🇸🇰"),
        ("ru", "Русский", "🇷🇺"),
        ("ja", "日本語", "🇯🇵"),
        ("zh", "中文", "🇨🇳"),
        ("ko", "한국어", "🇰🇷"),
        ("ar", "العربية", "🇸🇦"),
        ("tr", "Türkçe", "🇹🇷"),
        ("hi", "हिन्दी", "🇮🇳"),
    ]

    static let voiceMap: [String: (female: String, male: String)] = [
        "cs": ("cs-vlasta", "cs-antonin"),
        "en": ("en-jenny", "en-guy"),
        "de": ("de-katja", "de-conrad"),
        "fr": ("fr-denise", "fr-henri"),
        "es": ("es-elvira", "es-alvaro"),
        "it": ("it-elsa", "it-diego"),
        "pt": ("pt-francisca", "pt-antonio"),
        "pl": ("pl-zofia", "pl-marek"),
        "sk": ("sk-viktoria", "sk-lukas"),
        "ru": ("ru-svetlana", "ru-dmitry"),
        "ja": ("ja-nanami", "ja-keita"),
        "zh": ("zh-xiaoxiao", "zh-yunyang"),
        "ko": ("ko-sunhi", "ko-injoong"),
        "ar": ("ar-salma", "ar-hamed"),
        "tr": ("tr-emel", "tr-ahmet"),
        "hi": ("hi-swara", "hi-madhur"),
    ]

    var body: some View {
        ZStack {
            Color(hex: "f5f0e8").ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { saveAndDismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .light))
                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))
                    }
                    Spacer()
                    Text(L10n.t("settings"))
                        .font(.system(size: 16, weight: .light))
                        .tracking(3)
                        .foregroundColor(Color(hex: "1a1a2e").opacity(0.6))
                    Spacer()
                    // Invisible spacer pro symetrii
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .light))
                        .opacity(0)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                // Auto-save při každé změně
                .onChange(of: selectedLang) { _, _ in autoSave() }
                .onChange(of: selectedCity) { _, _ in autoSave() }
                .onChange(of: selectedVoiceGender) { _, _ in autoSave() }
                .onChange(of: userName) { _, _ in autoSave() }
                .onChange(of: editableQuickActions.count) { _, _ in autoSave() }

                ScrollView {
                    VStack(spacing: 32) {

                        // Jméno
                        SettingsSection(title: L10n.t("name")) {
                            TextField(L10n.t("name_placeholder"), text: $userName)
                                .font(.system(size: 16, weight: .light))
                                .padding(14)
                                .background(Color(hex: "1a1a2e").opacity(0.04))
                                .cornerRadius(12)
                        }

                        // Město
                        SettingsSection(title: L10n.t("city")) {
                            TextField(L10n.t("city_placeholder"), text: $selectedCity)
                                .font(.system(size: 16, weight: .light))
                                .padding(14)
                                .background(Color(hex: "1a1a2e").opacity(0.04))
                                .cornerRadius(12)
                        }

                        // Jazyk
                        SettingsSection(title: L10n.t("language")) {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                                ForEach(Self.languages, id: \.code) { lang in
                                    Button(action: { selectedLang = lang.code }) {
                                        HStack(spacing: 6) {
                                            Text(lang.flag)
                                                .font(.system(size: 16))
                                            Text(lang.name)
                                                .font(.system(size: 13, weight: selectedLang == lang.code ? .medium : .light))
                                                .lineLimit(1)
                                        }
                                        .foregroundColor(Color(hex: "1a1a2e").opacity(selectedLang == lang.code ? 0.9 : 0.5))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            selectedLang == lang.code
                                                ? Color(hex: "1a1a2e").opacity(0.08)
                                                : Color(hex: "1a1a2e").opacity(0.02)
                                        )
                                        .cornerRadius(20)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 20)
                                                .stroke(Color(hex: "1a1a2e").opacity(selectedLang == lang.code ? 0.2 : 0.06), lineWidth: 1)
                                        )
                                    }
                                }
                            }
                        }

                        // Hlas
                        SettingsSection(title: L10n.t("voice")) {
                            HStack(spacing: 12) {
                                VoiceButton(
                                    label: L10n.t("female"),
                                    icon: "person.fill",
                                    isSelected: selectedVoiceGender == "female",
                                    action: { selectedVoiceGender = "female" }
                                )
                                VoiceButton(
                                    label: L10n.t("male"),
                                    icon: "person.fill",
                                    isSelected: selectedVoiceGender == "male",
                                    action: { selectedVoiceGender = "male" }
                                )
                            }

                            // Rychlost mluvení
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(L10n.t("speech_speed"))
                                        .font(.system(size: 13, weight: .regular))
                                        .foregroundColor(Color(hex: "1a1a2e").opacity(0.7))
                                    Spacer()
                                    Text(ttsSpeedLabel)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(Color(hex: "1a1a2e").opacity(0.8))
                                        .monospacedDigit()
                                }
                                Slider(value: $ttsSpeed, in: -15...80, step: 5)
                                    .tint(Color(hex: "1a1a2e").opacity(0.6))
                                    .onChange(of: ttsSpeed) { _, newValue in
                                        UserDefaults.standard.set(newValue, forKey: "nova_tts_speed")
                                    }
                                HStack {
                                    Text(L10n.t("slower"))
                                        .font(.system(size: 10, weight: .light))
                                    Spacer()
                                    Text(L10n.t("faster"))
                                        .font(.system(size: 10, weight: .light))
                                }
                                .foregroundColor(Color(hex: "1a1a2e").opacity(0.4))
                            }
                            .padding(.top, 8)
                        }

                        // Speech Recognition Status
                        SettingsSection(title: L10n.t("speech_recognition")) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(whisperStatusColor)
                                        .frame(width: 8, height: 8)
                                    Text(whisperStatusText)
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundColor(Color(hex: "1a1a2e").opacity(0.8))
                                }

                                if nova.whisperState == .loading {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                        Text("\(L10n.t("stt_loading")) \(Int(nova.whisperLoadProgress * 100))%")
                                            .font(.system(size: 12, weight: .light))
                                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))
                                    }
                                }

                                Text(L10n.t("stt_desc"))
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.4))
                            }
                        }

                        // Wake Word ("Hi Nova")
                        SettingsSection(title: "Wake word „Hi Nova“") {
                            VStack(alignment: .leading, spacing: 10) {
                                Toggle(isOn: Binding(
                                    get: { nova.wakeWordEnabled },
                                    set: { nova.wakeWordEnabled = $0 }
                                )) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Poslouchat „Hi Nova“")
                                            .font(.system(size: 15, weight: .regular))
                                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.8))
                                        Text(nova.wakeWordEnabled
                                             ? "Nova naslouchá, když je appka otevřená."
                                             : "Zapni, ať Nova reaguje na „Hi Nova“ nebo „Ahoj Nova“.")
                                            .font(.system(size: 12, weight: .light))
                                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))
                                    }
                                }
                                .tint(Color(hex: "1a1a2e").opacity(0.7))

                                if nova.wakeWordEnabled {
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(nova.wakeWord.isRunning ? Color.green.opacity(0.7) : Color.orange.opacity(0.7))
                                            .frame(width: 8, height: 8)
                                        Text(nova.wakeWord.isRunning ? "Naslouchám" : "Čekám na oprávnění / spuštění")
                                            .font(.system(size: 12, weight: .light))
                                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))
                                    }
                                }

                                Text("Tip: mimo aplikaci řekni „Hey Siri, Hi Nova“ — Siri otevře Novu do konverzace.")
                                    .font(.system(size: 11, weight: .light))
                                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.4))
                            }
                        }

                        // Voice ID (Voice Biometrics)
                        SettingsSection(title: L10n.t("voice_id")) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 12) {
                                    Image(systemName: voiceProfile.state == .enrolled ? "checkmark.seal.fill" : "waveform.circle")
                                        .font(.system(size: 32, weight: .ultraLight))
                                        .foregroundColor(voiceProfile.state == .enrolled ? .green.opacity(0.7) : Color(hex: "1a1a2e").opacity(0.5))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(voiceProfile.state == .enrolled ? L10n.t("voice_profile_active") : L10n.t("voice_profile_none"))
                                            .font(.system(size: 15, weight: .regular))
                                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.8))
                                        Text(voiceProfile.state == .enrolled ? L10n.t("voice_responds_you") : L10n.t("face_id_voice"))
                                            .font(.system(size: 12, weight: .light))
                                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))
                                    }
                                    Spacer()
                                }

                                Button(action: { showVoiceEnrollment = true }) {
                                    Text(voiceProfile.state == .enrolled ? L10n.t("manage_profile") : L10n.t("create_profile"))
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(Color(hex: "1a1a2e").opacity(0.8))
                                        .padding(.vertical, 10)
                                        .frame(maxWidth: .infinity)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color(hex: "1a1a2e").opacity(0.2), lineWidth: 1)
                                        )
                                }

                                // Enforcement toggle — visible only when enrolled
                                if voiceProfile.state == .enrolled {
                                    Divider().opacity(0.2)

                                    Toggle(isOn: $voiceVerifyEnforced) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(L10n.t("require_verification"))
                                                .font(.system(size: 15, weight: .regular))
                                                .foregroundColor(Color(hex: "1a1a2e").opacity(0.8))
                                            Text(voiceVerifyEnforced
                                                 ? L10n.t("verify_on")
                                                 : L10n.t("verify_off"))
                                                .font(.system(size: 12, weight: .light))
                                                .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))
                                        }
                                    }
                                    .tint(Color(hex: "1a1a2e").opacity(0.7))
                                    .onChange(of: voiceVerifyEnforced) { _, newValue in
                                        UserDefaults.standard.set(newValue, forKey: "nova_voice_verify_enforce")
                                        nova.voiceVerificationEnforced = newValue
                                    }

                                    // Last verification confidence
                                    if voiceProfile.verificationConfidence > 0 {
                                        HStack(spacing: 6) {
                                            Image(systemName: voiceProfile.lastVerificationResult ? "checkmark.circle.fill" : "xmark.circle.fill")
                                                .font(.system(size: 12))
                                                .foregroundColor(voiceProfile.lastVerificationResult ? .green.opacity(0.7) : .red.opacity(0.7))
                                            Text("\(L10n.t("last_match")): \(Int(voiceProfile.verificationConfidence * 100))%")
                                                .font(.system(size: 12, weight: .light))
                                                .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))
                                        }
                                    }

                                    // Threshold slider — strictness control
                                    Divider().opacity(0.15)

                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(L10n.t("verification_strict"))
                                                .font(.system(size: 13, weight: .regular))
                                                .foregroundColor(Color(hex: "1a1a2e").opacity(0.7))
                                            Spacer()
                                            Text("\(Int(voiceProfile.verificationThreshold * 100))%")
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundColor(Color(hex: "1a1a2e").opacity(0.8))
                                                .monospacedDigit()
                                        }
                                        Slider(
                                            value: Binding(
                                                get: { voiceProfile.verificationThreshold },
                                                set: { voiceProfile.verificationThreshold = $0 }
                                            ),
                                            in: voiceProfile.minThreshold...voiceProfile.maxThreshold,
                                            step: 0.05
                                        )
                                        .tint(Color(hex: "1a1a2e").opacity(0.6))

                                        HStack {
                                            Text(L10n.t("permissive"))
                                                .font(.system(size: 10, weight: .light))
                                            Spacer()
                                            Text(L10n.t("balanced"))
                                                .font(.system(size: 10, weight: .light))
                                            Spacer()
                                            Text(L10n.t("strict"))
                                                .font(.system(size: 10, weight: .light))
                                        }
                                        .foregroundColor(Color(hex: "1a1a2e").opacity(0.4))
                                    }

                                    // Stats: enrollment date + total verifications + success rate
                                    if voiceProfile.totalVerifications > 0 || voiceProfile.enrollmentDate != nil {
                                        Divider().opacity(0.15)

                                        VStack(alignment: .leading, spacing: 4) {
                                            if let date = voiceProfile.enrollmentDate {
                                                HStack(spacing: 6) {
                                                    Image(systemName: "calendar")
                                                        .font(.system(size: 11))
                                                    Text("Vytvořeno: \(date.formatted(date: .abbreviated, time: .shortened))")
                                                }
                                                .font(.system(size: 11, weight: .light))
                                                .foregroundColor(Color(hex: "1a1a2e").opacity(0.45))
                                            }

                                            if voiceProfile.totalVerifications > 0 {
                                                HStack(spacing: 6) {
                                                    Image(systemName: "checkmark.shield")
                                                        .font(.system(size: 11))
                                                    Text("Ověření: \(voiceProfile.successfulVerifications)/\(voiceProfile.totalVerifications) (\(Int(voiceProfile.successRate * 100))%)")
                                                }
                                                .font(.system(size: 11, weight: .light))
                                                .foregroundColor(Color(hex: "1a1a2e").opacity(0.45))
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        SettingsSection(title: L10n.t("connection")) {
                            VStack(alignment: .leading, spacing: 8) {
                                // WebSocket status row removed — app uses HTTP polling, not WS
                                // HStack {
                                //     Circle()
                                //         .fill(nova.isConnected ? Color.green.opacity(0.6) : Color.red.opacity(0.4))
                                //         .frame(width: 8, height: 8)
                                //     Text(nova.isConnected ? L10n.t("connected") : L10n.t("disconnected"))
                                //         .font(.system(size: 14, weight: .light))
                                //         .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))
                                // }

                                // Server health detail
                                serverHealthDetailRow

                                Button(action: { nova.resetConfig() }) {
                                    Text(L10n.t("change_server"))
                                        .font(.system(size: 14, weight: .light))
                                        .foregroundColor(Color(hex: "1a1a2e").opacity(0.4))
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 16)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color(hex: "1a1a2e").opacity(0.1), lineWidth: 1)
                                        )
                                }
                            }
                        }

                        // Dev Mode — auto detection info
                        SettingsSection(title: "Dev mode") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Nova automaticky pozná na kterém projektu chceš pracovat z kontextu konverzace.")
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))

                                ForEach(Self.devProjects, id: \.key) { project in
                                    HStack(spacing: 12) {
                                        Image(systemName: project.icon)
                                            .font(.system(size: 14, weight: .light))
                                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.4))
                                            .frame(width: 20)
                                        Text(project.label)
                                            .font(.system(size: 13, weight: .light))
                                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.6))
                                        Spacer()
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 14)
                                }
                            }
                        }

                        // Vynutit routing — override automatické klasifikace
                        SettingsSection(title: "Vynutit routing") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Běžně Nova sama pozná jestli jde o kód, web nebo chat. Tady to můžeš přepsat ručně.")
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))

                                Picker("Routing", selection: $forceRouting) {
                                    Text("Auto").tag("auto")
                                    Text("Chat / Web").tag("web")
                                    Text("Dev").tag("dev")
                                }
                                .pickerStyle(.segmented)
                                .onChange(of: forceRouting) { _, newValue in
                                    UserDefaults.standard.set(newValue, forKey: "nova_force_routing")
                                    if newValue != "dev" {
                                        Task { await nova.resetSession() }
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 4)
                            }
                        }

                        // Nova Memory — fakta co si Nova pamatuje
                        SettingsSection(title: L10n.t("memory")) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "brain.head.profile")
                                        .font(.system(size: 14, weight: .light))
                                        .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))
                                    Text(L10n.t("memory_facts"))
                                        .font(.system(size: 14, weight: .light))
                                        .foregroundColor(Color(hex: "1a1a2e").opacity(0.7))
                                    Spacer()
                                    if nova.memoryLoading {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    } else {
                                        Text("\(nova.memoryFacts.count) \(L10n.t("memory_count"))")
                                            .font(.system(size: 12, weight: .light))
                                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.4))
                                    }
                                }

                                if nova.memoryFacts.isEmpty && !nova.memoryLoading {
                                    Text(L10n.t("memory_empty"))
                                        .font(.system(size: 13, weight: .light))
                                        .foregroundColor(Color(hex: "1a1a2e").opacity(0.35))
                                        .padding(.vertical, 8)
                                } else {
                                    ForEach(Array(nova.memoryFacts.enumerated()), id: \.offset) { index, fact in
                                        HStack(alignment: .top, spacing: 10) {
                                            Text("\(index + 1).")
                                                .font(.system(size: 12, weight: .light))
                                                .foregroundColor(Color(hex: "1a1a2e").opacity(0.3))
                                                .frame(width: 20, alignment: .trailing)
                                            Text(fact)
                                                .font(.system(size: 13, weight: .light))
                                                .foregroundColor(Color(hex: "1a1a2e").opacity(0.7))
                                                .fixedSize(horizontal: false, vertical: true)
                                            Spacer()
                                            Button(action: {
                                                HapticManager.shared.selectionChanged()
                                                Task { await nova.deleteMemoryFact(at: index) }
                                            }) {
                                                Image(systemName: "xmark.circle")
                                                    .font(.system(size: 14))
                                                    .foregroundColor(.red.opacity(0.4))
                                            }
                                        }
                                        .padding(.vertical, 4)
                                        if index < nova.memoryFacts.count - 1 {
                                            Divider().opacity(0.08)
                                        }
                                    }
                                }

                                if !nova.memoryFacts.isEmpty {
                                    Button(action: { showClearMemoryAlert = true }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "trash")
                                                .font(.system(size: 11))
                                            Text(L10n.t("memory_clear_all"))
                                                .font(.system(size: 13, weight: .light))
                                        }
                                        .foregroundColor(.red.opacity(0.5))
                                    }
                                    .padding(.top, 4)
                                }
                            }
                            .onAppear { Task { await nova.fetchMemory() } }
                        }

                        // Conversation History
                        SettingsSection(title: L10n.t("delete_history")) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "bubble.left.and.bubble.right")
                                        .font(.system(size: 14, weight: .light))
                                        .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))
                                    Text("\(nova.messages.count) zpráv v historii")
                                        .font(.system(size: 14, weight: .light))
                                        .foregroundColor(Color(hex: "1a1a2e").opacity(0.7))
                                }

                                // Export
                                if !nova.messages.isEmpty {
                                    ShareLink(item: exportConversationText()) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "square.and.arrow.up")
                                                .font(.system(size: 12))
                                            Text("Exportovat konverzaci")
                                                .font(.system(size: 14, weight: .light))
                                        }
                                        .foregroundColor(Color(hex: "1a1a2e").opacity(0.7))
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 16)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color(hex: "1a1a2e").opacity(0.2), lineWidth: 1)
                                        )
                                    }
                                }

                                Button(action: { showClearHistoryAlert = true }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 12))
                                        Text("Smazat historii konverzace")
                                            .font(.system(size: 14, weight: .light))
                                    }
                                    .foregroundColor(.red.opacity(0.7))
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 16)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.red.opacity(0.3), lineWidth: 1)
                                    )
                                }
                                .disabled(nova.messages.isEmpty)
                                .opacity(nova.messages.isEmpty ? 0.4 : 1.0)
                            }
                        }

                        // Quick Actions editor
                        SettingsSection(title: L10n.t("quick_actions")) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(L10n.t("quick_actions_desc"))
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.4))

                                ForEach(editableQuickActions.indices, id: \.self) { i in
                                    HStack(spacing: 8) {
                                        Image(systemName: editableQuickActions[i].icon)
                                            .font(.system(size: 14))
                                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))
                                            .frame(width: 24)

                                        VStack(spacing: 4) {
                                            TextField(L10n.t("action_name"), text: $editableQuickActions[i].label)
                                                .font(.system(size: 13, weight: .medium))
                                            TextField(L10n.t("action_prompt"), text: $editableQuickActions[i].prompt)
                                                .font(.system(size: 12, weight: .light))
                                                .foregroundColor(Color(hex: "1a1a2e").opacity(0.6))
                                        }

                                        Button(action: {
                                            editableQuickActions.remove(at: i)
                                        }) {
                                            Image(systemName: "minus.circle")
                                                .font(.system(size: 16))
                                                .foregroundColor(.red.opacity(0.5))
                                        }
                                    }
                                    .padding(.vertical, 4)
                                    if i < editableQuickActions.count - 1 {
                                        Divider().opacity(0.1)
                                    }
                                }

                                Button(action: {
                                    editableQuickActions.append(
                                        QuickAction(label: "", prompt: "", icon: "star")
                                    )
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "plus.circle")
                                            .font(.system(size: 14))
                                        Text(L10n.t("add_action"))
                                            .font(.system(size: 13, weight: .light))
                                    }
                                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))
                                }
                                .padding(.top, 4)
                            }
                        }

                        // About section
                        SettingsSection(title: L10n.t("about")) {
                            VStack(alignment: .leading, spacing: 8) {
                                aboutRow(label: L10n.t("version"), value: appVersionString)
                                aboutRow(label: L10n.t("developer"), value: "FxLooper")
                                aboutRow(label: "AI", value: "Claude Opus 4.7")
                                aboutRow(label: "Voice ID", value: "ECAPA-TDNN")
                                aboutRow(label: "STT", value: sttStatusString)
                                aboutRow(label: "TTS", value: "Microsoft Edge TTS")

                                Divider().opacity(0.15).padding(.vertical, 4)

                                Text("🔒 100% lokální komunikace s tvým Mac serverem přes Tailscale VPN. Žádný cloud, žádný tracking, žádná telemetry.")
                                    .font(.system(size: 11, weight: .light))
                                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
        }
        .alert(L10n.t("delete_history_confirm"), isPresented: $showClearHistoryAlert) {
            Button(L10n.t("cancel"), role: .cancel) {}
            Button(L10n.t("delete"), role: .destructive) {
                HapticManager.shared.errorOccurred()
                nova.clearMessages()
            }
        } message: {
            Text(L10n.t("delete_history_msg"))
        }
        .alert(L10n.t("memory_clear_confirm"), isPresented: $showClearMemoryAlert) {
            Button(L10n.t("cancel"), role: .cancel) {}
            Button(L10n.t("delete"), role: .destructive) {
                HapticManager.shared.errorOccurred()
                Task { await nova.clearAllMemory() }
            }
        }
        .fullScreenCover(isPresented: $showVoiceEnrollment) {
            VoiceEnrollmentView()
                .environmentObject(nova)
                .environmentObject(voiceProfile)
        }
    }

    // MARK: - Helper subviews

    private var serverHealthDetailRow: some View {
        let _ = nova.serverHealth.status  // trigger SwiftUI update
        let latency = nova.serverHealth.lastPingLatency
        return HStack(spacing: 6) {
            Circle()
                .fill(serverHealthStatusColor)
                .frame(width: 6, height: 6)
            Text(serverHealthStatusText)
                .font(.system(size: 11, weight: .light))
                .foregroundColor(Color(hex: "1a1a2e").opacity(0.4))
            if latency > 0 {
                Text("(\(Int(latency * 1000))ms)")
                    .font(.system(size: 11, weight: .light))
                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.3))
            }
            Spacer()
            Button(action: {
                HapticManager.shared.selectionChanged()
                Task { await nova.serverHealth.pingNow() }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))
            }
            .accessibilityLabel("Obnovit status serveru")
        }
    }

    private var serverHealthStatusColor: Color {
        switch nova.serverHealth.status {
        case .online: return .green
        case .degraded: return .yellow
        case .offline: return .red
        case .unknown: return Color(hex: "1a1a2e").opacity(0.2)
        }
    }

    private var serverHealthStatusText: String {
        switch nova.serverHealth.status {
        case .online: return "Mac server online"
        case .degraded: return "Mac server pomalý"
        case .offline: return "Mac server nedostupný"
        case .unknown: return "Mac server stav neznámý"
        }
    }

    private func exportConversationText() -> String {
        var lines = [String]()
        lines.append("# Nova konverzace — export")
        lines.append("Datum: \(Date().formatted(date: .long, time: .shortened))")
        lines.append("Počet zpráv: \(nova.messages.count)")
        lines.append("")
        lines.append("---")
        lines.append("")

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm dd.MM.yyyy"

        for msg in nova.messages {
            let role = msg.role == "user" ? userName : "Nova"
            let time = formatter.string(from: msg.timestamp)
            lines.append("**\(role)** _\(time)_")
            lines.append(msg.content)
            lines.append("")
        }

        lines.append("---")
        lines.append("Vygenerováno Novou by FxLooper • 100% privátní data")
        return lines.joined(separator: "\n")
    }

    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (build \(build))"
    }

    private var ttsSpeedLabel: String {
        let pct = Int(ttsSpeed)
        if pct == 0 { return L10n.t("normal") }
        return pct > 0 ? "+\(pct)%" : "\(pct)%"
    }

    private var whisperStatusColor: Color {
        switch nova.whisperState {
        case .ready, .listening, .transcribing: return .green
        case .loading: return .orange
        case .error: return .red
        case .unloaded: return .gray
        }
    }

    private var whisperStatusText: String {
        switch nova.whisperState {
        case .ready, .listening, .transcribing: return L10n.t("stt_connected")
        case .loading: return L10n.t("stt_loading")
        case .error: return L10n.t("stt_error")
        case .unloaded: return L10n.t("stt_offline")
        }
    }

    private var sttStatusString: String {
        if nova.useWhisper {
            switch nova.whisperState {
            case .ready, .listening, .transcribing:
                return "WhisperKit (on-device)"
            case .loading:
                let pct = Int(nova.whisperLoadProgress * 100)
                return "WhisperKit (\(pct)%...)"
            case .unloaded:
                return "WhisperKit (loading...)"
            case .error:
                return "WhisperKit (chyba) + Apple Dictation"
            }
        }
        return "Apple Dictation"
    }

    private func aboutRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .light))
                .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(Color(hex: "1a1a2e").opacity(0.7))
                .monospacedDigit()
        }
    }

    private func autoSave() {
        UserDefaults.standard.set(selectedLang, forKey: "nova_lang")
        UserDefaults.standard.set(selectedCity, forKey: "nova_city")
        UserDefaults.standard.set(selectedVoiceGender, forKey: "nova_voice_gender")
        UserDefaults.standard.set(userName, forKey: "nova_user_name")
        UserDefaults.standard.set(selectedDevProject, forKey: "nova_dev_project")
        let validActions = editableQuickActions.filter { !$0.label.isEmpty && !$0.prompt.isEmpty }
        QuickAction.save(validActions)

        let voices = Self.voiceMap[selectedLang] ?? ("cs-vlasta", "cs-antonin")
        let voice = selectedVoiceGender == "female" ? voices.female : voices.male
        UserDefaults.standard.set(voice, forKey: "nova_voice")

        nova.updateProfile(lang: selectedLang, city: selectedCity, name: userName, voice: voice, voiceGender: selectedVoiceGender)
    }

    private func saveAndDismiss() {
        UserDefaults.standard.set(selectedLang, forKey: "nova_lang")
        UserDefaults.standard.set(selectedCity, forKey: "nova_city")
        UserDefaults.standard.set(selectedVoiceGender, forKey: "nova_voice_gender")
        UserDefaults.standard.set(userName, forKey: "nova_user_name")
        UserDefaults.standard.set(voiceVerifyEnforced, forKey: "nova_voice_verify_enforce")
        UserDefaults.standard.set(selectedDevProject, forKey: "nova_dev_project")
        // Quick actions — ulož jen neprázdné
        let validActions = editableQuickActions.filter { !$0.label.isEmpty && !$0.prompt.isEmpty }
        QuickAction.save(validActions)
        nova.voiceVerificationEnforced = voiceVerifyEnforced

        // Vyber hlas podle jazyka a pohlaví
        let voices = Self.voiceMap[selectedLang] ?? ("cs-vlasta", "cs-antonin")
        let voice = selectedVoiceGender == "female" ? voices.female : voices.male
        UserDefaults.standard.set(voice, forKey: "nova_voice")

        // Update profil v NovaService
        nova.updateProfile(
            lang: selectedLang,
            city: selectedCity,
            name: userName,
            voice: voice,
            voiceGender: selectedVoiceGender
        )

        dismiss()
    }
}

// MARK: - Settings Section
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .medium))
                .tracking(2)
                .foregroundColor(Color(hex: "1a1a2e").opacity(0.3))
            content
        }
    }
}

// MARK: - Voice Button
struct VoiceButton: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(label)
                    .font(.system(size: 13, weight: isSelected ? .medium : .light))
            }
            .foregroundColor(Color(hex: "1a1a2e").opacity(isSelected ? 0.8 : 0.35))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(hex: "1a1a2e").opacity(isSelected ? 0.06 : 0.02))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(hex: "1a1a2e").opacity(isSelected ? 0.15 : 0.06), lineWidth: 1)
            )
        }
    }
}
