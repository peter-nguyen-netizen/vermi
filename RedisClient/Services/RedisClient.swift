import Foundation

protocol RedisClientProtocol: Sendable {
    func execute(_ command: [String]) async throws -> RESPValue
    func connect() async throws
    func disconnect() async throws
    func isConnected() async -> Bool
    func ping() async throws -> String
    func dbsize() async throws -> Int
    func info(section: String?) async throws -> String
    func keys(pattern: String) async throws -> [String]
    func scan(cursor: Int, pattern: String?, count: Int) async throws -> (Int, [String])
    func get(_ key: String) async throws -> RESPValue
    func set(_ key: String, value: String) async throws -> String
    func del(_ keys: [String]) async throws -> Int
    func exists(_ keys: [String]) async throws -> Int
    func ttl(_ key: String) async throws -> Int
    func expire(_ key: String, seconds: Int) async throws -> Bool
    func type(_ key: String) async throws -> String
    func flushdb(async: Bool) async throws -> Bool
    func flushall(async: Bool) async throws -> Bool
    func strlen(_ key: String) async throws -> Int
    func lrange(_ key: String, start: Int, stop: Int) async throws -> [String]
    func llen(_ key: String) async throws -> Int
    func hgetall(_ key: String) async throws -> [(field: String, value: String)]
    func hlen(_ key: String) async throws -> Int
    func smembers(_ key: String) async throws -> [String]
    func scard(_ key: String) async throws -> Int
    func zrangeWithScores(_ key: String, start: Int, stop: Int) async throws -> [(member: String, score: Double)]
    func zcard(_ key: String) async throws -> Int
    func setPushHandler(_ handler: @escaping @Sendable (RESPValue) -> Void) async
    func pipeline(_ commands: [[String]]) async throws -> [RESPValue]
    func keyMeta(_ keys: [String]) async -> [String: (type: String, size: Int)]
}

