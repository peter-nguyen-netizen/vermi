import Foundation

struct KeyStat: Identifiable, Equatable {
    var id: String { key }
    let key: String
    let type: String
    let size: Int
}

struct GroupStat: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let count: Int
    let totalSize: Int
}

/// Memory / big-keys analysis: samples the keyspace, sizes each key, and
/// aggregates the biggest keys plus breakdowns by type and namespace.
@MainActor
final class AnalysisViewModel: NSObject, ObservableObject {
    @Published var isRunning = false
    @Published var scanned = 0
    @Published var totalKeys = 0
    @Published var topKeys: [KeyStat] = []
    @Published var byType: [GroupStat] = []
    @Published var byNamespace: [GroupStat] = []
    @Published var errorMessage: String?
    @Published var didRun = false

    private var client: RedisClientProtocol?
    private let scanCount = 500

    func setClient(_ client: RedisClientProtocol) { self.client = client }

    /// Sample up to `limit` keys, size them, and aggregate.
    func run(limit: Int = 1000) async {
        guard let client = client else { errorMessage = "No connection"; return }
        isRunning = true
        errorMessage = nil
        scanned = 0
        topKeys = []; byType = []; byNamespace = []
        totalKeys = (try? await client.dbsize()) ?? 0

        var collected: [String] = []
        var cursor = 0
        var iterations = 0
        do {
            repeat {
                let (next, keys) = try await client.scan(cursor: cursor, pattern: "*", count: scanCount)
                collected.append(contentsOf: keys)
                cursor = next
                iterations += 1
                scanned = collected.count
            } while cursor != 0 && collected.count < limit && iterations < 200
        } catch {
            errorMessage = error.localizedDescription
            isRunning = false
            return
        }
        if collected.count > limit { collected = Array(collected.prefix(limit)) }

        // Size + type in batches (pipelined per node inside keyMeta).
        var stats: [KeyStat] = []
        let chunk = 100
        var i = 0
        while i < collected.count {
            let batch = Array(collected[i..<min(i + chunk, collected.count)])
            let meta = await client.keyMeta(batch)
            for k in batch {
                if let m = meta[k] { stats.append(KeyStat(key: k, type: m.type, size: m.size)) }
            }
            scanned = min(i + chunk, collected.count)
            i += chunk
        }

        let result = Self.aggregate(stats, topN: 25)
        topKeys = result.top
        byType = result.byType
        byNamespace = result.byNamespace
        didRun = true
        isRunning = false
    }

    /// Pure aggregation (unit-tested).
    nonisolated static func aggregate(_ stats: [KeyStat], topN: Int, delimiter: Character = ":")
        -> (top: [KeyStat], byType: [GroupStat], byNamespace: [GroupStat]) {

        let top = stats.sorted { $0.size > $1.size }.prefix(topN).map { $0 }

        var typeCount: [String: (Int, Int)] = [:]
        var nsCount: [String: (Int, Int)] = [:]
        for s in stats {
            let t = typeCount[s.type] ?? (0, 0)
            typeCount[s.type] = (t.0 + 1, t.1 + s.size)
            let ns = s.key.split(separator: delimiter, maxSplits: 1).first.map(String.init) ?? s.key
            let n = nsCount[ns] ?? (0, 0)
            nsCount[ns] = (n.0 + 1, n.1 + s.size)
        }
        let byType = typeCount.map { GroupStat(name: $0.key, count: $0.value.0, totalSize: $0.value.1) }
            .sorted { $0.totalSize > $1.totalSize }
        let byNamespace = nsCount.map { GroupStat(name: $0.key, count: $0.value.0, totalSize: $0.value.1) }
            .sorted { $0.totalSize > $1.totalSize }
        return (Array(top), byType, byNamespace)
    }
}
