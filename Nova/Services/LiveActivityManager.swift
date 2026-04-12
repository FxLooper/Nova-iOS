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

    func start(stageKey: String, stageDetail: String?, label: String) {
        guard isAuthorized else { return }
        if activity != nil {
            update(stageKey: stageKey, stageDetail: stageDetail, label: label)
            return
        }
        sessionId = UUID().uuidString
        let attrs = NovaActivityAttributes(sessionId: sessionId)
        let state = NovaActivityAttributes.ContentState(
            stageKey: stageKey,
            stageDetail: stageDetail,
            stageLabel: label,
            startedAt: Date()
        )
        do {
            activity = try Activity.request(
                attributes: attrs,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            print("[live-activity] start failed: \(error)")
        }
    }

    func update(stageKey: String, stageDetail: String?, label: String) {
        guard let activity else { return }
        let state = NovaActivityAttributes.ContentState(
            stageKey: stageKey,
            stageDetail: stageDetail,
            stageLabel: label,
            startedAt: activity.content.state.startedAt
        )
        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    func end() {
        guard let activity else { return }
        let final = activity.content.state
        Task {
            await activity.end(.init(state: final, staleDate: nil), dismissalPolicy: .immediate)
        }
        self.activity = nil
    }
}
#endif
