import XCTest
@testable import RedisClient

final class BinaryFormatterTests: XCTestCase {
    func testEscapedKeepsPrintableAndUTF8() {
        let data = Data([0x61, 0x00, 0xFF, 0x0A]) + "é✓".data(using: .utf8)! + Data([0x5C])
        XCTAssertEqual(BinaryFormatter.escaped(data), "a\\x00\\xff\né✓\\\\")
    }

    func testEscapedRejectsTruncatedAndOverlongSequences() {
        // 0xE2 0x9C without the 3rd byte; 0xC0 0x80 is an overlong NUL.
        XCTAssertEqual(BinaryFormatter.escaped(Data([0xE2, 0x9C])), "\\xe2\\x9c")
        XCTAssertEqual(BinaryFormatter.escaped(Data([0xC0, 0x80])), "\\xc0\\x80")
    }

    func testHexDumpLayout() {
        let data = Data((0..<18).map { UInt8($0 + 0x41) })
        let lines = BinaryFormatter.hexDump(data).components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0], "00000000  41 42 43 44 45 46 47 48  49 4a 4b 4c 4d 4e 4f 50  |ABCDEFGHIJKLMNOP|")
        XCTAssertEqual(lines[1].count, lines[0].count - 14)
        XCTAssertTrue(lines[1].hasPrefix("00000010  51 52 "))
        XCTAssertTrue(lines[1].hasSuffix("|QR|"))
    }

    func testBase64RoundTrips() {
        let data = Data((0..<200).map { UInt8($0) })
        let text = BinaryFormatter.format(data, mode: .base64)
        XCTAssertEqual(Data(base64Encoded: text, options: .ignoreUnknownCharacters), data)
    }
}
