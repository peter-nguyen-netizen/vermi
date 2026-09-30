import XCTest
@testable import RedisClient

final class KeyTreeTests: XCTestCase {
    func testGroupsByDelimiter() {
        let tree = KeyTree.build(["a:b:c", "a:b:d", "a:e", "x"])
        // Top level: folder "a" (sorts before) then leaf "x"
        XCTAssertEqual(tree.map(\.name), ["a", "x"])
        XCTAssertTrue(tree[0].isFolder)
        XCTAssertNil(tree[0].fullKey)
        XCTAssertFalse(tree[1].isFolder)
        XCTAssertEqual(tree[1].fullKey, "x")

        // "a" → folder "b" then leaf "e"
        let a = tree[0]
        XCTAssertEqual(a.children.map(\.name), ["b", "e"])
        XCTAssertEqual(a.children[0].children.map(\.name), ["c", "d"])
        XCTAssertEqual(a.children[0].children[0].fullKey, "a:b:c")
        XCTAssertEqual(a.children[1].fullKey, "a:e")
    }

    func testKeyThatIsAlsoAPrefix() {
        // "a:b" is a real key AND a parent of "a:b:c"
        let tree = KeyTree.build(["a:b", "a:b:c"])
        let a = tree[0]
        let b = a.children[0]
        XCTAssertEqual(b.name, "b")
        XCTAssertEqual(b.fullKey, "a:b")   // key ends here
        XCTAssertTrue(b.isFolder)          // and has a child
        XCTAssertEqual(b.children[0].fullKey, "a:b:c")
    }

    func testFlatKeysNoDelimiter() {
        let tree = KeyTree.build(["foo", "bar", "baz"])
        XCTAssertEqual(tree.map(\.name), ["bar", "baz", "foo"])  // alphabetical leaves
        XCTAssertTrue(tree.allSatisfy { !$0.isFolder })
    }
}
