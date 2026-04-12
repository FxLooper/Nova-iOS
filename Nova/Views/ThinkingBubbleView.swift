import SwiftUI

struct ThinkingBubbleView: View {
    @EnvironmentObject var nova: NovaService

    private var label: String {
        L10n.stage(nova.thinkingStage?.key, detail: nova.thinkingStage?.detail)
    }

    private var transitionId: String {
        "\(nova.thinkingStage?.key ?? "thinking")|\(nova.thinkingStage?.detail ?? "")"
    }

    var body: some View {
        HStack(spacing: 12) {
            ZenSpinner()
                .frame(width: 18, height: 18)

            Text(label)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundColor(Color(hex: "1a1a2e").opacity(0.72))
                .lineLimit(1)
                .truncationMode(.middle)
                .id(transitionId)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity.combined(with: .move(edge: .bottom))
                ))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color(hex: "1a1a2e").opacity(0.06), lineWidth: 0.5)
                )
                .shadow(color: Color(hex: "1a1a2e").opacity(0.05), radius: 8, x: 0, y: 2)
        )
        .padding(.horizontal, 20)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: transitionId)
    }
}

// MARK: - Zen spinner — slow, breathing, not nervous
private struct ZenSpinner: View {
    @State private var rotation: Double = 0
    @State private var pulse: CGFloat = 1.0

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.28)
            .stroke(
                AngularGradient(
                    colors: [
                        Color(hex: "1a1a2e").opacity(0.05),
                        Color(hex: "1a1a2e").opacity(0.55),
                        Color(hex: "1a1a2e").opacity(0.05),
                    ],
                    center: .center
                ),
                style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
            )
            .rotationEffect(.degrees(rotation))
            .scaleEffect(pulse)
            .onAppear {
                withAnimation(.linear(duration: 5).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                    pulse = 0.92
                }
            }
    }
}
