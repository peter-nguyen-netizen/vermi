import XCTest
@testable import RedisClient

final class RedisClusterTests: XCTestCase {
    // CRC16/XMODEM known values (per Redis Cluster spec).
    func testSlotComputation() {
        XCTAssertEqual(RedisCluster.slot(for: "123456789"), 12739)
        // Hash tag: {user1000} → hashes only "user1000"
        XCTAssertEqual(RedisCluster.slot(for: "foo{user1000}bar"),
                       RedisCluster.slot(for: "user1000"))
        // Empty hash tag {} → hash the whole key
        XCTAssertNotEqual(RedisCluster.slot(for: "foo{}bar"),
                          RedisCluster.slot(for: ""))
    }

    func testParseRedirect() {
        let moved = RedisCluster.parseRedirect("MOVED 3999 127.0.0.1:6381")
        XCTAssertEqual(moved?.kind, .moved)
        XCTAssertEqual(moved?.slot, 3999)
        XCTAssertEqual(moved?.host, "127.0.0.1")
        XCTAssertEqual(moved?.port, 6381)

        let ask = RedisCluster.parseRedirect("ASK 42 10.0.0.5:7000")
        XCTAssertEqual(ask?.kind, .ask)
        XCTAssertEqual(ask?.nodeKey, "10.0.0.5:7000")

        XCTAssertNil(RedisCluster.parseRedirect("WRONGTYPE ..."))
    }

    func testGroupByNode() {
        // Two slots mapped to two nodes; unknown slot falls back.
        let a = "keyA", b = "keyB"
        let slotA = RedisCluster.slot(for: a)
        let slotB = RedisCluster.slot(for: b)
        // Ensure distinct slots for a meaningful test
        guard slotA != slotB else { return }
        let slotMap: [Int: String] = [slotA: "n1:6379", slotB: "n2:6379"]

        let groups = RedisCluster.groupByNode([a, b, "unknownkey"], slotMap: slotMap, fallback: "primary:6379")
        XCTAssertEqual(groups["n1:6379"], [a])
        XCTAssertEqual(groups["n2:6379"], [b])
        // "unknownkey"'s slot isn't in the map (unless it collides) → fallback
        let unknownSlot = RedisCluster.slot(for: "unknownkey")
        if slotMap[unknownSlot] == nil {
            XCTAssertEqual(groups["primary:6379"], ["unknownkey"])
        }
    }
}
