import Foundation
import Combine

// MARK: - ServerHealthMonitor
// Monitoruje dostupnost Mac serveru a zveřejňuje status pro UI.
//
// Periodický ping na /api/voice/status každých 10s.
// Adaptivní backoff: pokud server padne, ping se zpomaluje (10s → 30s → 60s).
// Při úspěšném pingu se vrátí na 10s.
//
// Použití:
//   nova.serverHealth.status  // .online / .offline / .degraded
//   nova.serverHealth.startMonitoring(serverURL:token:)

@MainActor
class ServerHealthMonitor: ObservableObject {

    enum HealthStatus: Equatable {
        case unknown   // ještě nepingnuto
        case online    // server odpovídá pod 1s
        case degraded  // server odpovídá ale pomalu (>2s)
        case offline   // ping selhal
    }

    @Published private(set) var status: HealthStatus = .unknown
    @Published private(set) var lastPingTime: Date?
    @Published private(set) var lastPingLatency: TimeInterval = 0
    @Published private(set) var voiceEmbedderReady: Bool = false

    private var serverURL: String = ""
    private var token: String = ""
    private var monitorTask: Task<Void, Never>?
    private var consecutiveFailures: Int = 0

    deinit {
        monitorTask?.cancel()
    }

    // Adaptive ping interval (1s on success, exponential backoff on failure)
    private var pingInterval: TimeInterval {
        switch consecutiveFailures {
        case 0: return 10.0
        case 1...3: return 20.0
        case 4...6: return 45.0
        default: return 90.0
        }
    }

    func startMonitoring(serverURL: String, token: String) {
        self.serverURL = serverURL
        self.token = token

        guard !serverURL.isEmpty else {
            status = .unknown
            return
        }

        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.ping()
                let interval = self?.pingInterval ?? 30.0
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
        status = .unknown
        consecutiveFailures = 0
    }

    /// Force immediate ping (for manual refresh)
    func pingNow() async {
        await ping()
    }

    private func ping() async {
        guard !serverURL.isEmpty else { return }
        guard let url = URL(string: "\(serverURL)/api/voice/status") else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue(token, forHTTPHeaderField: "X-Nova-Token")

        let startTime = Date()

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let elapsed = Date().timeIntervalSince(startTime)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw NSError(domain: "ServerHealth", code: -1)
            }

            // Parse voice embedder ready status
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ready = json["ready"] as? Bool {
                voiceEmbedderReady = ready
            }

            consecutiveFailures = 0
            lastPingTime = Date()
            lastPingLatency = elapsed

            // Status based on latency
            if elapsed < 1.0 {
                status = .online
            } else {
                status = .degraded
            }
        } catch {
            consecutiveFailures += 1
            voiceEmbedderReady = false
            if consecutiveFailures >= 2 {
                status = .offline
            }
            lastPingTime = Date()
        }
    }
}
