import Foundation
@testable import RedisClient

/// Minimal in-memory RedisClientProtocol double for view-model tests. Records
/// every `execute`/`expire` call so tests can assert on the exact commands sent.
actor MockRedisClient: RedisClientProtocol {
    private(set) var executed: [[String]] = []
    private(set) var expireCalls: [(key: String, seconds: Int)] = []
    /// Canned responses keyed by the command verb (uppercased), else `.ok`.
    var responses: [String: RESPValue] = [:]

    func setResponse(_ verb: String, _ value: RESPValue) { responses[verb.uppercased()] = value }

    func execute(_ command: [String]) async throws -> RESPValue {
        executed.append(command)
        let verb = command.first?.uppercased() ?? ""
        return responses[verb] ?? .simpleString("OK")
    }

    func connect() async throws {}
    func disconnect() async throws {}
    func isConnected() async -> Bool { true }
    func ping() async throws -> String { "PONG" }
    func dbsize() async throws -> Int { 0 }
    /// Canned INFO payload so monitoring tests can give each mock its own server.
    var infoString: String = ""
    func setInfo(_ raw: String) { infoString = raw }
    func info(section: String?) async throws -> String { infoString }
    func keys(pattern: String) async throws -> [String] { [] }
    func scan(cursor: Int, pattern: String?, count: Int) async throws -> (Int, [String]) { (0, []) }
    func get(_ key: String) async throws -> RESPValue { .null }
    func set(_ key: String, value: String) async throws -> String { "OK" }
    func del(_ keys: [String]) async throws -> Int { keys.count }
    func exists(_ keys: [String]) async throws -> Int { 0 }
    func ttl(_ key: String) async throws -> Int { -1 }
    func expire(_ key: String, seconds: Int) async throws -> Bool {
        expireCalls.append((key, seconds)); return true
    }
    func type(_ key: String) async throws -> String { "string" }
    func flushdb(async: Bool) async throws -> Bool { true }
    func flushall(async: Bool) async throws -> Bool { true }
    func strlen(_ key: String) async throws -> Int { 0 }
    func lrange(_ key: String, start: Int, stop: Int) async throws -> [String] { [] }
    func llen(_ key: String) async throws -> Int { 0 }
    func hgetall(_ key: String) async throws -> [(field: String, value: String)] { [] }
    func hlen(_ key: String) async throws -> Int { 0 }
    func smembers(_ key: String) async throws -> [String] { [] }
    func scard(_ key: String) async throws -> Int { 0 }
    func zrangeWithScores(_ key: String, start: Int, stop: Int) async throws -> [(member: String, score: Double)] { [] }
    func zcard(_ key: String) async throws -> Int { 0 }
    func setPushHandler(_ handler: @escaping @Sendable (RESPValue) -> Void) async {}
    func pipeline(_ commands: [[String]]) async throws -> [RESPValue] { [] }
    func keyMeta(_ keys: [String]) async -> [String: (type: String, size: Int)] { [:] }
}
