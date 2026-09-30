import Foundation

/// Redis Cluster helpers: hash-slot computation (CRC16/XMODEM) and redirect parsing.
enum RedisCluster {
    static let slotCount = 16384

    /// Compute the hash slot for a key, honoring `{hashtag}` semantics.
    static func slot(for key: String) -> Int {
        let hashKey = hashTag(key)
        return Int(crc16(hashKey)) % slotCount
    }

    /// If the key contains `{...}` with non-empty content, only that substring
    /// is hashed (so related keys land on the same slot).
    private static func hashTag(_ key: String) -> String {
        guard let open = key.firstIndex(of: "{") else { return key }
        let afterOpen = key.index(after: open)
        guard let close = key[afterOpen...].firstIndex(of: "}"), close != afterOpen else {
            return key
        }
        return String(key[afterOpen..<close])
    }

    /// CRC16-CCITT (XMODEM) as used by Redis Cluster.
    static func crc16(_ string: String) -> UInt16 {
        var crc: UInt16 = 0
        for byte in Array(string.utf8) {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                if crc & 0x8000 != 0 {
                    crc = (crc << 1) ^ 0x1021
                } else {
                    crc <<= 1
                }
            }
        }
        return crc
    }

    /// A parsed MOVED / ASK redirect from a `-MOVED 3999 127.0.0.1:6381` error.
    struct Redirect {
        enum Kind { case moved, ask }
        let kind: Kind
        let slot: Int
        let host: String
        let port: UInt16
        var nodeKey: String { "\(host):\(port)" }
    }

    /// Parse a redirect out of a Redis error string, or nil if it isn't one.
    static func parseRedirect(_ error: String) -> Redirect? {
        let parts = error.split(separator: " ")
        guard parts.count >= 3 else { return nil }
        let kind: Redirect.Kind
        switch parts[0].uppercased() {
        case "MOVED": kind = .moved
        case "ASK": kind = .ask
        default: return nil
        }
        guard let slot = Int(parts[1]) else { return nil }
        let endpoint = parts[2]
        // endpoint may be host:port or ipv6 [::1]:port — split on last colon
        guard let colon = endpoint.lastIndex(of: ":") else { return nil }
        let host = String(endpoint[endpoint.startIndex..<colon])
        guard let port = UInt16(endpoint[endpoint.index(after: colon)...]) else { return nil }
        return Redirect(kind: kind, slot: slot, host: host, port: port)
    }

    /// First key argument for a command (position 1 for most commands).
    static func firstKey(of command: [String]) -> String? {
        guard command.count >= 2 else { return nil }
        return command[1]
    }

    /// Group keys by the node owning their hash slot (per `slotMap`), so each
    /// node's keys can be pipelined together. Keys with an unknown slot fall to
    /// `fallback` (typically the primary, which will then MOVED-redirect them).
    static func groupByNode(_ keys: [String], slotMap: [Int: String], fallback: String) -> [String: [String]] {
        var groups: [String: [String]] = [:]
        for key in keys {
            let node = slotMap[slot(for: key)] ?? fallback
            groups[node, default: []].append(key)
        }
        return groups
    }
}
