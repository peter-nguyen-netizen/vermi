import Foundation

enum RESPValue: Equatable, Sendable {
    case simpleString(String)
    case error(String)
    case integer(Int64)
    case bulkString(Data?)
    case array([RESPValue]?)
    case map([String: RESPValue])
    case set(Set<String>)
    case double(Double)
    case boolean(Bool)
    case null
    case push([RESPValue])

    var stringValue: String? {
        switch self {
        case .simpleString(let s), .error(let s):
            return s
        case .bulkString(let data):
            return data.flatMap { String(data: $0, encoding: .utf8) }
        case .integer(let i):
            return String(i)
        case .double(let d):
            return String(d)
        case .boolean(let b):
            return String(b)
        case .null:
            return "(nil)"
        default:
            return nil
        }
    }

    var intValue: Int64? {
        switch self {
        case .integer(let i):
            return i
        case .bulkString(let data):
            return data.flatMap { Int64(String(data: $0, encoding: .utf8) ?? "") }
        default:
            return nil
        }
    }

    var arrayValue: [RESPValue]? {
        switch self {
        case .array(let arr):
            return arr
        case .push(let elements):
            return elements
        default:
            return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .double(let d):
            return d
        case .integer(let i):
            return Double(i)
        case .bulkString(let data):
            return data.flatMap { Double(String(data: $0, encoding: .utf8) ?? "") }
        default:
            return nil
        }
    }

    var isNull: Bool {
        switch self {
        case .null, .array(nil), .bulkString(nil):
            return true
        default:
            return false
        }
    }

    var isError: Bool {
        switch self {
        case .error:
            return true
        default:
            return false
        }
    }
}

enum RESPError: LocalizedError, Equatable, Sendable {
    case invalidFormat(String)
    case incompleteData
    case decodingError(String)
    case connectionError(String)
    case timeout
    /// An error reply sent by the Redis server (e.g. "MOVED", "WRONGTYPE", "NOAUTH").
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat(let m): return "Invalid response format: \(m)"
        case .incompleteData: return "Incomplete data from server"
        case .decodingError(let m): return "Decoding error: \(m)"
        case .connectionError(let m): return m
        case .timeout: return "Request timed out"
        case .serverError(let m): return m
        }
    }
}
