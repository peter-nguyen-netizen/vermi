import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var savedConnections: [RedisConnection] = []
    @Published var openConnections: [ConnectionTab] = []
    @Published var activeTabId: UUID?
    @Published var isLoading: Bool = false
    /// Name of the connection currently being opened (drives a connecting overlay).
    @Published var connectingName: String?
    @Published var errorMessage: String?
    /// Set to present the edit-connection sheet for this connection.
    @Published var editingConnection: RedisConnection?

    struct ConnectionTab: Identifiable {
        let id: UUID
        let connection: RedisConnection
        var redisClient: RedisClientProtocol?
        var selectedTab: MainTab = .keyBrowser
        var latencyMs: Int?
        var connected: Bool = true
        var keyBrowserViewModel: KeyBrowserViewModel?
        var commandExecutorViewModel: CommandExecutorViewModel?
        var pubSubViewModel: PubSubViewModel?
        var analysisViewModel: AnalysisViewModel?
        var monitoringViewModel: MonitoringViewModel?
        var sshTunnel: SSHTunnel?
    }

    enum MainTab: String {
        case keyBrowser = "Keys"
        case commandExecutor = "Console"
        case pubSub = "Pub/Sub"
        case monitoring = "Monitoring"
        case analysis = "Analysis"
    }

    init() {
        loadConnections()
    }

    private func loadConnections() {
        guard let data = UserDefaults.standard.data(forKey: "RedisConnections"),
              let decoded = try? JSONDecoder().decode([RedisConnection].self, from: data) else { return }
        // Rehydrate passwords from the Keychain (they aren't stored in UserDefaults).
        savedConnections = decoded.map { conn in
            var c = conn
            if c.password == nil { c.password = Keychain.get(account: c.id.uuidString) }
            return c
        }
    }

    private func saveConnections() {
        // Store passwords in the Keychain, strip them before persisting to UserDefaults.
        var stripped: [RedisConnection] = []
        for conn in savedConnections {
            Keychain.set(conn.password, account: conn.id.uuidString)
            var c = conn
            c.password = nil
            stripped.append(c)
        }
        if let encoded = try? JSONEncoder().encode(stripped) {
            UserDefaults.standard.set(encoded, forKey: "RedisConnections")
        }
    }

    var activeConnection: RedisConnection? {
        guard let tabId = activeTabId else { return nil }
        return openConnections.first(where: { $0.id == tabId })?.connection
    }

    var activeClient: RedisClientProtocol? {
        guard let tabId = activeTabId else { return nil }
        return openConnections.first(where: { $0.id == tabId })?.redisClient
    }

    var activeKeyBrowserViewModel: KeyBrowserViewModel? {
        guard let tabId = activeTabId else { return nil }
        return openConnections.first(where: { $0.id == tabId })?.keyBrowserViewModel
    }

    var activeCommandExecutorViewModel: CommandExecutorViewModel? {
        guard let tabId = activeTabId else { return nil }
        return openConnections.first(where: { $0.id == tabId })?.commandExecutorViewModel
    }

    var activePubSubViewModel: PubSubViewModel? {
        guard let tabId = activeTabId else { return nil }
        return openConnections.first(where: { $0.id == tabId })?.pubSubViewModel
    }

    var activeAnalysisViewModel: AnalysisViewModel? {
        guard let tabId = activeTabId else { return nil }
        return openConnections.first(where: { $0.id == tabId })?.analysisViewModel
    }

    var activeMonitoringViewModel: MonitoringViewModel? {
        guard let tabId = activeTabId else { return nil }
        return openConnections.first(where: { $0.id == tabId })?.monitoringViewModel
    }

    func addSavedConnection(_ connection: RedisConnection) {
        savedConnections.append(connection)
        saveConnections()
    }

    func updateSavedConnection(_ connection: RedisConnection) {
        if let index = savedConnections.firstIndex(where: { $0.id == connection.id }) {
            savedConnections[index] = connection
            saveConnections()
        }
    }

    func removeSavedConnection(_ connection: RedisConnection) async {
        savedConnections.removeAll { $0.id == connection.id }
        Keychain.remove(account: connection.id.uuidString)
        if let tab = openConnections.first(where: { $0.connection.id == connection.id }) {
            await closeConnectionTab(tab.id)
        }
        saveConnections()
    }

    func openConnectionTab(_ connection: RedisConnection) async {
        // Declared outside the do so we can tear it down if connect fails.
        var tunnel: SSHTunnel?
        do {
            isLoading = true
            connectingName = connection.name
            errorMessage = nil

            // Establish an SSH tunnel first, then point the client at the local end.
            var targetHost = connection.host
            var targetPort = connection.port
            if connection.useSSH {
                let t = SSHTunnel()
                try await t.start(config: .init(
                    sshHost: connection.sshHost,
                    sshPort: connection.sshPort,
                    sshUser: connection.sshUser,
                    keyPath: connection.sshKeyPath,
                    remoteHost: connection.host,
                    remotePort: connection.port
                ))
                targetHost = "127.0.0.1"
                targetPort = await t.localPort
                tunnel = t
            }

            let client = RedisClient(
                host: targetHost,
                port: targetPort,
                useTLS: connection.useTLS,
                password: connection.password,
                database: connection.database,
                isCluster: connection.connectionType == .cluster
            )

            try await client.connect()

            let isConnected = await client.isConnected()
            guard isConnected else {
                throw RESPError.connectionError("Connection failed after connect()")
            }

            let viewModel = KeyBrowserViewModel()
            viewModel.setClient(client)
            viewModel.setConnectionID(connection.id.uuidString)

            let consoleVM = CommandExecutorViewModel()
            consoleVM.setClient(client)
            consoleVM.setConnectionID(connection.id.uuidString)

            let pubSubVM = PubSubViewModel()
            pubSubVM.setClient(client)
            pubSubVM.setConnectionInfo(connection)

            let analysisVM = AnalysisViewModel()
            analysisVM.setClient(client)

            // Per-tab so each open connection polls its own server; a shared
            // view model made every tab show the first connection's metrics.
            let monitoringVM = MonitoringViewModel()
            monitoringVM.setClient(client)

            let tab = ConnectionTab(
                id: UUID(),
                connection: connection,
                redisClient: client,
                keyBrowserViewModel: viewModel,
                commandExecutorViewModel: consoleVM,
                pubSubViewModel: pubSubVM,
                analysisViewModel: analysisVM,
                monitoringViewModel: monitoringVM,
                sshTunnel: tunnel
            )

            openConnections.append(tab)
            activeTabId = tab.id

            var updated = connection
            updated.lastConnected = Date()
            updateSavedConnection(updated)

            ToastCenter.shared.success("Connected to \(connection.name)")
            await measureLatency(tab.id)
        } catch {
            await tunnel?.stop()   // don't leak the ssh process on failure
            ToastCenter.shared.error("Failed to connect to \(connection.name): \(error.localizedDescription)")
        }
        isLoading = false
        connectingName = nil
    }

    /// Ping the tab's connection and record round-trip latency (ms).
    func measureLatency(_ tabId: UUID) async {
        guard let client = openConnections.first(where: { $0.id == tabId })?.redisClient else { return }
        let start = Date()
        let ok = (try? await client.ping()) != nil
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        if let i = openConnections.firstIndex(where: { $0.id == tabId }) {
            openConnections[i].connected = ok
            if ok { openConnections[i].latencyMs = ms }
        }
    }

    func closeConnectionTab(_ tabId: UUID) async {
        if let index = openConnections.firstIndex(where: { $0.id == tabId }) {
            let tab = openConnections[index]
            tab.pubSubViewModel?.reset()
            tab.monitoringViewModel?.stopMonitoring()
            if let client = tab.redisClient as? RedisClient {
                try? await client.disconnect()
            }
            await tab.sshTunnel?.stop()
            let connectionID = tab.connection.id.uuidString
            openConnections.remove(at: index)

            let remaining = openConnections.filter { $0.connection.id == tab.connection.id }
            if remaining.isEmpty {
                ConnectionHistoryStore.release(connectionID)
            }

            if activeTabId == tabId {
                activeTabId = openConnections.last?.id
            }
        }
    }

    func setActiveTab(_ tabId: UUID) {
        activeTabId = tabId
    }

    func setMainTab(_ mainTab: MainTab) {
        guard let tabId = activeTabId,
              let index = openConnections.firstIndex(where: { $0.id == tabId }) else {
            return
        }
        openConnections[index].selectedTab = mainTab
    }
}
