import Foundation

@MainActor
final class MonitoringViewModel: NSObject, ObservableObject {
    @Published var serverInfo: RedisInfo?
    // Empty until the first poll fills them — drives the skeleton placeholder.
    @Published var uptime: String = ""
    @Published var usedMemory: String = ""
    @Published var maxMemory: String = ""
    @Published var connectedClients: String = ""
    @Published var commandsPerSecond: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var refreshInterval: TimeInterval = 5.0

    /// Raw INFO output from the last fetch, for the Export action.
    private(set) var rawInfoString: String = ""

    private var redisClient: RedisClientProtocol?
    private var refreshTimer: Timer?

    /// Exposed for tests that assert the poll timer isn't duplicated.
    var activeTimerForTesting: Timer? { refreshTimer }

    func setClient(_ client: RedisClientProtocol) {
        self.redisClient = client
    }

    func startMonitoring() {
        // Never stack timers: re-entering the tab or changing the interval
        // must replace the running one, not add a second poller.
        stopMonitoring()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { _ in
            Task { @MainActor [weak self] in
                await self?.fetchMetrics()
            }
        }
        Task {
            await fetchMetrics()
        }
    }

    /// Change the poll interval and restart the timer with it.
    func setRefreshInterval(_ interval: TimeInterval) {
        refreshInterval = interval
        stopMonitoring()
        startMonitoring()
    }

    func stopMonitoring() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func fetchMetrics() async {
        guard let client = redisClient else {
            errorMessage = "No connection"
            return
        }

        do {
            // Only show the spinner on the first load — periodic refreshes
            // shouldn't toggle layout (caused visible jitter every 5s).
            if serverInfo == nil { isLoading = true }
            errorMessage = nil

            let infoString = try await client.info(section: nil)
            rawInfoString = infoString
            serverInfo = RedisInfo.parse(infoString: infoString)

            if let info = serverInfo {
                uptime = formatUptime(info.server["uptime_in_seconds"] ?? "0")
                usedMemory = formatBytes(info.memory["used_memory"] ?? "0")
                maxMemory = formatBytes(info.memory["maxmemory"] ?? "0")
                connectedClients = info.clients["connected_clients"] ?? "—"

                if let totalCommands = info.stats["total_commands_processed"],
                   let uptimeSeconds = info.server["uptime_in_seconds"] {
                    if let cmds = Int(totalCommands), let uptime = Int(uptimeSeconds), uptime > 0 {
                        let cps = Double(cmds) / Double(uptime)
                        commandsPerSecond = String(format: "%.2f ops/sec", cps)
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func formatBytes(_ bytesStr: String) -> String {
        guard let bytes = Int64(bytesStr) else { return bytesStr }
        let units = ["B", "KB", "MB", "GB"]
        var value = Double(bytes)
        var unitIndex = 0

        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        return String(format: "%.2f %@", value, units[unitIndex])
    }

    private func formatUptime(_ secondsStr: String) -> String {
        guard let seconds = Int(secondsStr) else { return secondsStr }
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60

        if days > 0 {
            return "\(days)d \(hours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    func reset() {
        stopMonitoring()
        serverInfo = nil
        uptime = ""
        usedMemory = ""
        maxMemory = ""
        connectedClients = ""
        commandsPerSecond = ""
        errorMessage = nil
    }

    deinit {
        refreshTimer?.invalidate()
    }
}
