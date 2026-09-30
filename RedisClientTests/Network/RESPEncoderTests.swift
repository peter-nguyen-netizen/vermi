import XCTest
@testable import RedisClient

final class RESPEncoderTests: XCTestCase {

    func testEncodeSimpleCommand() {
        let encoder = RESPEncoder()
        let data = encoder.encode(["PING"])
        let expected = "*1\r\n$4\r\nPING\r\n".data(using: .utf8)!
        XCTAssertEqual(data, expected)
    }

    func testEncodeGETCommand() {
        let encoder = RESPEncoder()
        let data = encoder.encode(["GET", "mykey"])
        let expected = "*2\r\n$3\r\nGET\r\n$5\r\nmykey\r\n".data(using: .utf8)!
        XCTAssertEqual(data, expected)
    }

    func testEncodeSETCommand() {
        let encoder = RESPEncoder()
        let data = encoder.encode(["SET", "key", "value"])
        let expected = "*3\r\n$3\r\nSET\r\n$3\r\nkey\r\n$5\r\nvalue\r\n".data(using: .utf8)!
        XCTAssertEqual(data, expected)
    }

    func testEncodeSimpleString() {
        let encoder = RESPEncoder()
        let data = encoder.encode(.simpleString("OK"))
        let expected = "+OK\r\n".data(using: .utf8)!
        XCTAssertEqual(data, expected)
    }

    func testEncodeError() {
        let encoder = RESPEncoder()
        let data = encoder.encode(.error("ERR unknown command"))
        let expected = "-ERR unknown command\r\n".data(using: .utf8)!
        XCTAssertEqual(data, expected)
    }

    func testEncodeInteger() {
        let encoder = RESPEncoder()
        let data = encoder.encode(.integer(1000))
        let expected = ":1000\r\n".data(using: .utf8)!
        XCTAssertEqual(data, expected)
    }

    func testEncodeBulkString() {
        let encoder = RESPEncoder()
        let data = encoder.encode(.bulkString("foobar".data(using: .utf8)))
        let expected = "$6\r\nfoobar\r\n".data(using: .utf8)!
        XCTAssertEqual(data, expected)
    }

    func testEncodeNullBulkString() {
        let encoder = RESPEncoder()
        let data = encoder.encode(.bulkString(nil))
        let expected = "$-1\r\n".data(using: .utf8)!
        XCTAssertEqual(data, expected)
    }

    func testEncodeEmptyBulkString() {
        let encoder = RESPEncoder()
        let data = encoder.encode(.bulkString("".data(using: .utf8)))
        let expected = "$0\r\n\r\n".data(using: .utf8)!
        XCTAssertEqual(data, expected)
    }

    func testEncodeArray() {
        let encoder = RESPEncoder()
        let arr: [RESPValue] = [
            .bulkString("foo".data(using: .utf8)),
            .bulkString("bar".data(using: .utf8))
        ]
        let data = encoder.encode(.array(arr))
        let expected = "*2\r\n$3\r\nfoo\r\n$3\r\nbar\r\n".data(using: .utf8)!
        XCTAssertEqual(data, expected)
    }

    func testEncodeEmptyArray() {
        let encoder = RESPEncoder()
        let data = encoder.encode(.array([]))
        let expected = "*0\r\n".data(using: .utf8)!
        XCTAssertEqual(data, expected)
    }

    func testEncodeNullArray() {
        let encoder = RESPEncoder()
        let data = encoder.encode(.array(nil))
        let expected = "*-1\r\n".data(using: .utf8)!
        XCTAssertEqual(data, expected)
    }

    func testEncodeDouble() {
        let encoder = RESPEncoder()
        let data = encoder.encode(.double(3.14))
        let expected = ",3.14\r\n".data(using: .utf8)!
        XCTAssertEqual(data, expected)
    }

    func testEncodeBoolean() {
        let encoder = RESPEncoder()
        let trueData = encoder.encode(.boolean(true))
        let expectedTrue = "#t\r\n".data(using: .utf8)!
        XCTAssertEqual(trueData, expectedTrue)

        let falseData = encoder.encode(.boolean(false))
        let expectedFalse = "#f\r\n".data(using: .utf8)!
        XCTAssertEqual(falseData, expectedFalse)
    }

    func testEncodeNull() {
        let encoder = RESPEncoder()
        let data = encoder.encode(.null)
        let expected = "_\r\n".data(using: .utf8)!
        XCTAssertEqual(data, expected)
    }

    func testEncodeMap() {
        let encoder = RESPEncoder()
        let map: [String: RESPValue] = [
            "key": .integer(100),
            "name": .bulkString("John".data(using: .utf8))
        ]
        let data = encoder.encode(.map(map))
        // Map ordering is not guaranteed, so we parse and verify
        let parser = RESPParser(data: data)
        let result = try! parser.parse()

        switch result {
        case .map(let dict):
            XCTAssertEqual(dict.count, 2)
            XCTAssertEqual(dict["key"]?.intValue, 100)
            XCTAssertEqual(dict["name"]?.stringValue, "John")
        default:
            XCTFail("Expected map")
        }
    }

    func testEncodeSet() {
        let encoder = RESPEncoder()
        let set: Set<String> = ["one", "two", "three"]
        let data = encoder.encode(.set(set))
        let parser = RESPParser(data: data)
        let result = try! parser.parse()

        switch result {
        case .set(let resultSet):
            XCTAssertEqual(resultSet.count, 3)
            XCTAssertTrue(resultSet.contains("one"))
            XCTAssertTrue(resultSet.contains("two"))
            XCTAssertTrue(resultSet.contains("three"))
        default:
            XCTFail("Expected set")
        }
    }

    func testRoundTripBulkString() throws {
        let original = "Hello, World!"
        let encoder = RESPEncoder()
        let encoded = encoder.encode(.bulkString(original.data(using: .utf8)))
        let parser = RESPParser(data: encoded)
        let decoded = try parser.parse()

        XCTAssertEqual(decoded.stringValue, original)
    }

    func testRoundTripArray() throws {
        let original: [RESPValue] = [
            .bulkString("foo".data(using: .utf8)),
            .integer(42),
            .bulkString("bar".data(using: .utf8))
        ]
        let encoder = RESPEncoder()
        let encoded = encoder.encode(.array(original))
        let parser = RESPParser(data: encoded)
        let decoded = try parser.parse()

        if case .array(let result) = decoded, let result = result {
            XCTAssertEqual(result.count, 3)
            XCTAssertEqual(result[0].stringValue, "foo")
            XCTAssertEqual(result[1].intValue, 42)
            XCTAssertEqual(result[2].stringValue, "bar")
        } else {
            XCTFail("Failed to decode array")
        }
    }
}
