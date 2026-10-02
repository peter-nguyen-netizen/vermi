import Foundation

/// How a binary (non-UTF-8) string value is rendered in the value panel.
enum BinaryViewMode: String, CaseIterable, Identifiable, Sendable {
    case text = "Text"
    case hex = "Hex"
    case base64 = "Base64"
    var id: String { rawValue }
}

/// Renders arbitrary bytes as readable text. Pure + nonisolated so it can run
/// in a detached task.
enum BinaryFormatter {
    static func format(_ data: Data, mode: BinaryViewMode) -> String {
        switch mode {
        case .text: return escaped(data)
        case .hex: return hexDump(data)
        case .base64: return data.base64EncodedString(options: [.lineLength76Characters, .endLineWithLineFeed])
        }
    }

    /// redis-cli style: valid UTF-8 (incl. multi-byte) kept as-is, control
    /// characters and invalid bytes escaped as `\xNN`, newlines/tabs kept.
    static func escaped(_ data: Data) -> String {
        let bytes = [UInt8](data)
        var out = String()
        out.reserveCapacity(bytes.count)
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            if b == 0x0A || b == 0x09 {
                out.unicodeScalars.append(Unicode.Scalar(b))
                i += 1
            } else if b >= 0x20 && b < 0x7F {
                if b == 0x5C { out += "\\\\" } else { out.unicodeScalars.append(Unicode.Scalar(b)) }
                i += 1
            } else if b >= 0x80, let (scalar, len) = decodeUTF8(bytes, at: i) {
                out.unicodeScalars.append(scalar)
                i += len
            } else {
                out += String(format: "\\x%02x", b)
                i += 1
            }
        }
        return out
    }

    /// `offset  hex bytes (16/line)  |ascii|` — classic hexdump layout.
    static func hexDump(_ data: Data) -> String {
        let bytes = [UInt8](data)
        let hexDigits = Array("0123456789abcdef")
        var lines: [String] = []
        lines.reserveCapacity(bytes.count / 16 + 1)
        var offset = 0
        while offset < bytes.count {
            let chunk = bytes[offset..<min(offset + 16, bytes.count)]
            var line = String(format: "%08x  ", offset)
            for (n, b) in chunk.enumerated() {
                line.append(hexDigits[Int(b >> 4)])
                line.append(hexDigits[Int(b & 0x0F)])
                line += n == 7 ? "  " : " "
            }
            if chunk.count < 16 {
                let missing = 16 - chunk.count
                line += String(repeating: "   ", count: missing) + (chunk.count <= 7 ? " " : "")
            }
            line += " |"
            for b in chunk {
                line.append(b >= 0x20 && b < 0x7F ? Character(Unicode.Scalar(b)) : ".")
            }
            line += "|"
            lines.append(line)
            offset += 16
        }
        return lines.joined(separator: "\n")
    }

    /// Decode one well-formed UTF-8 sequence (2–4 bytes) starting at `i`.
    private static func decodeUTF8(_ bytes: [UInt8], at i: Int) -> (Unicode.Scalar, Int)? {
        let b0 = bytes[i]
        let len: Int
        switch b0 {
        case 0xC2...0xDF: len = 2
        case 0xE0...0xEF: len = 3
        case 0xF0...0xF4: len = 4
        default: return nil
        }
        guard i + len <= bytes.count else { return nil }
        var value = UInt32(b0) & (len == 2 ? 0x1F : len == 3 ? 0x0F : 0x07)
        for k in 1..<len {
            let c = bytes[i + k]
            guard c & 0xC0 == 0x80 else { return nil }
            value = (value << 6) | UInt32(c & 0x3F)
        }
        // Reject overlongs, surrogates, out-of-range; Unicode.Scalar init
        // rejects surrogates/out-of-range.
        let minValue: UInt32 = len == 3 ? 0x800 : len == 4 ? 0x10000 : 0x80
        guard value >= minValue, let scalar = Unicode.Scalar(value) else { return nil }
        // Skip C1 controls / invisible noise — escape them instead.
        if value < 0xA0 { return nil }
        return (scalar, len)
    }
}
