import SwiftUI

// MARK: - JSON formatting + highlighting

enum JSONFormatter {
    /// Pretty-prints a JSON string (sorted keys, 2-space indent). Returns nil if
    /// the input isn't valid JSON.
    static func pretty(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("[") else { return nil }
        guard let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let out = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              var str = String(data: out, encoding: .utf8) else {
            return nil
        }
        // JSONSerialization uses escaped slashes; make output readable
        str = str.replacingOccurrences(of: "\\/", with: "/")
        return str
    }

    /// Whether a string looks like JSON.
    static func isJSON(_ raw: String) -> Bool {
        pretty(raw) != nil
    }
}

/// Syntax-highlighted, read-only JSON view. Shows the full content (scrollable),
/// no collapsible tree. Colors keys / strings / numbers / literals.
struct JSONHighlightedText: View {
    let text: String
    var highlight: String = ""
    var fontSize: CGFloat = 14

    @State private var cached: AttributedString?
    @State private var cachedKey: String = ""

    private var cacheKey: String { "\(text.count)_\(highlight)_\(fontSize)" }

    var body: some View {
        let attr = (cachedKey == cacheKey ? cached : nil) ?? Self.attributed(text, highlight: highlight)
        Text(attr)
            .font(.system(size: fontSize, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .lineSpacing(2)
            .task(id: cacheKey) {
                if cachedKey != cacheKey {
                    let t = text, h = highlight
                    let result = await Task.detached(priority: .userInitiated) {
                        Self.attributed(t, highlight: h)
                    }.value
                    if !Task.isCancelled {
                        cached = result
                        cachedKey = cacheKey
                    }
                }
            }
    }

    private nonisolated static let highlightLimit = 50_000

    private nonisolated static let numberRegex = try! NSRegularExpression(pattern: #"(?<![\w"])-?\d+(\.\d+)?([eE][+-]?\d+)?"#)
    private nonisolated static let boolRegex = try! NSRegularExpression(pattern: #"\b(true|false|null)\b"#)
    private nonisolated static let stringRegex = try! NSRegularExpression(pattern: #""(\\.|[^"\\])*""#)
    private nonisolated static let keyRegex = try! NSRegularExpression(pattern: #"("(\\.|[^"\\])*")\s*:"#)

    nonisolated static func attributed(_ input: String, highlight term: String = "") -> AttributedString {
        var attributed = AttributedString(input)
        attributed.foregroundColor = Theme.colors.text

        let syntaxHighlight = input.count <= highlightLimit

        func apply(_ regex: NSRegularExpression, _ color: Color, group: Int = 0) {
            guard syntaxHighlight else { return }
            let ns = input as NSString
            let matches = regex.matches(in: input, range: NSRange(location: 0, length: ns.length))
            for m in matches {
                let r = m.range(at: group)
                guard r.location != NSNotFound,
                      let range = Range(r, in: input),
                      let attrRange = Range(range, in: attributed) else { continue }
                attributed[attrRange].foregroundColor = color
            }
        }

        apply(numberRegex, Theme.colors.jsonNumber)
        apply(boolRegex, Theme.colors.jsonBool)
        apply(stringRegex, Theme.colors.jsonString)
        apply(keyRegex, Theme.colors.jsonKey, group: 1)

        let trimmed = term.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            let lowerInput = input.lowercased()
            let lowerTerm = trimmed.lowercased()
            var searchStart = lowerInput.startIndex
            while let found = lowerInput.range(of: lowerTerm, range: searchStart..<lowerInput.endIndex) {
                if let attrRange = Range(found, in: attributed) {
                    attributed[attrRange].backgroundColor = Theme.colors.warning.opacity(0.4)
                }
                searchStart = found.upperBound
            }
        }

        return attributed
    }
}
