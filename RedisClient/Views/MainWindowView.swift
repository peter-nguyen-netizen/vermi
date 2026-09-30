import SwiftUI

struct MainWindowView: View {
    @StateObject private var appState = AppState()
    @State private var showConnectionSheet = false
    @AppStorage("appearanceMode") private var appearanceRaw = AppearanceMode.system.rawValue
    @AppStorage("accentTheme") private var accentRaw = AccentTheme.vermilion.rawValue

    private var appearance: Binding<AppearanceMode> {
        Binding(
            get: { AppearanceMode(rawValue: appearanceRaw) ?? .system },
            set: { appearanceRaw = $0.rawValue }
        )
    }

    var body: some View {
        ZStack {
            GradientBackground()

            Group {
                if appState.openConnections.isEmpty {
                    EmptyStateView(showConnectionSheet: $showConnectionSheet, appearance: appearance)
                        .environmentObject(appState)
                } else {
                    VStack(spacing: 0) {
                        TopBar(showConnectionSheet: $showConnectionSheet, appearance: appearance)
                            .environmentObject(appState)

                        if let activeConnection = appState.activeConnection {
                            DetailPane(connection: activeConnection)
                                .environmentObject(appState)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            }
            .edgesIgnoringSafeArea(.top)

            if let name = appState.connectingName {
                ConnectingOverlay(name: name)
            }

            ToastOverlay()
                .allowsHitTesting(true)
        }
        // Rebuild the UI subtree when the accent theme changes so every view
        // re-reads Theme.colors. appState (owned above) is preserved.
        .id(accentRaw)
        .sheet(isPresented: $showConnectionSheet) {
            ConnectionDetailsView()
                .environmentObject(appState)
        }
        .sheet(item: $appState.editingConnection) { conn in
            ConnectionDetailsView(editing: conn)
                .environmentObject(appState)
        }
        .onChange(of: appState.errorMessage) { msg in
            if let msg = msg, !msg.isEmpty {
                ToastCenter.shared.error(msg)
                appState.errorMessage = nil
            }
        }
        .preferredColorScheme(appearance.wrappedValue.colorScheme)
        // Menu-bar commands (RedisClientApp) post these; act on the active tab.
        .onReceive(NotificationCenter.default.publisher(for: .vermiCommand)) { note in
            guard let raw = note.object as? String,
                  let cmd = VermiCommand(rawValue: raw) else { return }
            handle(cmd)
        }
    }

    private func handle(_ cmd: VermiCommand) {
        switch cmd {
        case .newConnection:
            showConnectionSheet = true
        case .closeTab:
            if let id = appState.activeTabId {
                Task { await appState.closeConnectionTab(id) }
            }
        case .focusSearch:
            guard let vm = appState.activeKeyBrowserViewModel else { return }
            appState.setMainTab(.keyBrowser)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 60_000_000)
                vm.focusSearchToken += 1
            }
        case .refresh:
            if let vm = appState.activeKeyBrowserViewModel {
                Task { await vm.scan(pattern: vm.searchText.isEmpty ? "*" : vm.searchText, reset: true) }
            }
        case .tab1, .tab2, .tab3, .tab4, .tab5:
            guard !appState.openConnections.isEmpty else { return }
            let tabs: [AppState.MainTab] = [.keyBrowser, .commandExecutor, .pubSub, .monitoring, .analysis]
            let idx = [VermiCommand.tab1, .tab2, .tab3, .tab4, .tab5].firstIndex(of: cmd) ?? 0
            appState.setMainTab(tabs[idx])
        }
    }
}

// MARK: - Top Bar (custom titlebar — traffic lights + connection tabs + function strip)

struct TopBar: View {
    @EnvironmentObject var appState: AppState
    @Binding var showConnectionSheet: Bool
    @Binding var appearance: AppearanceMode

    private var activeTab: AppState.ConnectionTab? {
        appState.openConnections.first(where: { $0.id == appState.activeTabId })
    }

