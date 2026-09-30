import Foundation

struct RedisConnection: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var host: String
    var port: UInt16
    var password: String?
    var useTLS: Bool
    var tlsVerify: Bool
    var connectionType: ConnectionType
    var database: Int
    var lastConnected: Date?
    var isFavorite: Bool
    var colorTag: String?

    // SSH tunnel (optional). When enabled, Vermi connects to host:port through
    // a local port forwarded over `ssh -L` to the bastion.
    var useSSH: Bool
    var sshHost: String
    var sshPort: UInt16
    var sshUser: String
    var sshKeyPath: String   // optional identity file (empty = use agent/config)

    enum ConnectionType: String, Codable, Sendable {
        case single
        case sentinel
        case cluster
    }

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: UInt16 = 6379,
        password: String? = nil,
        useTLS: Bool = false,
        tlsVerify: Bool = true,
        connectionType: ConnectionType = .single,
        database: Int = 0,
        lastConnected: Date? = nil,
        isFavorite: Bool = false,
        colorTag: String? = nil,
        useSSH: Bool = false,
        sshHost: String = "",
        sshPort: UInt16 = 22,
        sshUser: String = "",
        sshKeyPath: String = ""
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.password = password
        self.useTLS = useTLS
        self.tlsVerify = tlsVerify
        self.connectionType = connectionType
        self.database = database
        self.lastConnected = lastConnected
        self.isFavorite = isFavorite
        self.colorTag = colorTag
        self.useSSH = useSSH
        self.sshHost = sshHost
        self.sshPort = sshPort
        self.sshUser = sshUser
        self.sshKeyPath = sshKeyPath
    }

    // Custom decoding so older persisted connections (without SSH fields) still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        host = try c.decode(String.self, forKey: .host)
        port = try c.decode(UInt16.self, forKey: .port)
        password = try c.decodeIfPresent(String.self, forKey: .password)
        useTLS = try c.decodeIfPresent(Bool.self, forKey: .useTLS) ?? false
        tlsVerify = try c.decodeIfPresent(Bool.self, forKey: .tlsVerify) ?? true
        connectionType = try c.decodeIfPresent(ConnectionType.self, forKey: .connectionType) ?? .single
        database = try c.decodeIfPresent(Int.self, forKey: .database) ?? 0
        lastConnected = try c.decodeIfPresent(Date.self, forKey: .lastConnected)
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        colorTag = try c.decodeIfPresent(String.self, forKey: .colorTag)
        useSSH = try c.decodeIfPresent(Bool.self, forKey: .useSSH) ?? false
        sshHost = try c.decodeIfPresent(String.self, forKey: .sshHost) ?? ""
        sshPort = try c.decodeIfPresent(UInt16.self, forKey: .sshPort) ?? 22
        sshUser = try c.decodeIfPresent(String.self, forKey: .sshUser) ?? ""
        sshKeyPath = try c.decodeIfPresent(String.self, forKey: .sshKeyPath) ?? ""
    }

    var displayName: String {
        "\(name) (\(host):\(port))"
    }
}

struct KeyInfo: Identifiable, Sendable {
    let id: String
    let name: String
    let type: String
    let ttl: Int
    let size: Int
    let encoding: String?
    let lastAccessedTime: Date?

    var hasExpiry: Bool {
        ttl > -1
    }

    var expiryDate: Date? {
        guard ttl > 0 else { return nil }
        return Date().addingTimeInterval(TimeInterval(ttl))
    }
}

struct RedisInfo: Sendable {
    let server: [String: String]
    let clients: [String: String]
    let memory: [String: String]
    let persistence: [String: String]
    let stats: [String: String]
    let replication: [String: String]
    let cpu: [String: String]
    let cluster: [String: String]
    let keyspace: [String: String]

    static func parse(infoString: String) -> RedisInfo {
        var server: [String: String] = [:]
        var clients: [String: String] = [:]
        var memory: [String: String] = [:]
        var persistence: [String: String] = [:]
        var stats: [String: String] = [:]
        var replication: [String: String] = [:]
        var cpu: [String: String] = [:]
        var cluster: [String: String] = [:]
        var keyspace: [String: String] = [:]

        var currentSection = ""
        // Redis INFO uses \r\n, but be lenient about \n-only just in case.
        let lines = infoString.components(separatedBy: .newlines)

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            // Section header, e.g. "# Server" — must be checked BEFORE skipping
            // comment lines, otherwise the section is never set.
            if line.hasPrefix("#") {
                currentSection = line.dropFirst(1).trimmingCharacters(in: .whitespaces).lowercased()
                continue
            }
            guard !line.isEmpty else { continue }

            // Split on the first colon only (values may contain colons, e.g. keyspace).
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)

            switch currentSection {
            case "server":
                server[key] = value
            case "clients":
                clients[key] = value
            case "memory":
                memory[key] = value
            case "persistence":
                persistence[key] = value
            case "stats":
                stats[key] = value
            case "replication":
                replication[key] = value
            case "cpu":
                cpu[key] = value
            case "cluster":
                cluster[key] = value
            case "keyspace":
                keyspace[key] = value
            default:
                break
            }
        }

        return RedisInfo(
            server: server,
            clients: clients,
            memory: memory,
            persistence: persistence,
            stats: stats,
            replication: replication,
            cpu: cpu,
            cluster: cluster,
            keyspace: keyspace
        )
    }
}

struct ScanResult: Sendable {
    let cursor: Int
    let keys: [String]
    let hasMore: Bool

    var isEmpty: Bool {
        keys.isEmpty
    }
}

struct CommandHistory: Identifiable, Codable, Sendable {
    let id: UUID
    let command: String
    let executedAt: Date
    let result: String?
    let durationMs: Double

    init(
        id: UUID = UUID(),
        command: String,
        executedAt: Date = Date(),
        result: String? = nil,
        durationMs: Double = 0
    ) {
        self.id = id
        self.command = command
        self.executedAt = executedAt
        self.result = result
        self.durationMs = durationMs
    }
}

struct PubSubMessage: Identifiable, Sendable {
    let id: UUID
    let channel: String
    let message: String
    let receivedAt: Date

    init(
        id: UUID = UUID(),
        channel: String,
        message: String,
        receivedAt: Date = Date()
    ) {
        self.id = id
        self.channel = channel
        self.message = message
        self.receivedAt = receivedAt
    }
}
