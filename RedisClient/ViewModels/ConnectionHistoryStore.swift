import Foundation
import Combine

@MainActor
final class ConnectionHistoryStore: ObservableObject {
    let connectionID: String

    @Published var searchPatterns: [String] = []
    @Published var commandHistory: [String] = []

    private var patternsKey: String { "SavedSearchPatterns.\(connectionID)" }
    private var historyKey: String { "CommandHistory.\(connectionID)" }

    private static var stores: [String: ConnectionHistoryStore] = [:]

    static func shared(for connectionID: String) -> ConnectionHistoryStore {
        if let existing = stores[connectionID] { return existing }
        let store = ConnectionHistoryStore(connectionID: connectionID)
        stores[connectionID] = store
        return store
    }

    static func release(_ connectionID: String) {
        stores.removeValue(forKey: connectionID)
    }

    private init(connectionID: String) {
        self.connectionID = connectionID
        searchPatterns = UserDefaults.standard.stringArray(forKey: patternsKey) ?? []
        commandHistory = (UserDefaults.standard.array(forKey: historyKey) as? [String]) ?? []
    }

    func savePattern(_ pattern: String) {
        let p = pattern.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty, p != "*" else { return }
        searchPatterns.removeAll { $0 == p }
        searchPatterns.insert(p, at: 0)
        if searchPatterns.count > 10 { searchPatterns = Array(searchPatterns.prefix(10)) }
        UserDefaults.standard.set(searchPatterns, forKey: patternsKey)
    }

    func removePattern(_ pattern: String) {
        searchPatterns.removeAll { $0 == pattern }
        UserDefaults.standard.set(searchPatterns, forKey: patternsKey)
    }

    func addCommand(_ command: String) {
        if commandHistory.last != command {
            commandHistory.append(command)
            if commandHistory.count > 100 {
                commandHistory.removeFirst()
            }
            UserDefaults.standard.set(commandHistory, forKey: historyKey)
        }
    }

    func clearCommandHistory() {
        commandHistory = []
        UserDefaults.standard.set(commandHistory, forKey: historyKey)
    }

    func clearAll() {
        searchPatterns = []
        commandHistory = []
        UserDefaults.standard.set(searchPatterns, forKey: patternsKey)
        UserDefaults.standard.set(commandHistory, forKey: historyKey)
    }
}
