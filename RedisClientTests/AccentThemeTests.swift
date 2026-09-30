import XCTest
@testable import RedisClient

final class AccentThemeTests: XCTestCase {
    func testSevenThemes() {
        XCTAssertEqual(AccentTheme.allCases.count, 7)
        XCTAssertEqual(AccentTheme.allCases.first, .vermilion)
    }

    func testDefaultIsVermilionWhenUnset() {
        UserDefaults.standard.removeObject(forKey: "accentTheme")
        XCTAssertEqual(AccentTheme.current, .vermilion)
    }

    func testStoredThemeIsRead() {
        UserDefaults.standard.set("teal", forKey: "accentTheme")
        XCTAssertEqual(AccentTheme.current, .teal)
        UserDefaults.standard.removeObject(forKey: "accentTheme")
    }

    func testAccentsAreDistinct() {
        let lights = AccentTheme.allCases.map { "\($0.light)" }
        XCTAssertEqual(Set(lights).count, AccentTheme.allCases.count)
    }
}
