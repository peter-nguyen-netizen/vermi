import XCTest
@testable import RedisClient

final class AnalysisTests: XCTestCase {
    func testAggregate() {
        let stats = [
            KeyStat(key: "a:1", type: "hash", size: 100),
            KeyStat(key: "a:2", type: "hash", size: 300),
            KeyStat(key: "b:1", type: "string", size: 50),
            KeyStat(key: "b:2", type: "zset", size: 900),
        ]
        let r = AnalysisViewModel.aggregate(stats, topN: 2)

        // Top 2 by size
        XCTAssertEqual(r.top.map(\.key), ["b:2", "a:2"])

        // By type: zset(900) > hash(400) > string(50)
        XCTAssertEqual(r.byType.map(\.name), ["zset", "hash", "string"])
        XCTAssertEqual(r.byType.first(where: { $0.name == "hash" })?.count, 2)
        XCTAssertEqual(r.byType.first(where: { $0.name == "hash" })?.totalSize, 400)

        // By namespace: b(950) > a(400)
        XCTAssertEqual(r.byNamespace.map(\.name), ["b", "a"])
        XCTAssertEqual(r.byNamespace.first(where: { $0.name == "a" })?.totalSize, 400)
    }
}
