import SwiftUI

/// App-level menu commands post these; MainWindowView observes and acts (it owns
/// the AppState). Menu items give the shortcuts a discoverable home in the menu bar.
enum VermiCommand: String {
    case newConnection, closeTab, focusSearch, refresh
    case tab1, tab2, tab3, tab4, tab5
}

extension Notification.Name {
    static let vermiCommand = Notification.Name("VermiCommand")
}

private func postCommand(_ cmd: VermiCommand) {
    NotificationCenter.default.post(name: .vermiCommand, object: cmd.rawValue)
}

@main
struct RedisClientApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .frame(minWidth: 1000, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1400, height: 900)
        .commands { VermiCommands() }

        Settings {
            SettingsView()
        }
    }
}

/// Menu-bar commands. Each mirrors a keyboard shortcut so it is discoverable.
struct VermiCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Connection…") { postCommand(.newConnection) }
                .keyboardShortcut("n", modifiers: [.command])
            Button("New Tab") { postCommand(.newConnection) }
                .keyboardShortcut("t", modifiers: [.command])
            Divider()
            Button("Close Tab") { postCommand(.closeTab) }
                .keyboardShortcut("w", modifiers: [.command])
        }

        CommandMenu("Go") {
            Button("Keys") { postCommand(.tab1) }.keyboardShortcut("1", modifiers: [.command])
            Button("Console") { postCommand(.tab2) }.keyboardShortcut("2", modifiers: [.command])
            Button("Pub/Sub") { postCommand(.tab3) }.keyboardShortcut("3", modifiers: [.command])
            Button("Monitoring") { postCommand(.tab4) }.keyboardShortcut("4", modifiers: [.command])
            Button("Analysis") { postCommand(.tab5) }.keyboardShortcut("5", modifiers: [.command])
            Divider()
            Button("Find in Keys") { postCommand(.focusSearch) }.keyboardShortcut("f", modifiers: [.command])
            Button("Refresh Keys") { postCommand(.refresh) }.keyboardShortcut("r", modifiers: [.command])
        }
    }
}
