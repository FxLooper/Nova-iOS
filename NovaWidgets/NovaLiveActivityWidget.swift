import ActivityKit
import WidgetKit
import SwiftUI

@available(iOS 16.2, *)
struct NovaLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NovaActivityAttributes.self) { context in
            // Lock screen / banner UI
            LockScreenView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ZenSpinnerView()
                        .frame(width: 26, height: 26)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("Nova")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.stageLabel)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                ZenSpinnerView()
                    .frame(width: 16, height: 16)
            } compactTrailing: {
                Text(shortLabel(context.state.stageLabel))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                    .frame(maxWidth: 80)
            } minimal: {
                ZenSpinnerView()
                    .frame(width: 14, height: 14)
            }
            .keylineTint(Color.white.opacity(0.4))
        }
    }

    private func shortLabel(_ s: String) -> String {
        s.count > 14 ? String(s.prefix(13)) + "…" : s
    }
}

@available(iOS 16.2, *)
private struct LockScreenView: View {
    let state: NovaActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            ZenSpinnerView()
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text("Nova")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))
                Text(state.stageLabel)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

private struct ZenSpinnerView: View {
    @State private var rotation: Double = 0
    @State private var pulse: CGFloat = 1.0

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.28)
            .stroke(
                AngularGradient(
                    colors: [
                        Color.white.opacity(0.05),
                        Color.white.opacity(0.85),
                        Color.white.opacity(0.05),
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