actor RedisClient: RedisClientProtocol {
    private let host: String
    private let port: UInt16
    private let useTLS: Bool
    private let password: String?
    private let database: Int
    private let commandTimeout: TimeInterval
    private let isCluster: Bool

    /// One channel per node. Non-cluster uses just the primary; cluster adds
    /// node channels on demand as MOVED/ASK redirects or CLUSTER SLOTS reveal them.
    private var channels: [String: NetworkChannel] = [:]
    private var slotMap: [Int: String] = [:]
    private var pushHandler: (@Sendable (RESPValue) -> Void)?
    private let primaryKey: String

    init(
        host: String,
        port: UInt16 = 6379,
        useTLS: Bool = false,
        password: String? = nil,
        database: Int = 0,
        commandTimeout: TimeInterval = 10.0,
        isCluster: Bool = false
    ) {
        self.host = host
        self.port = port
        self.useTLS = useTLS
        self.password = password
        self.database = database
        self.commandTimeout = commandTimeout
        self.isCluster = isCluster
        self.primaryKey = "\(host):\(port)"
    }

    private func makeChannel(host: String, port: UInt16) -> NetworkChannel {
        NetworkChannel(host: host, port: port, useTLS: useTLS, password: password, commandTimeout: commandTimeout)
    }

    /// Return a connected channel for a node, (re)establishing the session if
    /// it's new or was dropped. This is where auto-reconnect happens.
    private func channel(for nodeKey: String) async throws -> NetworkChannel {
        // Reuse only a live channel. A dropped one may be wedged in a non-
        // reconnectable state, so discard it and build a fresh NWConnection.
        if let existing = channels[nodeKey] {
            if await existing.getConnectionState() == .connected { return existing }
            try? await existing.disconnect()
            channels[nodeKey] = nil
        }
        let parts = nodeKey.split(separator: ":")
        guard parts.count == 2, let p = UInt16(parts[1]) else {
            throw RESPError.connectionError("Invalid node address: \(nodeKey)")
        }
        let ch = makeChannel(host: String(parts[0]), port: p)
        try await establish(ch)
        channels[nodeKey] = ch   // store only after a successful session
        return ch
    }

    /// Connect + AUTH + PING (+ SELECT for non-cluster) on a channel.
    private func establish(_ ch: NetworkChannel) async throws {
        try await ch.connect()

        if let password = password, !password.isEmpty {
            if case .error(let m) = try await ch.send(["AUTH", password]) {
                try? await ch.disconnect()
                throw RESPError.connectionError("AUTH failed: \(m)")
            }
        }
        if case .error(let m) = try await ch.send(["PING"]) {
            try? await ch.disconnect()
            throw RESPError.connectionError("PING failed: \(m)")
        }
        // SELECT is not supported in cluster mode (single logical DB)
        if database > 0 && !isCluster {
            if case .error(let m) = try await ch.send(["SELECT", String(database)]) {
                try? await ch.disconnect()
                throw RESPError.connectionError("SELECT \(database) failed: \(m)")
            }
        }
        if let handler = pushHandler {
            await ch.setPushHandler(handler)
        }
    }

    func connect() async throws {
        _ = try await channel(for: primaryKey)
        if isCluster { await discoverSlots() }
    }

    /// Populate slot→node map from CLUSTER SLOTS so commands route directly.
    private func discoverSlots() async {
        guard let primary = channels[primaryKey],
              let resp = try? await primary.send(["CLUSTER", "SLOTS"]),
              let ranges = resp.arrayValue else { return }
        for range in ranges {
            guard let r = range.arrayValue, r.count >= 3,
                  let start = r[0].intValue, let end = r[1].intValue,
                  let master = r[2].arrayValue, master.count >= 2,
                  let mhost = master[0].stringValue, let mport = master[1].intValue else { continue }
            let key = "\(mhost):\(mport)"
            if start <= end {
                for slot in Int(start)...Int(end) { slotMap[slot] = key }
            }
        }
    }

    func disconnect() async throws {
        for ch in channels.values {
            try? await ch.disconnect()
        }
        channels.removeAll()
        slotMap.removeAll()
    }

    func isConnected() async -> Bool {
        guard let primary = channels[primaryKey] else { return false }
        return await primary.getConnectionState() == .connected
    }

    func execute(_ command: [String]) async throws -> RESPValue {
        let result = try await executeRouted(command)
        // Surface a real Redis server error reply (WRONGTYPE, NOAUTH, …) as an
        // error with its text. MOVED/ASK are handled below, so they never reach here.
        if case .error(let message) = result {
            throw RESPError.serverError(message)
        }
        return result
    }

    /// Send a command, transparently following MOVED/ASK redirects. This runs
    /// for EVERY connection, not just those opened as "Cluster" — a standalone
    /// server never sends MOVED, and a cluster reached via any node just works
    /// (the slot map is learned lazily from the first redirect). Also does one
    /// auto-reconnect retry if the target node's connection dropped.
    private func executeRouted(_ command: [String]) async throws -> RESPValue {
        var nodeKey: String = {
            if let key = RedisCluster.firstKey(of: command) {
                return slotMap[RedisCluster.slot(for: key)] ?? primaryKey
            }
            return primaryKey
        }()
        var asking = false
        var reconnectTried = false

        for _ in 0..<8 {
            let ch: NetworkChannel
            do {
                ch = try await channel(for: nodeKey)
            } catch {
                throw RESPError.connectionError(
                    "Cannot reach cluster node \(nodeKey): \(error.localizedDescription). " +
                    "The key lives on a node your machine can't open a direct connection to " +
                    "(nodes advertise their own address; often only reachable from inside the VPC/network)."
                )
            }

            do {
                if asking {
                    _ = try await ch.send(["ASKING"])
                    asking = false
                }
                let resp = try await ch.send(command)
                if case .error(let msg) = resp, let redirect = RedisCluster.parseRedirect(msg) {
                    if redirect.kind == .moved { slotMap[redirect.slot] = redirect.nodeKey }
                    else { asking = true }
                    nodeKey = redirect.nodeKey
                    continue
                }
                return resp
            } catch let error as RESPError where isRetriable(error) && !reconnectTried {
                // Connection dropped — reconnect that node once and retry.
                reconnectTried = true
                continue
            }
        }
        throw RESPError.connectionError("Too many redirects")
    }

    /// Pipeline commands to the primary node in a single round-trip. Redirects
    /// are NOT followed here (best-effort batch); use `execute` for routed
    /// single commands. Fine for same-node batches like list metadata.
    func pipeline(_ commands: [[String]]) async throws -> [RESPValue] {
        guard !commands.isEmpty else { return [] }
        return try await channel(for: primaryKey).pipeline(commands)
    }

    /// Fetch type + byte-size for many keys. Fast path: two pipelines to the
    /// primary (2 round-trips). Cluster: keys owned by another node come back as
    /// MOVED errors on the primary — those are resolved individually via routed
    /// commands (which follow MOVED). Error replies are never treated as data.
    func keyMeta(_ keys: [String]) async -> [String: (type: String, size: Int)] {
        guard !keys.isEmpty else { return [:] }
        var out: [String: (type: String, size: Int)] = [:]

        // Group keys by their owning node so each node is pipelined once. When
        // slots aren't known (non-cluster, or not yet discovered) everything
        // goes to the primary and MOVED-redirected keys are handled below.
        let groups = slotMap.isEmpty
            ? [primaryKey: keys]
            : RedisCluster.groupByNode(keys, slotMap: slotMap, fallback: primaryKey)

        for (nodeKey, nodeKeys) in groups {
            let resolved = await metaOnNode(nodeKey, keys: nodeKeys)
            for (k, m) in resolved { out[k] = m }
        }

        // Any key still unresolved (e.g. a MOVED because the slot map was stale)
        // → routed per-key, which follows MOVED to the correct node.
        for key in keys where out[key] == nil {
            guard let t = try? await type(key) else { continue }
            out[key] = (t, intFromNonError(try? await execute(["MEMORY", "USAGE", key])))
        }
        return out
    }

    /// Pipeline TYPE + MEMORY USAGE for a set of keys on one node. Keys whose
    /// reply isn't a clean type (e.g. MOVED) are simply omitted.
    private func metaOnNode(_ nodeKey: String, keys: [String]) async -> [String: (type: String, size: Int)] {
        guard let ch = try? await channel(for: nodeKey) else { return [:] }
        let types = try? await ch.pipeline(keys.map { ["TYPE", $0] })
        let sizes = try? await ch.pipeline(keys.map { ["MEMORY", "USAGE", $0] })
        var out: [String: (type: String, size: Int)] = [:]
        for (i, key) in keys.enumerated() {
            if let reply = types?[safe: i], case .simpleString(let t) = reply, !t.isEmpty {
                out[key] = (t, intFromNonError(sizes?[safe: i]))
            }
        }
        return out
    }

    private func intFromNonError(_ reply: RESPValue?) -> Int {
        guard let reply = reply, !reply.isError else { return 0 }
        return Int(reply.intValue ?? 0)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension RedisClient {

    private func isRetriable(_ error: RESPError) -> Bool {
        switch error {
        case .connectionError, .timeout: return true
        default: return false
        }
    }

    func ping() async throws -> String {
        let result = try await execute(["PING"])
        guard let str = result.stringValue else {
            throw RESPError.decodingError("Invalid PING response")
        }
        return str
    }

    func dbsize() async throws -> Int {
        let result = try await execute(["DBSIZE"])
        guard let size = result.intValue else {
            throw RESPError.decodingError("Invalid DBSIZE response")
        }
        return Int(size)
    }

    func info(section: String? = nil) async throws -> String {
        var command = ["INFO"]
        if let section = section {
            command.append(section)
        }
        let result = try await execute(command)
        guard let info = result.stringValue else {
            throw RESPError.decodingError("Invalid INFO response")
        }
        return info
    }

    func keys(pattern: String) async throws -> [String] {
        let result = try await execute(["KEYS", pattern])
        guard let values = result.arrayValue else {
            throw RESPError.decodingError("Invalid KEYS response")
        }
        return values.compactMap { $0.stringValue }
    }

    func scan(cursor: Int = 0, pattern: String? = nil, count: Int = 10) async throws -> (Int, [String]) {
        var command = ["SCAN", String(cursor)]
        if let pattern = pattern {
            command.append(contentsOf: ["MATCH", pattern])
        }
        command.append(contentsOf: ["COUNT", String(count)])

        let result = try await execute(command)
        guard let arr = result.arrayValue, arr.count == 2 else {
            throw RESPError.decodingError("Invalid SCAN response")
        }

        guard let nextCursor = Int(arr[0].stringValue ?? "0") else {
            throw RESPError.decodingError("Invalid cursor in SCAN response")
        }

        let keys = arr[1].arrayValue?.compactMap { $0.stringValue } ?? []
        return (nextCursor, keys)
    }

    func get(_ key: String) async throws -> RESPValue {
        let result = try await execute(["GET", key])
        return result
    }

    func set(_ key: String, value: String) async throws -> String {
        let result = try await execute(["SET", key, value])
        guard let status = result.stringValue else {
            throw RESPError.decodingError("Invalid SET response")
        }
        return status
    }

    func del(_ keys: [String]) async throws -> Int {
        var command = ["DEL"]
        command.append(contentsOf: keys)
        let result = try await execute(command)
        guard let count = result.intValue else {
            throw RESPError.decodingError("Invalid DEL response")
        }
        return Int(count)
    }

    func exists(_ keys: [String]) async throws -> Int {
        var command = ["EXISTS"]
        command.append(contentsOf: keys)
        let result = try await execute(command)
        guard let count = result.intValue else {
            throw RESPError.decodingError("Invalid EXISTS response")
        }
        return Int(count)
    }

    func ttl(_ key: String) async throws -> Int {
        let result = try await execute(["TTL", key])
        guard let ttl = result.intValue else {
            throw RESPError.decodingError("Invalid TTL response")
        }
        return Int(ttl)
    }

    func expire(_ key: String, seconds: Int) async throws -> Bool {
        let result = try await execute(["EXPIRE", key, String(seconds)])
        guard let changed = result.intValue else {
            throw RESPError.decodingError("Invalid EXPIRE response")
        }
        return changed == 1
    }

    func type(_ key: String) async throws -> String {
        let result = try await execute(["TYPE", key])
        guard let type = result.stringValue else {
            throw RESPError.decodingError("Invalid TYPE response")
        }
        return type
    }

    // MARK: - Typed value readers

    func strlen(_ key: String) async throws -> Int {
        let result = try await execute(["STRLEN", key])
        return Int(result.intValue ?? 0)
    }

    func lrange(_ key: String, start: Int, stop: Int) async throws -> [String] {
        let result = try await execute(["LRANGE", key, String(start), String(stop)])
        guard let values = result.arrayValue else {
            throw RESPError.decodingError("Invalid LRANGE response")
        }
        return values.compactMap { $0.stringValue }
    }

    func llen(_ key: String) async throws -> Int {
        let result = try await execute(["LLEN", key])
        return Int(result.intValue ?? 0)
    }

    func hgetall(_ key: String) async throws -> [(field: String, value: String)] {
        let result = try await execute(["HGETALL", key])

        // RESP3 returns a map, RESP2 a flat [field, value, field, value] array
        if case .map(let map) = result {
            return map.map { ($0.key, $0.value.stringValue ?? "") }
                .sorted { $0.0 < $1.0 }
        }

        guard let flat = result.arrayValue else {
            throw RESPError.decodingError("Invalid HGETALL response")
        }
        var pairs: [(String, String)] = []
        var index = 0
        while index + 1 < flat.count {
            pairs.append((flat[index].stringValue ?? "", flat[index + 1].stringValue ?? ""))
            index += 2
        }
        return pairs
    }

    func hlen(_ key: String) async throws -> Int {
        let result = try await execute(["HLEN", key])
        return Int(result.intValue ?? 0)
    }

    func smembers(_ key: String) async throws -> [String] {
        let result = try await execute(["SMEMBERS", key])
        if case .set(let set) = result {
            return set.sorted()
        }
        guard let values = result.arrayValue else {
            throw RESPError.decodingError("Invalid SMEMBERS response")
        }
        return values.compactMap { $0.stringValue }
    }

    func scard(_ key: String) async throws -> Int {
        let result = try await execute(["SCARD", key])
        return Int(result.intValue ?? 0)
    }

    func zrangeWithScores(_ key: String, start: Int, stop: Int) async throws -> [(member: String, score: Double)] {
        let result = try await execute(["ZRANGE", key, String(start), String(stop), "WITHSCORES"])
        guard let flat = result.arrayValue else {
            throw RESPError.decodingError("Invalid ZRANGE response")
        }

        // RESP3 may return nested [member, score] pairs; RESP2 a flat list
        if let first = flat.first, case .array = first {
            return flat.compactMap { entry in
                guard let pair = entry.arrayValue, pair.count == 2,
                      let member = pair[0].stringValue else { return nil }
                let score = pair[1].doubleValue ?? Double(pair[1].stringValue ?? "") ?? 0
                return (member, score)
            }
        }

        var pairs: [(String, Double)] = []
        var index = 0
        while index + 1 < flat.count {
            let member = flat[index].stringValue ?? ""
            let score = flat[index + 1].doubleValue ?? Double(flat[index + 1].stringValue ?? "") ?? 0
            pairs.append((member, score))
            index += 2
        }
        return pairs
    }

    func zcard(_ key: String) async throws -> Int {
        let result = try await execute(["ZCARD", key])
        return Int(result.intValue ?? 0)
    }

    // MARK: - Pub/Sub

    func setPushHandler(_ handler: @escaping @Sendable (RESPValue) -> Void) async {
        pushHandler = handler
        for ch in channels.values {
            await ch.setPushHandler(handler)
        }
    }

    func flushdb(async: Bool = false) async throws -> Bool {
        let command = async ? ["FLUSHDB", "ASYNC"] : ["FLUSHDB"]
        let result = try await execute(command)
        return !result.isError
    }

    func flushall(async: Bool = false) async throws -> Bool {
        let command = async ? ["FLUSHALL", "ASYNC"] : ["FLUSHALL"]
        let result = try await execute(command)
        return !result.isError
    }
}
