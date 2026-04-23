import ActivityKit
import WidgetKit
import SwiftUI

struct NovaLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NovaActivityAttributes.self) { context in
            // Lock screen / banner
            LockScreenView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.9))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "nova://conversation"))
        } dynamicIsland: { context in
            DynamicIsland {
                // ── EXPANDED ──
                DynamicIslandExpandedRegion(.leading) {
                    StateIcon(state: context.state.novaState, size: 22)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text("Nova")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                        Text(context.state.stageLabel)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundColor(Self.stateColor(context.state.novaState))
                            .contentTransition(.opacity)
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
                        // State progress — tři sekce podle fáze (listening → thinking → speaking)
                        ForEach(0..<3, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(i <= Self.stateIndex(context.state.novaState)
                                    ? Self.stateColor(context.state.novaState)
                                    : Color.white.opacity(0.1))
                                .frame(height: 3)
                                .animation(.easeInOut(duration: 0.3), value: context.state.novaState)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                }
            } compactLeading: {
                // ── COMPACT (pill) ──
                StateIcon(state: context.state.novaState, size: 14)
            } compactTrailing: {
                // Brand "Nova" text místo matoucích "..."
                Text("Nova")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(Self.stateColor(context.state.novaState))
                    .contentTransition(.opacity)
            } minimal: {
                StateIcon(state: context.state.novaState, size: 12)
            }
            .keylineTint(Self.stateColor(context.state.novaState).opacity(0.5))
            .widgetURL(URL(string: "nova://conversation"))
        }
    }

    // MARK: - State helpers
    static func stateColor(_ state: String) -> Color {
        switch state {
        case "listening": return .orange
        case "thinking": return .cyan
        case "speaking": return .green
        default: return .white.opacity(0.5)
        }
    }

    static func stateIcon(_ state: String) -> String {
        switch state {
        case "listening": return "waveform"
        case "thinking": return "brain"
        case "speaking": return "speaker.wave.2.fill"
        default: return "circle.fill"
        }
    }

    static func stateIndex(_ state: String) -> Int {
        switch state {
        case "listening": return 0
        case "thinking": return 1
        case "speaking": return 2
        default: return -1
        }
    }
}

// MARK: - Animated state icon
private struct StateIcon: View {
    let state: String
    let size: CGFloat

    var body: some View {
        let icon = Image(systemName: NovaLiveActivityWidget.stateIcon(state))
            .font(.system(size: size, weight: .semibold))
            .foregroundColor(NovaLiveActivityWidget.stateColor(state))
            .contentTransition(.symbolEffect(.replace))

        if #available(iOS 17.0, *) {
            switch state {
            case "listening":
                icon.symbolEffect(.variableColor.iterative, options: .repeating)
            case "thinking":
                icon.symbolEffect(.pulse, options: .repeating)
            case "speaking":
                icon.symbolEffect(.variableColor.cumulative, options: .repeating)
            default:
                icon
            }
        } else {
            icon
        }
    }
}

// MARK: - Lock Screen View
private struct LockScreenView: View {
    let state: NovaActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            StateIcon(state: state.novaState, size: 22)
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
                        .contentTransition(.opacity)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var stateColor: Color {
        NovaLiveActivityWidget.stateColor(state.novaState)
    }
}
