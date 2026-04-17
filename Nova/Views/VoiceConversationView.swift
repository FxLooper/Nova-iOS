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

                // State label
                Text(isInitializing ? L10n.t("starting_conversation").uppercased() : stateLabel)
                    .font(.system(size: 12, weight: .light))
                    .tracking(4)
                    .foregroundColor(Color(hex: "1a1a2e").opacity(isInitializing ? 0.5 : stateOpacity))
                    .padding(.top, 12)
                    .animation(.easeInOut(duration: 0.3), value: nova.state)
                    .animation(.easeInOut(duration: 0.3), value: isInitializing)

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
}
