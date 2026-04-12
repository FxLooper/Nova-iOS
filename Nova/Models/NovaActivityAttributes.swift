#if os(iOS)
import Foundation
import ActivityKit

struct NovaActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var novaState: String       // "listening", "thinking", "speaking", "idle"
        var stageLabel: String      // Zobrazený text ("Poslouchám", "Přemýšlím"...)
        var startedAt: Date
        var isVoiceConversation: Bool
    }

    var sessionId: String
}
#endif
