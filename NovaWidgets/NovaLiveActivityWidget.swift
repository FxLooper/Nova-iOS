import ActivityKit
import WidgetKit
import SwiftUI

@available(iOS 16.2, *)
struct NovaLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NovaActivityAttributes.self) { context in
            // Lock screen / banner
            LockScreenView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.9))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // ── EXPANDED ──
                DynamicIslandExpandedRegion(.leading) {
                    OrbMiniView(novaState: context.state.novaState)
                        .frame(width: 32, height: 32)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text("Nova")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                        Text(context.state.stageLabel)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VoiceWaveView(novaState: context.state.novaState)
                        .frame(width: 28, height: 20)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 0) {
                        // Elapsed time
                        Text(context.state.startedAt, style: .timer)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                            .monospacedDigit()

                        Spacer()

                        // State dot
                        Circle()
                            .fill(stateColor(context.state.novaState))
                            .frame(width: 6, height: 6)

                        Text(context.state.stageLabel)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.leading, 6)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                }
            } compactLeading: {
                // ── COMPACT (pill) ──
                OrbMiniView(novaState: context.state.novaState)
                    .frame(width: 18, height: 18)
                    .padding(.leading, 2)
            } compactTrailing: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(stateColor(context.state.novaState))
                        .frame(width: 5, height: 5)
                    Text(shortLabel(context.state.novaState))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                }
                .padding(.trailing, 2)
            } minimal: {
                // ── MINIMAL (jen ikonka) ──
                OrbMiniView(novaState: context.state.novaState)
                    .frame(width: 14, height: 14)
            }
            .keylineTint(Color.white.opacity(0.3))
        }
    }

    private func stateColor(_ state: String) -> Color {
        switch state {
        case "listening": return .orange
        case "thinking": return .cyan
        case "speaking": return .green
        default: return .gray
        }
    }

    private func shortLabel(_ state: String) -> String {
        switch state {
        case "listening": return "..."
        case "thinking": return "AI"
        case "speaking": return "Nova"
        default: return ""
        }
    }
}

// MARK: - Mini Orb for Dynamic Island
@available(iOS 16.2, *)
private struct OrbMiniView: View {
    let novaState: String
    @State private var rotation: Double = 0
    @State private var pulse: CGFloat = 1.0

    var body: some View {
        ZStack {
            // Outer ring
            Circle()
                .trim(from: 0, to: trimAmount)
                .stroke(
                    AngularGradient(
                        colors: [
                            ringColor.opacity(0.05),
                            ringColor.opacity(0.9),
                            ringColor.opacity(0.05),
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                )
                .rotationEffect(.degrees(rotation))

            // Core dot
            Circle()
                .fill(ringColor.opacity(0.8))
                .scaleEffect(pulse * 0.35)
        }
        .onAppear {
            withAnimation(.linear(duration: animationSpeed).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse = 0.85
            }
        }
    }

    private var ringColor: Color {
        switch novaState {
        case "listening": return .orange
        case "thinking": return .cyan
        case "speaking": return .green
        default: return .white.opacity(0.5)
        }
    }

    private var trimAmount: CGFloat {
        switch novaState {
        case "listening": return 0.35
        case "thinking": return 0.2
        case "speaking": return 0.5
        default: return 0.25
        }
    }

    private var animationSpeed: Double {
        switch novaState {
        case "listening": return 4.0
        case "thinking": return 1.5
        case "speaking": return 3.0
        default: return 6.0
        }
    }
}

// MARK: - Voice Wave Bars
@available(iOS 16.2, *)
private struct VoiceWaveView: View {
    let novaState: String
    @State private var animate = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(barColor.opacity(0.7))
                    .frame(width: 3, height: animate ? barHeight(i) : 4)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }

    private var barColor: Color {
        switch novaState {
        case "listening": return .orange
        case "speaking": return .green
        default: return .white.opacity(0.4)
        }
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let isActive = novaState == "listening" || novaState == "speaking"
        guard isActive else { return 4 }
        let heights: [CGFloat] = [8, 14, 10, 16]
        return heights[index % heights.count]
    }
}

// MARK: - Lock Screen View
@available(iOS 16.2, *)
private struct LockScreenView: View {
    let state: NovaActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            OrbMiniView(novaState: state.novaState)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Nova")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.65))

                    Text(state.startedAt, style: .timer)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                        .monospacedDigit()
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(stateColor)
                        .frame(width: 6, height: 6)
                    Text(state.stageLabel)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var stateColor: Color {
        switch state.novaState {
        case "listening": return .orange
        case "thinking": return .cyan
        case "speaking": return .green
        default: return .gray
        }
    }
}
