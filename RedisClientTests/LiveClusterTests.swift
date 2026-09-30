import XCTest
@testable import RedisClient

/// Live integration test against a real cluster. Only runs when the
/// VERMI_LIVE_HOST env var is set, e.g.:
///   VERMI_LIVE_HOST=host VERMI_LIVE_PORT=6379 swift test --filter LiveClusterTests
final class LiveClusterTests: XCTestCase {
    private var host: String? { ProcessInfo.processInfo.environment["VERMI_LIVE_HOST"] }
    private var port: UInt16 { UInt16(ProcessInfo.processInfo.environment["VERMI_LIVE_PORT"] ?? "6379") ?? 6379 }

    func testLiveClusterFlow() async throws {
        try XCTSkipUnless(host != nil, "Set VERMI_LIVE_HOST to run")
        let client = RedisClient(host: host!, port: port, commandTimeout: 8, isCluster: true)

        try await client.connect()
        let pong = try await client.ping()
        print("PING → \(pong)")
        XCTAssertEqual(pong.uppercased(), "PONG")

        // CLUSTER SLOTS (discovery already ran in connect)
        if let slots = try? await client.execute(["CLUSTER", "SLOTS"]) {
            print("CLUSTER SLOTS ranges: \(slots.arrayValue?.count ?? 0)")
        }

        // Scan a page
        let (cursor, keys) = try await client.scan(cursor: 0, pattern: "*", count: 50)
        print("SCAN cursor=\(cursor) got \(keys.count) keys; first: \(keys.prefix(3))")

        // Metadata for the first few keys (exercises groupByNode + pipeline + MOVED fallback)
        let sample = Array(keys.prefix(10))
        let meta = await client.keyMeta(sample)
        print("keyMeta resolved \(meta.count)/\(sample.count)")
        for k in sample {
            if let m = meta[k] { print("  \(k) → type=\(m.type) size=\(m.size)") }
            else { print("  \(k) → (unresolved)") }
        }

        // Read one key's value if any
        if let first = keys.first {
            let type = try await client.type(first)
            print("TYPE \(first) → \(type)")
        }

        try await client.disconnect()
    }

    func testLiveAnalysis() async throws {
        try XCTSkipUnless(host != nil, "Set VERMI_LIVE_HOST to run")
        let client = RedisClient(host: host!, port: port, commandTimeout: 8, isCluster: true)
        try await client.connect()

        // Sample ~200 keys, size them, aggregate.
        var collected: [String] = []
        var cursor = 0
        repeat {
            let (next, keys) = try await client.scan(cursor: cursor, pattern: "*", count: 500)
            collected.append(contentsOf: keys); cursor = next
        } while cursor != 0 && collected.count < 200
        collected = Array(collected.prefix(200))

        var stats: [KeyStat] = []
        let meta = await client.keyMeta(collected)
        for k in collected { if let m = meta[k] { stats.append(KeyStat(key: k, type: m.type, size: m.size)) } }

        let r = AnalysisViewModel.aggregate(stats, topN: 5)
        print("Analysis: \(stats.count) keys sized")
        print("By type: \(r.byType.map { "\($0.name):\($0.count)/\($0.totalSize)B" })")
        print("Top: \(r.top.map { "\($0.key)=\($0.size)B" })")
        XCTAssertFalse(stats.isEmpty)
        XCTAssertFalse(r.byType.isEmpty)
        try await client.disconnect()
    }
}
