import XCTest
@testable import RedisClient

@MainActor
final class KeyBrowserSelectionTests: XCTestCase {
    func testBulkSelectionState() {
        let vm = KeyBrowserViewModel()
        vm.keys = ["a", "b", "c"]

        vm.toggleSelectionMode()
        XCTAssertTrue(vm.selectionMode)

        vm.toggleSelected("a")
        vm.toggleSelected("b")
        XCTAssertEqual(vm.selectedKeys, ["a", "b"])

        vm.toggleSelected("a")   // toggle off
        XCTAssertEqual(vm.selectedKeys, ["b"])

        vm.selectAllVisible()
        XCTAssertEqual(vm.selectedKeys, ["a", "b", "c"])

        vm.clearSelection()
        XCTAssertTrue(vm.selectedKeys.isEmpty)

        // Exiting selection mode clears any selection.
        vm.toggleSelected("c")
        vm.toggleSelectionMode()
        XCTAssertFalse(vm.selectionMode)
        XCTAssertTrue(vm.selectedKeys.isEmpty)
    }
}
