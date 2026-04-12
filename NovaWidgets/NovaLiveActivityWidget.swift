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
                    Image(systemName: stateIcon(context.state.novaState))
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(stateColor(context.state.novaState))
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text("Nova")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                        Text(context.state.stageLabel)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundColor(stateColor(context.state.novaState))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.startedAt, style: .timer)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                        .monospacedDigit()
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        // State bar
                        ForEach(0..<3, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(i == stateIndex(context.state.novaState)
                                    ? stateColor(context.state.novaState)
                                    : Color.white.opacity(0.1))
                                .frame(height: 3)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                }
            } compactLeading: {
                // ── COMPACT (pill) ──
                Image(systemName: stateIcon(context.state.novaState))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(stateColor(context.state.novaState))
            } compactTrailing: {
                Text(shortLabel(context.state.novaState))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(stateColor(context.state.novaState))
            } minimal: {
                Image(systemName: stateIcon(context.state.novaState))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(stateColor(context.state.novaState))
            }
            .keylineTint(stateColor(context.state.novaState).opacity(0.5))
        }
    }

    private func stateColor(_ state: String) -> Color {
        switch state {
        case "listening": return .orange
        case "thinking": return .cyan
        case "speaking": return .green
        default: return .white.opacity(0.5)
        }
    }

    private func stateIcon(_ state: String) -> String {
        switch state {
        case "listening": return "waveform"
        case "thinking": return "brain"
        case "speaking": return "speaker.wave.2.fill"
        default: return "circle.fill"
        }
    }

    private func stateIndex(_ state: String) -> Int {
        switch state {
        case "listening": return 0
        case "thinking": return 1
        case "speaking": return 2
        default: return -1
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

// MARK: - Lock Screen View
@available(iOS 16.2, *)
private struct LockScreenView: View {
    let state: NovaActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: stateIcon)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(stateColor)
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

    private var stateIcon: String {
        switch state.novaState {
        case "listening": return "waveform"
        case "thinking": return "brain"
        case "speaking": return "speaker.wave.2.fill"
        default: return "circle.fill"
        }
    }
}
