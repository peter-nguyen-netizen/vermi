import XCTest
@testable import RedisClient

@MainActor
final class ConsoleRenderTests: XCTestCase {
    func testRenderScalars() {
        XCTAssertEqual(CommandExecutorViewModel.render(.integer(42)).0, "(integer) 42")
        XCTAssertEqual(CommandExecutorViewModel.render(.simpleString("PONG")).0, "OK: PONG")
        XCTAssertEqual(CommandExecutorViewModel.render(.null).0, "(nil)")

        let err = CommandExecutorViewModel.render(.error("WRONGTYPE"))
        XCTAssertTrue(err.1, "error flag should be set")
        XCTAssertTrue(err.0.contains("WRONGTYPE"))
    }

    func testRenderArrayIsNumbered() {
        let v = RESPValue.array([.bulkString("a".data(using: .utf8)), .bulkString("b".data(using: .utf8))])
        XCTAssertEqual(CommandExecutorViewModel.render(v).0, "1) a\n2) b")
    }

    private func bulk(_ s: String) -> RESPValue { .bulkString(s.data(using: .utf8)) }

    func testHGETALLBecomesJSONObject() {
        let reply = RESPValue.array([bulk("title"), bulk("Whiplash"), bulk("year"), bulk("2014")])
        let json = CommandExecutorViewModel.jsonPretty(reply, command: "HGETALL sample:movie")
        XCTAssertNotNil(json)
        // Object form (sorted keys), not a numbered list.
        XCTAssertTrue(json!.contains("\"title\" : \"Whiplash\""))
        XCTAssertTrue(json!.contains("\"year\" : \"2014\""))
        XCTAssertTrue(json!.hasPrefix("{"))
    }

    func testNestedJSONStringIsExpanded() {
        // A hash whose value is itself a JSON string should nest, not stay a string.
        let reply = RESPValue.array([bulk("Settings"), bulk("{\"enabled\":true,\"n\":3}")])
        let json = CommandExecutorViewModel.jsonPretty(reply, command: "HGETALL k")
        XCTAssertNotNil(json)
        XCTAssertTrue(json!.contains("\"enabled\" : true"))
        XCTAssertTrue(json!.contains("\"n\" : 3"))
    }

    func testPlainArrayStaysArray() {
        let reply = RESPValue.array([bulk("a"), bulk("b"), bulk("c")])
        let json = CommandExecutorViewModel.jsonPretty(reply, command: "LRANGE k 0 -1")
        XCTAssertEqual(json?.hasPrefix("["), true)
    }
}
