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

    init() {
        _selectedLang = State(initialValue: UserDefaults.standard.string(forKey: "nova_lang") ?? "cs")
        _selectedCity = State(initialValue: UserDefaults.standard.string(forKey: "nova_city") ?? "Plzeň")
        _selectedVoiceGender = State(initialValue: UserDefaults.standard.string(forKey: "nova_voice_gender") ?? "female")
        _userName = State(initialValue: UserDefaults.standard.string(forKey: "nova_user_name") ?? "Ondřej")
        _useWhisper = State(initialValue: UserDefaults.standard.bool(forKey: "nova_use_whisper"))
        _voiceVerifyEnforced = State(initialValue: UserDefaults.standard.bool(forKey: "nova_voice_verify_enforce"))
    }

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
                    Button(action: { saveAndDismiss() }) {
                        Text(L10n.t("save"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.7))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

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
                        }

                        // Server info
                        // Speech Recognition Engine
                        SettingsSection(title: "Rozpoznávání řeči") {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle(isOn: $useWhisper) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Whisper (experimentální)")
                                            .font(.system(size: 15, weight: .regular))
                                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.8))
                                        Text(useWhisper ? "On-device, auto-detect jazyka" : "Apple DictationTranscriber")
                                            .font(.system(size: 12, weight: .light))
                                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))
                                    }
                                }
                                .tint(Color(hex: "1a1a2e").opacity(0.7))

                                if nova.whisperState == .loading {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                        Text("Stahuji model... \(Int(nova.whisperLoadProgress * 100))%")
                                            .font(.system(size: 12, weight: .light))
                                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))
                                    }
                                } else if case .error(let msg) = nova.whisperState {
                                    Text("⚠️ \(msg)")
                                        .font(.system(size: 12, weight: .light))
                                        .foregroundColor(.red.opacity(0.7))
                                } else if nova.whisperState == .ready && useWhisper {
                                    Text("✅ Model načten, připraven")
                                        .font(.system(size: 12, weight: .light))
                                        .foregroundColor(.green.opacity(0.7))
                                }
                            }
                        }

                        // Voice ID (Voice Biometrics)
                        SettingsSection(title: "Voice ID") {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 12) {
                                    Image(systemName: voiceProfile.state == .enrolled ? "checkmark.seal.fill" : "waveform.circle")
                                        .font(.system(size: 32, weight: .ultraLight))
                                        .foregroundColor(voiceProfile.state == .enrolled ? .green.opacity(0.7) : Color(hex: "1a1a2e").opacity(0.5))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(voiceProfile.state == .enrolled ? "Hlasový profil aktivní" : "Hlasový profil nevytvořen")
                                            .font(.system(size: 15, weight: .regular))
                                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.8))
                                        Text(voiceProfile.state == .enrolled ? "Nova reaguje jen na tebe" : "Face ID pro tvůj hlas")
                                            .font(.system(size: 12, weight: .light))
                                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))
                                    }
                                    Spacer()
                                }

                                Button(action: { showVoiceEnrollment = true }) {
                                    Text(voiceProfile.state == .enrolled ? "Spravovat profil" : "Vytvořit profil")
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
                                            Text("Vyžadovat ověření hlasu")
                                                .font(.system(size: 15, weight: .regular))
                                                .foregroundColor(Color(hex: "1a1a2e").opacity(0.8))
                                            Text(voiceVerifyEnforced
                                                 ? "Nova reaguje jen pokud poznám tvůj hlas"
                                                 : "Nova reaguje na všechny mluvčí")
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
                                            Text("Poslední shoda: \(Int(voiceProfile.verificationConfidence * 100))%")
                                                .font(.system(size: 12, weight: .light))
                                                .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))
                                        }
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
                                HStack {
                                    Circle()
                                        .fill(nova.isConnected ? Color.green.opacity(0.6) : Color.red.opacity(0.4))
                                        .frame(width: 8, height: 8)
                                    Text(nova.isConnected ? L10n.t("connected") : L10n.t("disconnected"))
                                        .font(.system(size: 14, weight: .light))
                                        .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))
                                }

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
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
        }
        .fullScreenCover(isPresented: $showVoiceEnrollment) {
            VoiceEnrollmentView()
                .environmentObject(nova)
                .environmentObject(voiceProfile)
        }
    }

    private func saveAndDismiss() {
        UserDefaults.standard.set(selectedLang, forKey: "nova_lang")
        UserDefaults.standard.set(selectedCity, forKey: "nova_city")
        UserDefaults.standard.set(selectedVoiceGender, forKey: "nova_voice_gender")
        UserDefaults.standard.set(userName, forKey: "nova_user_name")
        UserDefaults.standard.set(useWhisper, forKey: "nova_use_whisper")
        UserDefaults.standard.set(voiceVerifyEnforced, forKey: "nova_voice_verify_enforce")
        nova.setUseWhisper(useWhisper)
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
