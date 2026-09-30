import Foundation

final class RESPEncoder {
    private var buffer = Data()

    func encode(_ command: [String]) -> Data {
        buffer.removeAll()
        encodeArray(command.map { .bulkString($0.data(using: .utf8)) })
        return buffer
    }

    func encode(_ value: RESPValue) -> Data {
        buffer.removeAll()
        encodeValue(value)
        return buffer
    }

    private func encodeValue(_ value: RESPValue) {
        switch value {
        case .simpleString(let str):
            encodeSimpleString(str)
        case .error(let str):
            encodeError(str)
        case .integer(let num):
            encodeInteger(num)
        case .bulkString(let data):
            encodeBulkString(data)
        case .array(let arr):
            if let arr = arr {
                encodeArray(arr)
            } else {
                // RESP2 null array — we speak RESP2 (no HELLO 3 handshake)
                buffer.append(contentsOf: "*-1\r\n".data(using: .utf8) ?? Data())
            }
        case .map(let dict):
            encodeMap(dict)
        case .set(let set):
            encodeSet(set)
        case .double(let num):
            encodeDouble(num)
        case .boolean(let bool):
            encodeBoolean(bool)
        case .null:
            encodeNull()
        case .push(let arr):
            encodePush(arr)
        }
    }

    private func encodeSimpleString(_ str: String) {
        buffer.append(UInt8(ascii: "+"))
        if let data = str.data(using: .utf8) {
            buffer.append(data)
        }
        appendCRLF()
    }

    private func encodeError(_ str: String) {
        buffer.append(UInt8(ascii: "-"))
        if let data = str.data(using: .utf8) {
            buffer.append(data)
        }
        appendCRLF()
    }

    private func encodeInteger(_ num: Int64) {
        buffer.append(UInt8(ascii: ":"))
        if let data = String(num).data(using: .utf8) {
            buffer.append(data)
        }
        appendCRLF()
    }

    private func encodeBulkString(_ data: Data?) {
        if let data = data {
            buffer.append(UInt8(ascii: "$"))
            if let lenStr = String(data.count).data(using: .utf8) {
                buffer.append(lenStr)
            }
            appendCRLF()
            buffer.append(data)
            appendCRLF()
        } else {
            buffer.append(UInt8(ascii: "$"))
            buffer.append(contentsOf: "-1".data(using: .utf8)!)
            appendCRLF()
        }
    }

    private func encodeArray(_ arr: [RESPValue]) {
        buffer.append(UInt8(ascii: "*"))
        if let data = String(arr.count).data(using: .utf8) {
            buffer.append(data)
        }
        appendCRLF()

        for value in arr {
            encodeValue(value)
        }
    }

    private func encodeMap(_ dict: [String: RESPValue]) {
        buffer.append(UInt8(ascii: "%"))
        if let data = String(dict.count).data(using: .utf8) {
            buffer.append(data)
        }
        appendCRLF()

        for (key, value) in dict {
            encodeBulkString(key.data(using: .utf8))
            encodeValue(value)
        }
    }

    private func encodeSet(_ set: Set<String>) {
        buffer.append(UInt8(ascii: "~"))
        if let data = String(set.count).data(using: .utf8) {
            buffer.append(data)
        }
        appendCRLF()

        for value in set {
            encodeBulkString(value.data(using: .utf8))
        }
    }

    private func encodeDouble(_ num: Double) {
        buffer.append(UInt8(ascii: ","))
        if let data = String(num).data(using: .utf8) {
            buffer.append(data)
        }
        appendCRLF()
    }

    private func encodeBoolean(_ bool: Bool) {
        buffer.append(UInt8(ascii: "#"))
        buffer.append(UInt8(ascii: bool ? "t" : "f"))
        appendCRLF()
    }

    private func encodeNull() {
        buffer.append(contentsOf: "_\r\n".data(using: .utf8) ?? Data())
    }

    private func encodePush(_ arr: [RESPValue]) {
        buffer.append(UInt8(ascii: ">"))
        if let data = String(arr.count).data(using: .utf8) {
            buffer.append(data)
        }
        appendCRLF()

        for value in arr {
            encodeValue(value)
        }
    }

    private func appendCRLF() {
        buffer.append(UInt8(ascii: "\r"))
        buffer.append(UInt8(ascii: "\n"))
    }
}