    var body: some View {
        VStack(spacing: 0) {
            // Row 1: titlebar — [window-buttons] [tabs] [+] [spacer] [meta] [toggle]
            HStack(spacing: Theme.spacing.sm) {
                // Custom traffic light buttons (native ones hidden)
                TrafficLightButtons()
                    .padding(.leading, 10)
                    .padding(.trailing, 8)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.spacing.sm) {
                        ForEach(appState.openConnections) { tab in
                            ConnectionTabChip(tab: tab, isActive: tab.id == appState.activeTabId)
                                .environmentObject(appState)
                        }
                    }
                }

                Menu {
                    Button {
                        showConnectionSheet = true
                    } label: {
                        Label("New Connection…", systemImage: "plus")
                    }

                    if !appState.savedConnections.isEmpty {
                        let openIds = Set(appState.openConnections.map { $0.connection.id })
                        Divider()
                        Section("Open Saved") {
                            ForEach(appState.savedConnections) { conn in
                                Button {
                                    Task { await appState.openConnectionTab(conn) }
                                } label: {
                                    HStack {
                                        Text("\(conn.name)  —  \(conn.host):\(String(conn.port))")
                                        if openIds.contains(conn.id) {
                                            Circle()
                                                .fill(Theme.colors.success)
                                                .frame(width: 6, height: 6)
                                        }
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.colors.primary)
                        .frame(width: 30, height: 30)
                        .background(Theme.colors.surface)
                        .cornerRadius(Theme.sizes.smallCornerRadius)
                        .softShadowSmall()
                }
                .menuStyle(.borderlessButton).handCursor()
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Open or create a connection")

                Spacer()

                if let tab = activeTab {
                    HStack(spacing: Theme.spacing.md) {
                        StatusIndicator(isConnected: tab.connected)
                        Text("\(tab.connection.host):\(String(tab.connection.port))")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(Theme.colors.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let ms = tab.latencyMs {
                            Text("\(ms)ms")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(latencyColor(ms))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(latencyColor(ms).opacity(0.15))
                                .cornerRadius(8)
                                .softShadowSmall()
                        }
                    }
                    .task(id: tab.id) {
                        while !Task.isCancelled {
                            try? await Task.sleep(nanoseconds: 5_000_000_000)
                            if Task.isCancelled { break }
                            await appState.measureLatency(tab.id)
                        }
                    }
                }

                AppearanceToggle(mode: $appearance)
                    .padding(.trailing, Theme.spacing.md)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, Theme.spacing.md)
            .background(Theme.colors.sidebarBackground)

            Rectangle().fill(Theme.colors.border).frame(height: 0.5)

            // Row 2: function strip
            HStack(spacing: Theme.spacing.lg) {
                FunctionTabStrip(selected: activeTab?.selectedTab ?? .keyBrowser)
                    .environmentObject(appState)

                Spacer()
            }
            .padding(.horizontal, Theme.spacing.lg)
            .padding(.vertical, Theme.spacing.md)
            .background(Theme.colors.background)

            Rectangle().fill(Theme.colors.border).frame(height: 0.5)
        }
    }

    private func latencyColor(_ ms: Int) -> Color {
        if ms < 50 { return Theme.colors.success }
        if ms < 200 { return Theme.colors.warning }
        return Theme.colors.error
    }
}

// MARK: - Connection Tab Chip

struct ConnectionTabChip: View {
    @EnvironmentObject var appState: AppState
    let tab: AppState.ConnectionTab
    let isActive: Bool
    @State private var isHovering = false

    private var tabDisplayName: String {
        let sameConnection = appState.openConnections.filter { $0.connection.id == tab.connection.id }
        guard sameConnection.count > 1,
              let idx = sameConnection.firstIndex(where: { $0.id == tab.id }) else {
            return tab.connection.name
        }
        return "\(tab.connection.name) (\(idx + 1))"
    }

    var body: some View {
        HStack(spacing: Theme.spacing.md) {
            Circle()
                .fill(isActive ? Theme.colors.primary : Theme.colors.avatarColor(for: tab.connection.name))
                .frame(width: 8, height: 8)

            Text(tabDisplayName)
                .font(.system(size: 13, weight: isActive ? .bold : .semibold, design: .rounded))
                .foregroundColor(isActive ? Theme.colors.text : Theme.colors.textSecondary)
                .lineLimit(1)

            Button(action: {
                Task { await appState.closeConnectionTab(tab.id) }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.colors.textTertiary)
                    .frame(width: 16, height: 16)
                    .background(isHovering ? Theme.colors.surfaceActive : Color.clear)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain).handCursor()
            .help("Close tab (⌘W)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: Theme.sizes.smallCornerRadius)
                .fill(isActive ? Theme.colors.surface : (isHovering ? Theme.colors.muted : Color.clear))
        )
        .if(isActive) { $0.softShadowSmall() }
        .contentShape(Rectangle())
        .onTapGesture { appState.setActiveTab(tab.id) }
        .onHover { isHovering = $0 }
        .handCursor()
    }
}

// MARK: - Function Tab Strip (Keys / Console / Pub-Sub / Monitor)

struct FunctionTabStrip: View {
    @EnvironmentObject var appState: AppState
    let selected: AppState.MainTab

    var body: some View {
        HStack(spacing: Theme.spacing.sm) {
            ForEach([AppState.MainTab.keyBrowser, .commandExecutor, .pubSub, .monitoring, .analysis], id: \.self) { tab in
                FunctionTabButton(tab: tab, isSelected: selected == tab)
                    .environmentObject(appState)
            }
        }
        .padding(Theme.spacing.sm)
        .background(Theme.colors.muted)
        .cornerRadius(Theme.sizes.smallCornerRadius)
    }
}

struct FunctionTabButton: View {
    @EnvironmentObject var appState: AppState
    let tab: AppState.MainTab
    let isSelected: Bool
    @State private var isHovering = false

    private var icon: String {
        switch tab {
        case .keyBrowser: return "key.fill"
        case .commandExecutor: return "terminal.fill"
        case .pubSub: return "bubble.left.and.bubble.right.fill"
        case .monitoring: return "chart.line.uptrend.xyaxis"
        case .analysis: return "chart.bar.fill"
        }
    }

    private var title: String {
        switch tab {
        case .keyBrowser: return "Keys"
        case .commandExecutor: return "Console"
        case .pubSub: return "Pub/Sub"
        case .monitoring: return "Monitor"
        case .analysis: return "Analysis"
        }
    }

    private var shortcut: String {
        switch tab {
        case .keyBrowser: return "⌘1"
        case .commandExecutor: return "⌘2"
        case .pubSub: return "⌘3"
        case .monitoring: return "⌘4"
        case .analysis: return "⌘5"
        }
    }

    var body: some View {
        Button(action: { appState.setMainTab(tab) }) {
            HStack(spacing: Theme.spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 12, design: .rounded))
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundColor(isSelected ? Theme.colors.primary : Theme.colors.textSecondary)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Theme.colors.primary.opacity(0.12) : (isHovering ? Theme.colors.surfaceHover : Color.clear))
            )
            .if(isSelected) { $0.softShadowSmall() }
        }
        .buttonStyle(.plain).handCursor()
        .onHover { isHovering = $0 }
        .help("\(title) (\(shortcut))")
    }
}

// MARK: - Detail Pane

struct DetailPane: View {
    @EnvironmentObject var appState: AppState
    let connection: RedisConnection

