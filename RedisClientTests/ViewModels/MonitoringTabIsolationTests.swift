import XCTest
@testable import RedisClient

/// Regression tests for the Monitoring tab showing stale data when several
/// connections are open at once: the monitoring view model must be per
/// connection tab (like the key browser / console / pub-sub ones) and must
/// follow `activeTabId`.
@MainActor
final class MonitoringTabIsolationTests: XCTestCase {

    private func info(uptime: String, usedMemory: String, clients: String) -> String {
        """
        # Server
        redis_version:7.2.4
        uptime_in_seconds:\(uptime)
        # Clients
        connected_clients:\(clients)
        # Memory
        used_memory:\(usedMemory)
        maxmemory:0
        # Stats
        total_commands_processed:1000
        """
    }

    private func makeTab(name: String, client: RedisClientProtocol) -> AppState.ConnectionTab {
        let monitoringVM = MonitoringViewModel()
        monitoringVM.setClient(client)
        return AppState.ConnectionTab(
            id: UUID(),
            connection: RedisConnection(name: name, host: "127.0.0.1"),
            redisClient: client,
            monitoringViewModel: monitoringVM
        )
    }

    /// Each open connection owns its own monitoring view model, and the active
    /// accessor follows `activeTabId`.
    func testActiveMonitoringViewModelFollowsActiveTab() {
        let appState = AppState()
        let tabA = makeTab(name: "A", client: MockRedisClient())
        let tabB = makeTab(name: "B", client: MockRedisClient())
        appState.openConnections = [tabA, tabB]

        appState.activeTabId = tabA.id
        XCTAssertTrue(appState.activeMonitoringViewModel === tabA.monitoringViewModel)

        appState.activeTabId = tabB.id
        XCTAssertTrue(appState.activeMonitoringViewModel === tabB.monitoringViewModel)
        XCTAssertFalse(tabA.monitoringViewModel === tabB.monitoringViewModel)
    }

    /// Switching the active tab surfaces the other server's metrics, not the
    /// first connection's cached numbers.
    func testMetricsAreNotSharedBetweenConnections() async throws {
        let clientA = MockRedisClient()
        await clientA.setInfo(info(uptime: "120", usedMemory: "1048576", clients: "3"))
        let clientB = MockRedisClient()
        await clientB.setInfo(info(uptime: "7200", usedMemory: "2097152", clients: "9"))

        let appState = AppState()
        let tabA = makeTab(name: "A", client: clientA)
        let tabB = makeTab(name: "B", client: clientB)
        appState.openConnections = [tabA, tabB]

        appState.activeTabId = tabA.id
        await appState.activeMonitoringViewModel?.fetchMetrics()
        XCTAssertEqual(appState.activeMonitoringViewModel?.connectedClients, "3")
        XCTAssertEqual(appState.activeMonitoringViewModel?.usedMemory, "1.00 MB")
        XCTAssertEqual(appState.activeMonitoringViewModel?.uptime, "2m")

        appState.activeTabId = tabB.id
        await appState.activeMonitoringViewModel?.fetchMetrics()
        XCTAssertEqual(appState.activeMonitoringViewModel?.connectedClients, "9")
        XCTAssertEqual(appState.activeMonitoringViewModel?.usedMemory, "2.00 MB")
        XCTAssertEqual(appState.activeMonitoringViewModel?.uptime, "2h 0m")

        // Tab A keeps its own numbers untouched.
        XCTAssertEqual(tabA.monitoringViewModel?.connectedClients, "3")
    }

    /// Restarting monitoring must not leave the previous timer running.
    func testStartMonitoringTwiceKeepsOneTimer() {
        let vm = MonitoringViewModel()
        vm.setClient(MockRedisClient())
        vm.startMonitoring()
        let first = vm.activeTimerForTesting
        vm.startMonitoring()
        let second = vm.activeTimerForTesting
        XCTAssertFalse(first === second)
        XCTAssertEqual(first?.isValid, false)
        XCTAssertEqual(second?.isValid, true)
        vm.stopMonitoring()
    }
}
