#if os(iOS)
import Foundation
import ActivityKit

@available(iOS 16.2, *)
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var activity: Activity<NovaActivityAttributes>?
    private var sessionId: String = UUID().uuidString

    private init() {}

    var isAuthorized: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    var isActive: Bool { activity != nil }

    func startVoiceConversation(state: String, label: String) {
        guard isAuthorized else {
            print("[live-activity] not authorized")
            return
        }
        if activity != nil {
            update(state: state, label: label)
            return
        }
        sessionId = UUID().uuidString
        let attrs = NovaActivityAttributes(sessionId: sessionId)
        let content = NovaActivityAttributes.ContentState(
            novaState: state,
            stageLabel: label,
            startedAt: Date(),
            isVoiceConversation: true
        )
        do {
            activity = try Activity.request(
                attributes: attrs,
                content: .init(state: content, staleDate: nil),
                pushType: nil
            )
            print("[live-activity] started voice conversation")
        } catch {
            print("[live-activity] start failed: \(error)")
        }
    }

    func update(state: String, label: String) {
        guard let activity else { return }
        let content = NovaActivityAttributes.ContentState(
            novaState: state,
            stageLabel: label,
            startedAt: activity.content.state.startedAt,
            isVoiceConversation: activity.content.state.isVoiceConversation
        )
        Task {
            await activity.update(.init(state: content, staleDate: nil))
        }
    }

    func end() {
        guard let activity else { return }
        let final = activity.content.state
        Task {
            await activity.end(.init(state: final, staleDate: nil), dismissalPolicy: .immediate)
        }
        self.activity = nil
        print("[live-activity] ended")
    }
}
#endif
