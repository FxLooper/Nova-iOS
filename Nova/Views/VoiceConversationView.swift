import SwiftUI

/// Fullscreen voice-only conversation — orb centered, no text, pure voice interaction
struct VoiceConversationView: View {
    @EnvironmentObject var nova: NovaService
    @Binding var isPresented: Bool
    @State private var showCamera = false
    @State private var isInitializing = true

    var body: some View {
        ZStack {
            NovaBackground()

            VStack(spacing: 0) {
                // Top bar: close + camera
                HStack {
                    Button(action: { endAndDismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .light))
                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.4))
                            .frame(width: 44, height: 44)
                    }

                    Spacer()

                    Button(action: { showCamera = true }) {
                        Image(systemName: "camera")
                            .font(.system(size: 18, weight: .light))
                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.4))
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // Session / DEV / WEB banner
                if nova.activeSession != nil || nova.isDevMode || nova.isWebMode {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(nova.isDevMode ? Color.blue.opacity(0.8) : Color.green.opacity(0.8))
                            .frame(width: 8, height: 8)
                            .scaleEffect(1.2)
                        Text(nova.activeSession != nil ? "DEV SESSION" : (nova.isDevMode ? "DEV" : "WEB"))
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(3)
                            .foregroundColor(nova.isDevMode || nova.activeSession != nil ? .blue.opacity(0.7) : .green.opacity(0.7))
                        if let session = nova.activeSession {
                            Text("·")
                                .foregroundColor(Color(hex: "1a1a2e").opacity(0.2))
                            Text(session)
                                .font(.system(size: 11, weight: .light))
                                .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))
                        }
                        if let stage = nova.thinkingStage {
                            Text("·")
                                .foregroundColor(Color(hex: "1a1a2e").opacity(0.2))
                            Text(L10n.stage(stage.key, detail: stage.detail))
                                .font(.system(size: 11, weight: .light))
                                .foregroundColor(Color(hex: "1a1a2e").opacity(0.4))
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background((nova.isDevMode ? Color.blue : Color.green).opacity(0.06))
                    .cornerRadius(10)
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.3), value: nova.isDevMode)
                    .animation(.easeInOut(duration: 0.3), value: nova.isWebMode)
                }

                Spacer()

                // Orb — large, centered, reactive
                // Tap = přeruš mluvení a začni poslouchat
                OrbWebView(state: isInitializing ? "thinking" : nova.state.rawValue, audioLevel: 0)
                    .frame(width: 280, height: 280)
                    .opacity(isInitializing ? 0.6 : 1.0)
                    .animation(.easeInOut(duration: 0.5), value: isInitializing)
                    .onTapGesture {
                        if nova.state == .speaking {
                            HapticManager.shared.selectionChanged()
                            nova.interruptAndListen()
                        }
                    }

                // State label + stage detail
                VStack(spacing: 6) {
                    Text(isInitializing ? L10n.t("starting_conversation").uppercased() : stateLabel)
                        .font(.system(size: 12, weight: .light))
                        .tracking(4)
                        .foregroundColor(Color(hex: "1a1a2e").opacity(isInitializing ? 0.5 : stateOpacity))

                    // Stage detail — co Nova právě dělá (hledám na webu, čtu soubor...)
                    if !isInitializing, let stage = nova.thinkingStage {
                        Text(L10n.stage(stage.key, detail: stage.detail))
                            .font(.system(size: 11, weight: .light))
                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.35))
                            .transition(.opacity)
                    }
                }
                .padding(.top, 12)
                .animation(.easeInOut(duration: 0.3), value: nova.state)
                .animation(.easeInOut(duration: 0.3), value: isInitializing)
                .animation(.easeInOut(duration: 0.3), value: nova.thinkingStage)

                // Dev logs — live stream co Nova dělá (jen když běží dev mode)
                if nova.isDevMode && !nova.devLogs.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        // Header
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.blue.opacity(0.7))
                                .frame(width: 6, height: 6)
                            Text("DEV")
                                .font(.system(size: 10, weight: .medium))
                                .tracking(2)
                                .foregroundColor(.blue.opacity(0.6))
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                        // Log lines — posledních 8 řádků
                        ScrollView {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(Array(nova.devLogs.suffix(8).enumerated()), id: \.offset) { _, log in
                                    Text(log)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(devLogColor(log))
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                        }
                        .frame(maxHeight: 120)
                    }
                    .background(Color(hex: "1a1a2e").opacity(0.04))
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Spacer()

                // Bottom: end call button
                Button(action: { endAndDismiss() }) {
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.15))
                            .frame(width: 64, height: 64)
                        Image(systemName: "phone.down.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.red.opacity(0.8))
                    }
                }
                .padding(.bottom, 48)
            }
        }
        .onAppear {
            isInitializing = true
            // Počkej až WhisperKit bude ready + OrbWebView se načte
            Task {
                // Počkej na whisper (max 30s)
                for _ in 0..<60 {
                    if nova.whisperState == .ready { break }
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
                // Počkej na OrbWebView GPU launch
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    if !nova.conversationActive {
                        nova.toggleConversation()
                    }
                    withAnimation(.easeOut(duration: 0.4)) {
                        isInitializing = false
                    }
                }
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraCaptureView { image in
                showCamera = false
                guard let image = image else { return }
                Task {
                    await nova.sendMessage("[Fotka pořízena — popis: \(image.size.width)x\(image.size.height)]")
                }
            }
        }
    }

    private var stateLabel: String {
        switch nova.state {
        case .idle: return ""
        case .listening: return L10n.t("listening").uppercased()
        case .thinking: return L10n.t("thinking").uppercased()
        case .speaking: return L10n.t("speaking").uppercased()
        }
    }

    private var stateOpacity: Double {
        nova.state == .idle ? 0.2 : 0.45
    }

    private func endAndDismiss() {
        nova.endConversation()
        isPresented = false
    }

    private func devLogColor(_ log: String) -> Color {
        if log.contains("📖") || log.contains("Read") { return .green.opacity(0.7) }
        if log.contains("✏️") || log.contains("Edit") { return .orange.opacity(0.7) }
        if log.contains("📝") || log.contains("Write") { return .yellow.opacity(0.7) }
        if log.contains("$") || log.contains("Bash") { return .cyan.opacity(0.7) }
        if log.contains("🔍") || log.contains("Glob") { return .purple.opacity(0.7) }
        if log.contains("🔎") || log.contains("Grep") { return .indigo.opacity(0.7) }
        if log.contains("🚀") { return .blue.opacity(0.7) }
        return Color(hex: "1a1a2e").opacity(0.5)
    }
}
