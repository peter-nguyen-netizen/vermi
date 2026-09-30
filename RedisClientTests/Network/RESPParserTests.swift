import XCTest
@testable import RedisClient

final class RESPParserTests: XCTestCase {

    func testParseSimpleString() throws {
        let data = "+OK\r\n".data(using: .utf8)!
        let parser = RESPParser(data: data)
        let value = try parser.parse()

        switch value {
        case .simpleString(let str):
            XCTAssertEqual(str, "OK")
        default:
            XCTFail("Expected simpleString")
        }
    }

    func testParseError() throws {
        let data = "-ERR unknown command\r\n".data(using: .utf8)!
        let parser = RESPParser(data: data)
        let value = try parser.parse()

        switch value {
        case .error(let str):
            XCTAssertEqual(str, "ERR unknown command")
        default:
            XCTFail("Expected error")
        }
    }

    func testParseInteger() throws {
        let data = ":1000\r\n".data(using: .utf8)!
        let parser = RESPParser(data: data)
        let value = try parser.parse()

        switch value {
        case .integer(let num):
            XCTAssertEqual(num, 1000)
        default:
            XCTFail("Expected integer")
        }
    }

    func testParseNegativeInteger() throws {
        let data = ":-1000\r\n".data(using: .utf8)!
        let parser = RESPParser(data: data)
        let value = try parser.parse()

        switch value {
        case .integer(let num):
            XCTAssertEqual(num, -1000)
        default:
            XCTFail("Expected integer")
        }
    }

    func testParseBulkString() throws {
        let data = "$6\r\nfoobar\r\n".data(using: .utf8)!
        let parser = RESPParser(data: data)
        let value = try parser.parse()

        switch value {
        case .bulkString(let data):
            XCTAssertEqual(String(data: data!, encoding: .utf8), "foobar")
        default:
            XCTFail("Expected bulkString")
        }
    }

    func testParseBulkStringNull() throws {
        let data = "$-1\r\n".data(using: .utf8)!
        let parser = RESPParser(data: data)
        let value = try parser.parse()

        switch value {
        case .bulkString(let data):
            XCTAssertNil(data)
        default:
            XCTFail("Expected null bulkString")
        }
    }

    func testParseEmptyBulkString() throws {
        let data = "$0\r\n\r\n".data(using: .utf8)!
        let parser = RESPParser(data: data)
        let value = try parser.parse()

        switch value {
        case .bulkString(let data):
            XCTAssertEqual(data?.count, 0)
        default:
            XCTFail("Expected empty bulkString")
        }
    }

    func testParseArray() throws {
        let data = "*2\r\n$3\r\nfoo\r\n$3\r\nbar\r\n".data(using: .utf8)!
        let parser = RESPParser(data: data)
        let value = try parser.parse()

        switch value {
        case .array(let arr):
            XCTAssertEqual(arr?.count, 2)
            if let arr = arr {
                XCTAssertEqual(arr[0].stringValue, "foo")
                XCTAssertEqual(arr[1].stringValue, "bar")
            }
        default:
            XCTFail("Expected array")
        }
    }

    func testParseEmptyArray() throws {
        let data = "*0\r\n".data(using: .utf8)!
        let parser = RESPParser(data: data)
        let value = try parser.parse()

        switch value {
        case .array(let arr):
            XCTAssertEqual(arr?.count, 0)
        default:
            XCTFail("Expected empty array")
        }
    }

    func testParseNullArray() throws {
        let data = "*-1\r\n".data(using: .utf8)!
        let parser = RESPParser(data: data)
        let value = try parser.parse()

        switch value {
        case .array(let arr):
            XCTAssertNil(arr)
        default:
            XCTFail("Expected null array")
        }
    }

    func testParseNestedArray() throws {
        let data = "*2\r\n*2\r\n:1\r\n:2\r\n*2\r\n:3\r\n:4\r\n".data(using: .utf8)!
        let parser = RESPParser(data: data)
        let value = try parser.parse()

        switch value {
        case .array(let arr):
            XCTAssertEqual(arr?.count, 2)
            if let arr = arr {
                XCTAssertEqual(arr[0].arrayValue?.count, 2)
                XCTAssertEqual(arr[1].arrayValue?.count, 2)
            }
        default:
            XCTFail("Expected nested array")
        }
    }

    func testParseDouble() throws {
        let data = ",3.14\r\n".data(using: .utf8)!
        let parser = RESPParser(data: data)
        let value = try parser.parse()

        switch value {
        case .double(let num):
            XCTAssertEqual(num, 3.14)
        default:
            XCTFail("Expected double")
        }
    }

    func testParseBoolean() throws {
        let trueData = "#t\r\n".data(using: .utf8)!
        let parser = RESPParser(data: trueData)
        let value = try parser.parse()

        switch value {
        case .boolean(let bool):
            XCTAssertTrue(bool)
        default:
            XCTFail("Expected boolean")
        }
    }

