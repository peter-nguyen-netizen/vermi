import XCTest
@testable import RedisClient

final class RedisCommandCatalogTests: XCTestCase {
    func testFunctionCommandsPresent() {
        // The reported gap: FCALL_RO (and friends) must be in the catalog.
        for name in ["FCALL", "FCALL_RO", "FUNCTION", "EVAL_RO", "EVALSHA_RO"] {
            XCTAssertNotNil(RedisCommandCatalog.info(for: name), "\(name) missing")
        }
    }

    func testPrefixMatchingIsCaseInsensitiveAndSorted() {
        let m = RedisCommandCatalog.matching(prefix: "fcall")
        XCTAssertEqual(m.map(\.name), ["FCALL", "FCALL_RO"])
    }

    func testBroadCoverage() {
        // Sanity: the catalog should be comprehensive, not the old ~90.
        XCTAssertGreaterThan(RedisCommandCatalog.all.count, 180)
    }

    func testSubcommandSuggestions() {
        XCTAssertTrue(RedisCommandCatalog.hasSubcommands("CONFIG"))
        XCTAssertFalse(RedisCommandCatalog.hasSubcommands("GET"))

        let get = RedisCommandCatalog.subcommandsMatching(container: "config", prefix: "g")
        XCTAssertEqual(get.map(\.name), ["CONFIG GET"])

        let all = RedisCommandCatalog.subcommandsMatching(container: "CONFIG", prefix: "")
        XCTAssertTrue(all.contains { $0.name == "CONFIG SET" })
        XCTAssertTrue(all.contains { $0.name == "CONFIG REWRITE" })
    }
}
