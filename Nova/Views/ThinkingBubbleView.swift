import SwiftUI

/// Zen status bubble — shows what Nova is doing right now (like Claude Code's white dot stages)
struct ThinkingBubbleView: View {
    @EnvironmentObject var nova: NovaService

    private var label: String {
        L10n.stage(nova.thinkingStage?.key, detail: nova.thinkingStage?.detail)
    }

    private var transitionId: String {
        "\(nova.thinkingStage?.key ?? "thinking")|\(nova.thinkingStage?.detail ?? "")"
    }

    var body: some View {
        HStack(spacing: 10) {
            // Animated dot — pulzuje bíle jako Claude Code
            ZStack {
                Circle()
                    .fill(Color(hex: "1a1a2e").opacity(0.06))
                    .frame(width: 24, height: 24)

                Circle()
                    .fill(Color(hex: "1a1a2e").opacity(0.5))
                    .frame(width: 7, height: 7)

                // Outer pulse ring
                Circle()
                    .stroke(Color(hex: "1a1a2e").opacity(0.15), lineWidth: 1)
                    .frame(width: 18, height: 18)
            }

            // Stage label s plynulou transition
            Text(label)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundColor(Color(hex: "1a1a2e").opacity(0.65))
                .lineLimit(1)
                .truncationMode(.middle)
                .id(transitionId)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .leading)),
                    removal: .opacity
                ))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(hex: "1a1a2e").opacity(0.05), lineWidth: 0.5)
                )
                .shadow(color: Color(hex: "1a1a2e").opacity(0.04), radius: 8, x: 0, y: 2)
        )
        .padding(.horizontal, 16)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: transitionId)
    }
}
