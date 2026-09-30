import Foundation
import Combine

@MainActor
final class CommandExecutorViewModel: NSObject, ObservableObject {
    @Published var commandInput: String = ""
    /// Text result of the CURRENT command only (raw formatting).
    @Published var result: String = ""
    /// Raw reply of the current command, kept so the result can be re-rendered
    /// as JSON on demand.
    @Published var lastValue: RESPValue?
    /// The command that produced the current result (drives JSON pairing, e.g. HGETALL).
    @Published var lastCommand: String = ""
    @Published var didRun: Bool = false
    @Published var resultType: ResultType = .raw
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var historyIndex: Int?
    /// Starred commands (persisted), for quick re-run.
    @Published var favorites: [String] = []
    private let favoritesKey = "CommandFavorites"

    enum ResultType: String {
        case raw = "Raw"
        case json = "JSON"
    }

    private var redisClient: RedisClientProtocol?
    private(set) var historyStore: ConnectionHistoryStore?
    private var storeCancellable: AnyCancellable?

    func setClient(_ client: RedisClientProtocol) {
        self.redisClient = client
        favorites = UserDefaults.standard.stringArray(forKey: favoritesKey) ?? []
    }

    func setConnectionID(_ id: String) {
        let store = ConnectionHistoryStore.shared(for: id)
        self.historyStore = store
        historyIndex = nil
        storeCancellable = store.$commandHistory
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }

    var isCurrentFavorite: Bool {
        let c = commandInput.trimmingCharacters(in: .whitespaces)
        return !c.isEmpty && favorites.contains(c)
    }

    /// Star / unstar the current command input.
    func toggleFavorite() {
        let c = commandInput.trimmingCharacters(in: .whitespaces)
        guard !c.isEmpty else { return }
        if let i = favorites.firstIndex(of: c) {
            favorites.remove(at: i)
        } else {
            favorites.insert(c, at: 0)
            if favorites.count > 30 { favorites = Array(favorites.prefix(30)) }
        }
        UserDefaults.standard.set(favorites, forKey: favoritesKey)
    }

    func removeFavorite(_ cmd: String) {
        favorites.removeAll { $0 == cmd }
        UserDefaults.standard.set(favorites, forKey: favoritesKey)
    }

    var recentCommands: [String] {
        Array((historyStore?.commandHistory ?? []).reversed().prefix(30))
    }

    func executeCommand() async {
        guard !commandInput.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Command not empty"
            return
        }

        guard let client = redisClient else {
            errorMessage = "No connection"
            return
        }

        let parts = Self.tokenize(commandInput)
        guard !parts.isEmpty else {
            errorMessage = "Command not empty"
            return
        }

        let command = commandInput
        do {
            isLoading = true
            errorMessage = nil

            let value = try await client.execute(parts)
            addToHistory(command)

            let (text, isError) = Self.render(value)
            result = text
            lastValue = value
            lastCommand = command
            didRun = true
            errorMessage = isError ? text : nil
        } catch {
            let msg = error.localizedDescription
            errorMessage = msg
            result = msg
            lastValue = .error(msg)
            lastCommand = command
            didRun = true
        }

