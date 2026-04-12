#if os(iOS)
import Foundation
import ActivityKit

struct NovaActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var stageKey: String
        var stageDetail: String?
        var stageLabel: String
        var startedAt: Date
    }

    var sessionId: String
}
#endif
