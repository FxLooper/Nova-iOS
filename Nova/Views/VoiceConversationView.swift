import SwiftUI

/// Fullscreen voice-only conversation — orb centered, no text, pure voice interaction
struct VoiceConversationView: View {
    @EnvironmentObject var nova: NovaService
    @Binding var isPresented: Bool
    @State private var showCamera = false

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
                OrbWebView(state: nova.state.rawValue, audioLevel: 0)
                    .frame(width: 280, height: 280)

                // State label
                Text(stateLabel)
                    .font(.system(size: 12, weight: .light))
                    .tracking(4)
                    .foregroundColor(Color(hex: "1a1a2e").opacity(stateOpacity))
                    .padding(.top, 12)
                    .animation(.easeInOut(duration: 0.3), value: nova.state)

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
            if !nova.conversationActive {
                nova.toggleConversation()
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
        case .listening: return "POSLOUCHÁM"
        case .thinking: return "PŘEMÝŠLÍM"
        case .speaking: return "ODPOVÍDÁM"
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