    var body: some View {
        if let activeTab = appState.openConnections.first(where: { $0.id == appState.activeTabId }) {
            Group {
                switch activeTab.selectedTab {
                case .keyBrowser:
                    KeyBrowserView()
                        .environmentObject(appState)
                case .commandExecutor:
                    CommandExecutorView()
                        .environmentObject(appState)
                case .pubSub:
                    PubSubView()
                        .environmentObject(appState)
                case .monitoring:
                    MonitoringView()
                        .environmentObject(appState)
                case .analysis:
                    AnalysisView()
                        .environmentObject(appState)
                }
            }
            .background(Theme.colors.background)
        }
    }
}

// MARK: - Connecting Overlay

// MARK: - Custom Traffic Light Buttons

struct TrafficLightButtons: View {
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            TrafficDot(color: Color(red: 1.0, green: 0.373, blue: 0.341), hoverIcon: "xmark", isHovering: isHovering) {
                NSApp.keyWindow?.close()
            }
            TrafficDot(color: Color(red: 0.996, green: 0.737, blue: 0.180), hoverIcon: "minus", isHovering: isHovering) {
                NSApp.keyWindow?.miniaturize(nil)
            }
            TrafficDot(color: Color(red: 0.157, green: 0.784, blue: 0.251), hoverIcon: "arrow.up.left.and.arrow.down.right", isHovering: isHovering) {
                NSApp.keyWindow?.zoom(nil)
            }
        }
        .onHover { isHovering = $0 }
    }
}

struct TrafficDot: View {
    let color: Color
    let hoverIcon: String
    let isHovering: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 13, height: 13)
                if isHovering {
                    Image(systemName: hoverIcon)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.black.opacity(0.5))
                }
            }
        }
        .buttonStyle(.plain)
        .handCursor()
    }
}

/// Dimmed overlay with a spinner shown while a connection is being opened.
struct ConnectingOverlay: View {
    let name: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: Theme.spacing.lg) {
                ProgressView().scaleEffect(1.1)
                Text("Connecting to \(name)…")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.colors.text)
            }
            .padding(Theme.spacing.xxl)
            .background(Theme.colors.surface)
            .cornerRadius(Theme.sizes.cardCornerRadius)
            .softShadow()
        }
        .transition(.opacity)
    }
}