    func testParseMap() throws {
        let data = "%2\r\n$3\r\nkey\r\n:100\r\n$4\r\nname\r\n$4\r\nJohn\r\n".data(using: .utf8)!
        let parser = RESPParser(data: data)
        let value = try parser.parse()

        switch value {
        case .map(let dict):
            XCTAssertEqual(dict.count, 2)
            XCTAssertEqual(dict["key"]?.intValue, 100)
            XCTAssertEqual(dict["name"]?.stringValue, "John")
        default:
            XCTFail("Expected map")
        }
    }

    func testParseSet() throws {
        let data = "~2\r\n$3\r\none\r\n$3\r\ntwo\r\n".data(using: .utf8)!
        let parser = RESPParser(data: data)
        let value = try parser.parse()

        switch value {
        case .set(let set):
            XCTAssertEqual(set.count, 2)
            XCTAssertTrue(set.contains("one"))
            XCTAssertTrue(set.contains("two"))
        default:
            XCTFail("Expected set")
        }
    }

    func testParseIncompleteData() throws {
        let data = "$6\r\nfoob".data(using: .utf8)!
        let parser = RESPParser(data: data)

        XCTAssertThrowsError(try parser.parse()) { error in
            XCTAssertEqual(error as? RESPError, .incompleteData)
        }
    }

    // A line split mid-frame (no CRLF yet) must be incompleteData, NOT a format
    // error — otherwise the receive buffer desyncs ("Expected CR/LF").
    func testParseSimpleStringWithoutTerminatorIsIncomplete() throws {
        let parser = RESPParser(data: "+OK".data(using: .utf8)!)
        XCTAssertThrowsError(try parser.parse()) { error in
            XCTAssertEqual(error as? RESPError, .incompleteData)
        }
    }

    func testParseBulkStringMissingTrailingCRLFIsIncomplete() throws {
        // Length + data present, but the terminating CRLF hasn't arrived.
        let parser = RESPParser(data: "$3\r\nfoo".data(using: .utf8)!)
        XCTAssertThrowsError(try parser.parse()) { error in
            XCTAssertEqual(error as? RESPError, .incompleteData)
        }
    }

    func testParseCRWithoutLFIsIncomplete() throws {
        let parser = RESPParser(data: "+OK\r".data(using: .utf8)!)
        XCTAssertThrowsError(try parser.parse()) { error in
            XCTAssertEqual(error as? RESPError, .incompleteData)
        }
    }

    func testParseInvalidFormat() throws {
        let data = "invalid\r\n".data(using: .utf8)!
        let parser = RESPParser(data: data)

        XCTAssertThrowsError(try parser.parse()) { error in
            if case .invalidFormat = error as? RESPError {
                // Pass
            } else {
                XCTFail("Expected invalidFormat error")
            }
        }
    }

    // Pipeline read path: multiple replies concatenated in one buffer must be
    // parsed sequentially via consumedOffset (as NetworkChannel.drainBuffer does).
    func testParseMultipleConcatenatedFrames() throws {
        var buffer = Data("+OK\r\n:42\r\n$3\r\nabc\r\n".utf8)
        var values: [RESPValue] = []
        while !buffer.isEmpty {
            let parser = RESPParser(data: buffer)
            let v = try parser.parse()
            values.append(v)
            buffer = buffer.subdata(in: parser.consumedOffset..<buffer.count)
        }
        XCTAssertEqual(values.count, 3)
        XCTAssertEqual(values[0].stringValue, "OK")
        XCTAssertEqual(values[1].intValue, 42)
        XCTAssertEqual(values[2].stringValue, "abc")
    }

    // A trailing incomplete frame after complete ones stops cleanly (waits for more).
    func testParseFramesThenIncompleteTail() throws {
        var buffer = Data(":1\r\n:2\r\n$5\r\npar".utf8)   // third frame truncated
        var values: [RESPValue] = []
        var incomplete = false
        while !buffer.isEmpty {
            let parser = RESPParser(data: buffer)
            do {
                let v = try parser.parse()
                values.append(v)
                buffer = buffer.subdata(in: parser.consumedOffset..<buffer.count)
            } catch RESPError.incompleteData {
                incomplete = true
                break
            }
        }
        XCTAssertEqual(values.count, 2)
        XCTAssertTrue(incomplete)
    }

    func testBinaryData() throws {
        let binaryData = Data([0x00, 0x01, 0x02, 0x03])
        var fullData = Data("$4\r\n".utf8)
        fullData.append(binaryData)
        fullData.append(Data("\r\n".utf8))

        let parser = RESPParser(data: fullData)
        let value = try parser.parse()

        switch value {
        case .bulkString(let data):
            XCTAssertEqual(data, binaryData)
        default:
            XCTFail("Expected bulkString with binary data")
        }
    }
}
