import Foundation
import Network
import Combine

// MARK: - NetworkMonitor
// Sleduje stav sítě a oznamuje změny.
//
// Scénáře které řešíme:
// - Uživatel přejde z WiFi na celulární síť → reconnect WebSocket
// - Tailscale VPN spadne → server health půjde na offline
// - Zařízení usnulo → po probuzení reconnect
// - Uživatel restartoval router → po obnovení reconnect
//
// Nova reaguje:
// - WebSocket reconnect (v NovaService)
// - ServerHealthMonitor okamžitý ping
// - UI update přes published vlastnosti

@MainActor
class NetworkMonitor: ObservableObject {

    enum ConnectionType {
        case wifi
        case cellular
        case wired       // Ethernet, USB
        case loopback    // localhost
        case other
        case none
    }

    @Published private(set) var isConnected: Bool = false
    @Published private(set) var connectionType: ConnectionType = .none
    @Published private(set) var isExpensive: Bool = false  // celulární / hotspot
    @Published private(set) var isConstrained: Bool = false  // low data mode

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.fxlooper.nova.network")

    /// Callback volaný při změně konektivity (z any → connected nebo connected → none)
    var onConnectionChange: ((Bool) -> Void)?

    init() {
        startMonitoring()
    }

    deinit {
        monitor.cancel()
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.handlePathUpdate(path)
            }
        }
        monitor.start(queue: queue)
    }

    private func handlePathUpdate(_ path: NWPath) {
        let wasConnected = isConnected
        let oldType = connectionType
        let nowConnected = path.status == .satisfied

        isConnected = nowConnected
        isExpensive = path.isExpensive
        isConstrained = path.isConstrained

        // Determine connection type
        if path.usesInterfaceType(.wifi) {
            connectionType = .wifi
        } else if path.usesInterfaceType(.cellular) {
            connectionType = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            connectionType = .wired
        } else if path.usesInterfaceType(.loopback) {
            connectionType = .loopback
        } else if path.status == .satisfied {
            connectionType = .other
        } else {
            connectionType = .none
        }

        print("[network] status=\(nowConnected ? "ONLINE" : "OFFLINE") type=\(connectionType) expensive=\(isExpensive)")

        // Notify callback if status flipped OR connection type changed (e.g. WiFi → Cellular)
        if wasConnected != nowConnected || (nowConnected && oldType != connectionType) {
            onConnectionChange?(nowConnected)
        }
    }
}
