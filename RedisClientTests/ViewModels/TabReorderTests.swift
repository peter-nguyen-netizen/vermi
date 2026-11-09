import XCTest
@testable import RedisClient

/// Drag-to-reorder for connection tabs (Chrome-style).
@MainActor
final class TabReorderTests: XCTestCase {

    private func tab(_ conn: RedisConnection, _ n: Int = 1) -> AppState.ConnectionTab {
        AppState.ConnectionTab(id: UUID(), connection: conn, instanceNumber: n)
    }

    private func names(_ s: AppState) -> [String] { s.openConnections.map { s.displayName(for: $0) } }

    private func makeState() -> (AppState, [AppState.ConnectionTab]) {
        let s = AppState()
        let tabs = ["A", "B", "C", "D"].map { tab(RedisConnection(name: $0, host: "127.0.0.1")) }
        s.openConnections = tabs
        return (s, tabs)
    }

    func testDragRightLandsInTargetSlot() {
        let (s, t) = makeState()
        s.moveTab(t[0].id, to: t[2].id)
        XCTAssertEqual(names(s), ["B", "C", "A", "D"])
    }

    func testDragLeftLandsInTargetSlot() {
        let (s, t) = makeState()
        s.moveTab(t[3].id, to: t[1].id)
        XCTAssertEqual(names(s), ["A", "D", "B", "C"])
    }

    func testMoveOntoSelfOrUnknownIsNoop() {
        let (s, t) = makeState()
        s.moveTab(t[1].id, to: t[1].id)
        s.moveTab(UUID(), to: t[1].id)
        s.moveTab(t[1].id, to: UUID())
        XCTAssertEqual(names(s), ["A", "B", "C", "D"])
    }

    func testMoveByOffsetClamps() {
        let (s, t) = makeState()
        s.moveTab(t[0].id, by: -1)
        XCTAssertEqual(names(s), ["A", "B", "C", "D"])
        s.moveTab(t[0].id, by: 1)
        XCTAssertEqual(names(s), ["B", "A", "C", "D"])
        s.moveTab(t[0].id, by: 99)
        XCTAssertEqual(names(s), ["B", "C", "D", "A"])
    }

    func testReorderKeepsActiveTab() {
        let (s, t) = makeState()
        s.activeTabId = t[1].id
        s.moveTab(t[1].id, to: t[3].id)
        XCTAssertEqual(s.activeTabId, t[1].id)
    }

    /// Duplicate tabs of one connection keep their "(N)" label after reordering.
    func testInstanceLabelsStableAcrossReorder() {
        let s = AppState()
        let conn = RedisConnection(name: "prod", host: "127.0.0.1")
        let first = tab(conn, 1)
        s.openConnections = [first]
        XCTAssertEqual(s.nextInstanceNumber(for: conn.id), 2)
        let second = tab(conn, s.nextInstanceNumber(for: conn.id))
        s.openConnections.append(second)
        XCTAssertEqual(names(s), ["prod (1)", "prod (2)"])

        s.moveTab(second.id, to: first.id)
        XCTAssertEqual(names(s), ["prod (2)", "prod (1)"])

        // Closing one drops the suffix; the freed ordinal is reused.
        s.openConnections.removeAll { $0.id == first.id }
        XCTAssertEqual(names(s), ["prod"])
        XCTAssertEqual(s.nextInstanceNumber(for: conn.id), 1)
    }
}
