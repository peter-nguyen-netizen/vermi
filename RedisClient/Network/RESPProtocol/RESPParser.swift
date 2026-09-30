import Foundation

final class RESPParser {
    private let data: Data
    private var offset: Int = 0

    /// Bytes consumed by the last successful parse(). Callers use this to
    /// keep unconsumed trailing bytes (next pipelined response) in the buffer.
    var consumedOffset: Int { offset }

    init(data: Data) {
        self.data = data
    }

    func parse() throws -> RESPValue {
        let value = try parseValue()
        return value
    }

    private func parseValue() throws -> RESPValue {
        guard offset < data.count else {
            throw RESPError.incompleteData
        }

        let byte = data[offset]
        offset += 1

        switch byte {
        case UInt8(ascii: "+"):
            return try parseSimpleString()
        case UInt8(ascii: "-"):
            return try parseError()
        case UInt8(ascii: ":"):
            return try parseInteger()
        case UInt8(ascii: "$"):
            return try parseBulkString()
        case UInt8(ascii: "*"):
            return try parseArray()
        case UInt8(ascii: "%"):
            return try parseMap()
        case UInt8(ascii: "~"):
            return try parseSet()
        case UInt8(ascii: ","):
            return try parseDouble()
        case UInt8(ascii: "#"):
            return try parseBoolean()
        case UInt8(ascii: "|"):
            return try parseAttribute()
        case UInt8(ascii: ">"):
            return try parsePush()
        default:
            throw RESPError.invalidFormat("Unknown RESP type marker: \(Character(UnicodeScalar(byte)))")
        }
    }

    private func parseSimpleString() throws -> RESPValue {
        let str = try readLine()
        return .simpleString(str)
    }

    private func parseError() throws -> RESPValue {
        let str = try readLine()
        return .error(str)
    }

    private func parseInteger() throws -> RESPValue {
        let str = try readLine()
        guard let int = Int64(str) else {
            throw RESPError.decodingError("Invalid integer: \(str)")
        }
        return .integer(int)
    }

    private func parseBulkString() throws -> RESPValue {
        let lenStr = try readLine()
        guard let len = Int(lenStr) else {
            throw RESPError.decodingError("Invalid bulk string length: \(lenStr)")
        }

        if len == -1 {
            return .bulkString(nil)
        }

        guard len >= 0 else {
            throw RESPError.decodingError("Invalid bulk string length: \(len)")
        }

        let startOffset = offset
        offset += len

        guard offset <= data.count else {
            throw RESPError.incompleteData
        }

        let bulkData = data.subdata(in: startOffset..<offset)

        try skipCRLF()

        return .bulkString(bulkData)
    }

    private func parseArray() throws -> RESPValue {
        let countStr = try readLine()
        guard let count = Int(countStr) else {
            throw RESPError.decodingError("Invalid array count: \(countStr)")
        }

        if count == -1 {
            return .array(nil)
        }

        guard count >= 0 else {
            throw RESPError.decodingError("Invalid array count: \(count)")
        }

        var elements: [RESPValue] = []
        for _ in 0..<count {
            elements.append(try parseValue())
        }

        return .array(elements)
    }

    private func parseMap() throws -> RESPValue {
        let countStr = try readLine()
        guard let count = Int(countStr) else {
            throw RESPError.decodingError("Invalid map count: \(countStr)")
        }

        var map: [String: RESPValue] = [:]
        for _ in 0..<count {
            let keyValue = try parseValue()
            let valueValue = try parseValue()

            guard let key = keyValue.stringValue else {
                throw RESPError.decodingError("Map key must be a string")
            }

            map[key] = valueValue
        }

        return .map(map)
    }

    private func parseSet() throws -> RESPValue {
        let countStr = try readLine()
        guard let count = Int(countStr) else {
            throw RESPError.decodingError("Invalid set count: \(countStr)")
        }

        var set: Set<String> = []
        for _ in 0..<count {
            let value = try parseValue()
            if let stringVal = value.stringValue {
                set.insert(stringVal)
            }
        }

        return .set(set)
    }

    private func parseDouble() throws -> RESPValue {
        let str = try readLine()
        guard let double = Double(str) else {
            throw RESPError.decodingError("Invalid double: \(str)")
        }
        return .double(double)
    }

    private func parseBoolean() throws -> RESPValue {
        let str = try readLine()
        let value = str == "t"
        return .boolean(value)
    }

    private func parseAttribute() throws -> RESPValue {
        let countStr = try readLine()
        guard let count = Int(countStr) else {
            throw RESPError.decodingError("Invalid attribute count: \(countStr)")
        }

        for _ in 0..<count {
            _ = try parseValue()
            _ = try parseValue()
        }

        return try parseValue()
    }

    private func parsePush() throws -> RESPValue {
        let countStr = try readLine()
        guard let count = Int(countStr) else {
            throw RESPError.decodingError("Invalid push count: \(countStr)")
        }

        var elements: [RESPValue] = []
        for _ in 0..<count {
            elements.append(try parseValue())
        }

        return .push(elements)
    }

    private func readLine() throws -> String {
        var lineData = Data()
        var foundCR = false

        while offset < data.count {
            let byte = data[offset]
            offset += 1

            if byte == UInt8(ascii: "\r") {
                // CR at the very end: LF hasn't arrived yet → wait for more data.
                guard offset < data.count else {
                    throw RESPError.incompleteData
                }
                guard data[offset] == UInt8(ascii: "\n") else {
                    throw RESPError.invalidFormat("Expected LF after CR")
                }
                offset += 1
                foundCR = true
                break
            }

            lineData.append(byte)
        }

        // Reached end of buffer without a terminating CRLF → frame is incomplete.
        guard foundCR else {
            throw RESPError.incompleteData
        }

        guard let str = String(data: lineData, encoding: .utf8) else {
            throw RESPError.decodingError("Failed to decode line as UTF-8")
        }

        return str
    }

    private func skipCRLF() throws {
        guard offset < data.count else { throw RESPError.incompleteData }
        guard data[offset] == UInt8(ascii: "\r") else {
            throw RESPError.invalidFormat("Expected CR")
        }
        offset += 1

        guard offset < data.count else { throw RESPError.incompleteData }
        guard data[offset] == UInt8(ascii: "\n") else {
            throw RESPError.invalidFormat("Expected LF")
        }
        offset += 1
    }
}