        isLoading = false
    }

    /// The current result rendered as pretty JSON (hash → object, nested JSON
    /// string values expanded). nil when there's nothing sensible to show.
    func resultAsJSON() -> String? {
        guard let value = lastValue else { return JSONFormatter.pretty(result) }
        return Self.jsonPretty(value, command: lastCommand)
    }

    /// Key-name suggestions for the Console, backed by one SCAN page (read-only,
    /// cluster-safe). Matched by `prefix*`.
    func keySuggestions(prefix: String, limit: Int = 8) async -> [String] {
        guard let client = redisClient else { return [] }
        let pattern = prefix.isEmpty ? "*" : "\(prefix)*"
        guard let (_, keys) = try? await client.scan(cursor: 0, pattern: pattern, count: 300) else { return [] }
        return Array(keys.prefix(limit))
    }

    /// Split a command line into arguments, honoring single/double quotes and
    /// backslash escapes (like redis-cli). So a field with spaces can be passed
    /// as `"color:anti oxi"` or `'color:anti oxi'`, and it stays one argument.
    static func tokenize(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var hasCurrent = false
        var quote: Character? = nil   // nil, '"', or '\''
        var escaped = false

        for ch in input {
            if escaped {
                current.append(ch)
                hasCurrent = true
                escaped = false
                continue
            }
            if ch == "\\" && quote != "'" {
                // Backslash escapes outside single quotes
                escaped = true
                hasCurrent = true
                continue
            }
            if let q = quote {
                if ch == q {
                    quote = nil            // close quote
                } else {
                    current.append(ch)
                }
                hasCurrent = true
                continue
            }
            if ch == "\"" || ch == "'" {
                quote = ch                 // open quote
                hasCurrent = true
                continue
            }
            if ch == " " || ch == "\t" {
                if hasCurrent {
                    tokens.append(current)
                    current = ""
                    hasCurrent = false
                }
                continue
            }
            current.append(ch)
            hasCurrent = true
        }
        if hasCurrent {
            tokens.append(current)
        }
        return tokens
    }

    func addToHistory(_ command: String) {
        historyStore?.addCommand(command)
        historyIndex = nil
    }

    func previousCommand() {
        let storage = historyStore?.commandHistory ?? []
        let index = historyIndex ?? storage.count
        if index > 0 {
            historyIndex = index - 1
            commandInput = storage[index - 1]
        }
    }

    func nextCommand() {
        let storage = historyStore?.commandHistory ?? []
        guard let index = historyIndex else { return }
        if index < storage.count - 1 {
            historyIndex = index + 1
            commandInput = storage[index + 1]
        } else {
            historyIndex = nil
            commandInput = ""
        }
    }

    func clearHistory() {
        historyStore?.clearCommandHistory()
        historyIndex = nil
    }

    /// Format a RESP value for display. Returns the text and whether it's an error.
    static func render(_ value: RESPValue) -> (String, Bool) {
        switch value {
        case .simpleString(let str):
            return ("OK: \(str)", false)
        case .error(let err):
            return ("Error: \(err)", true)
        case .integer(let num):
            return ("(integer) \(num)", false)
        case .bulkString(let data):
            if let str = data.flatMap({ String(data: $0, encoding: .utf8) }) {
                return (str, false)
            } else if let data = data {
                return ("[\(data.count) bytes]", false)
            } else {
                return ("(nil)", false)
            }
        case .array(let arr):
            return (arr.map { formatArray($0) } ?? "(nil array)", false)
        case .map(let dict):
            return (formatMap(dict), false)
        case .set(let set):
            return (set.sorted().joined(separator: "\n"), false)
        case .double(let d):
            return (String(d), false)
        case .boolean(let b):
            return (b ? "true" : "false", false)
        case .null:
            return ("(nil)", false)
        case .push(let arr):
            return ("PUSH: " + arr.map { valueToString($0) }.joined(separator: ", "), false)
        }
    }

    // MARK: RESP → JSON

    /// Pretty JSON for a RESP reply. Hash-like replies (HGETALL, CONFIG GET)
    /// become objects; string values that are themselves JSON are nested.
    static func jsonPretty(_ value: RESPValue, command: String) -> String? {
        let obj = jsonObject(from: value, command: command)
        guard let data = try? JSONSerialization.data(
            withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]),
              var str = String(data: data, encoding: .utf8) else { return nil }
        str = str.replacingOccurrences(of: "\\/", with: "/")
        return str
    }

    private static func jsonObject(from value: RESPValue, command: String) -> Any {
        switch value {
        case .null:
            return NSNull()
        case .integer(let i):
            return i
        case .double(let d):
            return d
        case .boolean(let b):
            return b
        case .simpleString(let s), .error(let s):
            return expandJSONString(s)
        case .bulkString(let data):
            guard let data, let s = String(data: data, encoding: .utf8) else { return NSNull() }
            return expandJSONString(s)
        case .set(let set):
            return set.sorted().map { expandJSONString($0) }
        case .map(let dict):
            var out: [String: Any] = [:]
            for (k, v) in dict { out[k] = jsonObject(from: v, command: "") }
            return out
        case .push(let arr):
            return arr.map { jsonObject(from: $0, command: "") }
        case .array(let arr):
            guard let arr else { return NSNull() }
            // Pair field/value arrays into an object for hash-like replies.
            let verb = command.split(separator: " ").first.map { $0.uppercased() } ?? ""
            let pairVerbs: Set<String> = ["HGETALL", "CONFIG", "XPENDING"]
            if pairVerbs.contains(verb), arr.count % 2 == 0, !arr.isEmpty,
               arr.enumerated().allSatisfy({ i, v in i % 2 == 1 || scalarString(v) != nil }) {
                var out: [String: Any] = [:]
                var i = 0
                while i < arr.count {
                    let key = scalarString(arr[i]) ?? "\(i)"
                    out[key] = jsonObject(from: arr[i + 1], command: "")
                    i += 2
                }
                return out
            }
            return arr.map { jsonObject(from: $0, command: "") }
        }
    }

    /// A JSON container string is parsed so it nests; otherwise kept as a string.
    private static func expandJSONString(_ s: String) -> Any {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if (t.hasPrefix("{") || t.hasPrefix("[")),
           let d = t.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed]) {
            return obj
        }
        return s
    }

    private static func scalarString(_ v: RESPValue) -> String? {
        switch v {
        case .simpleString(let s), .error(let s): return s
        case .bulkString(let d): return d.flatMap { String(data: $0, encoding: .utf8) }
        case .integer(let i): return String(i)
        default: return nil
        }
    }

    private static func formatArray(_ arr: [RESPValue]) -> String {
        let items = arr.enumerated().map { i, v in
            "\(i + 1)) \(valueToString(v))"
        }
        return items.joined(separator: "\n")
    }

    private static func formatMap(_ dict: [String: RESPValue]) -> String {
        let items = dict.sorted { $0.key < $1.key }.map { k, v in
            "\(k): \(valueToString(v))"
        }
        return items.joined(separator: "\n")
    }

    private static func valueToString(_ value: RESPValue) -> String {
        switch value {
        case .simpleString(let s), .error(let s):
            return s
        case .integer(let i):
            return String(i)
        case .bulkString(let data):
            return data.flatMap { String(data: $0, encoding: .utf8) } ?? "(binary)"
        case .array(let arr):
            if let arr = arr {
                return arr.map { valueToString($0) }.joined(separator: ", ")
            } else {
                return "(nil)"
            }
        default:
            return value.stringValue ?? "(complex)"
        }
    }


    func reset() {
        commandInput = ""
        result = ""
        lastValue = nil
        lastCommand = ""
        didRun = false
        resultType = .raw
        errorMessage = nil
        historyIndex = nil
    }
}
