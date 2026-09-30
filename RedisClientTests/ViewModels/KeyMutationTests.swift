import XCTest
@testable import RedisClient

@MainActor
final class KeyMutationTests: XCTestCase {

    /// Deleting a list element must go by index (LSET sentinel + LREM sentinel),
    /// not by value — otherwise duplicate values would delete the wrong element.
    func testRemoveListIndexUsesSentinel() async {
        let mock = MockRedisClient()
        let vm = KeyBrowserViewModel()
        vm.setClient(mock)
        vm.selectedKey = "mylist"

        await vm.removeListIndex(2)

        let cmds = await mock.executed
        // First LSET <key> 2 <sentinel>, then LREM <key> 1 <sentinel>.
        XCTAssertEqual(cmds.count, 2)
        XCTAssertEqual(cmds[0][0], "LSET")
        XCTAssertEqual(cmds[0][1], "mylist")
        XCTAssertEqual(cmds[0][2], "2")
        let sentinel = cmds[0][3]
        XCTAssertTrue(sentinel.hasPrefix("__vermi_del_"))
        XCTAssertEqual(cmds[1], ["LREM", "mylist", "1", sentinel])
    }

    /// Undo of a string delete re-creates the value and restores its TTL.
    func testRestoreStringKeyWithTTL() async {
        let mock = MockRedisClient()
        let vm = KeyBrowserViewModel()
        vm.setClient(mock)

        await vm.restoreStringKey("greeting", value: "hello", ttl: 60)

        let cmds = await mock.executed
        XCTAssertEqual(cmds.first, ["SET", "greeting", "hello"])
        let expires = await mock.expireCalls
        XCTAssertEqual(expires.count, 1)
        XCTAssertEqual(expires.first?.key, "greeting")
        XCTAssertEqual(expires.first?.seconds, 60)
        XCTAssertTrue(vm.keys.contains("greeting"))
    }

    /// No TTL means no EXPIRE call.
    func testRestoreStringKeyWithoutTTL() async {
        let mock = MockRedisClient()
        let vm = KeyBrowserViewModel()
        vm.setClient(mock)

        await vm.restoreStringKey("k", value: "v", ttl: nil)

        let expires = await mock.expireCalls
        XCTAssertTrue(expires.isEmpty)
    }
}
