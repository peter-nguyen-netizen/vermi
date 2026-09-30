import SwiftUI

/// Thin wrapper: resolves the per-tab view model so every open connection
/// shows its own server's metrics instead of the first tab's cached numbers.
struct MonitoringView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if let tabId = appState.activeTabId,
           let viewModel = appState.activeMonitoringViewModel {
            MonitoringContent(viewModel: viewModel)
                .environmentObject(appState)
                // Re-identify per connection tab so switching tabs runs
                // onDisappear/onAppear and moves the poll timer with it.
                .id(tabId)
        }
    }
}

struct MonitoringContent: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var viewModel: MonitoringViewModel

    var body: some View {
        VStack(spacing: 0) {
            MonitoringHeader()
                .environmentObject(appState)
                .environmentObject(viewModel)

            Rectangle()
                .fill(Theme.colors.border)
                .frame(height: 0.5)

            ScrollView {
                VStack(spacing: Theme.spacing.xl) {
                    // Metrics grid — adaptive, cards fill and wrap
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 160), spacing: Theme.spacing.md)],
                        spacing: Theme.spacing.md
                    ) {
                        MetricCard(title: "Uptime", value: viewModel.uptime,
                                   icon: "clock.fill", color: Theme.colors.info)
                        MetricCard(title: "Memory Used", value: viewModel.usedMemory,
                                   icon: "memorychip.fill", color: Theme.colors.warning)
                        MetricCard(title: "Max Memory", value: viewModel.maxMemory,
                                   icon: "memorychip", color: Theme.colors.error)
                        MetricCard(title: "Connected Clients", value: viewModel.connectedClients,
                                   icon: "person.fill", color: Theme.colors.success)
                        MetricCard(title: "Commands/sec", value: viewModel.commandsPerSecond,
                                   icon: "bolt.fill", color: Theme.colors.primary)
                    }

                    // Server Info
                    if let info = viewModel.serverInfo {
                        VStack(alignment: .leading, spacing: Theme.spacing.md) {
                            Text("Server Info")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(Theme.colors.textSecondary)
                                .textCase(.uppercase)

                            VStack(spacing: 0) {
                                InfoRow(title: "Redis Version", value: info.server["redis_version"] ?? "—")
                                InfoRow(title: "OS", value: info.server["os"] ?? "—")
                                InfoRow(title: "TCP Port", value: info.server["tcp_port"] ?? "—")
                                InfoRow(title: "Uptime Seconds", value: info.server["uptime_in_seconds"] ?? "—")
                                InfoRow(title: "Database Keys", value: dbKeyCount(info.keyspace["db0"]))
                            }
                            .background(Theme.colors.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.sizes.smallCornerRadius)
                                    .stroke(Theme.colors.borderSubtle, lineWidth: 0.5)
                            )
                        }
                    }

                    // Error
                    if let errorMsg = viewModel.errorMessage {
                        HStack(spacing: Theme.spacing.md) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 14, design: .rounded))
                                .foregroundColor(Theme.colors.error)
                            Text(errorMsg)
                                .font(.system(size: 13, design: .rounded))
                                .foregroundColor(Theme.colors.error)
                        }
                        .padding(Theme.spacing.md)
                        .background(Theme.colors.error.opacity(0.08))
                        .cornerRadius(Theme.sizes.smallCornerRadius)
                    }

                    Spacer()
                        .frame(height: Theme.spacing.xxl)
                }
                .padding(Theme.spacing.xl)
            }
            .background(Theme.colors.background)
        }
        .onAppear {
            // Keep this tab's last numbers on screen; the immediate first poll
            // of startMonitoring() refreshes them without a skeleton flash.
            if let client = appState.activeClient { viewModel.setClient(client) }
            viewModel.startMonitoring()
        }
        .onDisappear {
            viewModel.stopMonitoring()
        }
        .onChange(of: viewModel.errorMessage) { msg in
            if let msg = msg, !msg.isEmpty { ToastCenter.shared.error(msg) }
        }
    }

    /// keyspace value looks like "keys=42,expires=0,avg_ttl=0" — show just 42.
    private func dbKeyCount(_ raw: String?) -> String {
        guard let raw = raw else { return "—" }
        if let part = raw.split(separator: ",").first(where: { $0.hasPrefix("keys=") }) {
            return String(part.dropFirst("keys=".count))
        }
        return "—"
    }
}

// MARK: - Monitoring Header

struct MonitoringHeader: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var viewModel: MonitoringViewModel

    var body: some View {
        HStack(spacing: Theme.spacing.md) {
            Text("Monitoring")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.colors.textSecondary)
                .textCase(.uppercase)

            Spacer()

            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(0.7)
            }

            Badge(text: "every \(Int(viewModel.refreshInterval))s", color: Theme.colors.textSecondary)

            Menu {
                Picker("Refresh Interval", selection: Binding(
                    get: { viewModel.refreshInterval },
                    set: { viewModel.setRefreshInterval($0) }
                )) {
                    Text("1 second").tag(TimeInterval(1))
                    Text("2 seconds").tag(TimeInterval(2))
                    Text("5 seconds").tag(TimeInterval(5))
                    Text("10 seconds").tag(TimeInterval(10))
                    Text("30 seconds").tag(TimeInterval(30))
                }
                Divider()
                Button("Export INFO to clipboard") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(viewModel.rawInfoString, forType: .string)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.colors.textSecondary)
                    .frame(width: 20, height: 20)
                    .background(Theme.colors.muted)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain).handCursor()
            .menuStyle(.borderlessButton).handCursor()
            .fixedSize()
            .help("Refresh interval · Export INFO")
        }
        .padding(.horizontal, Theme.spacing.xl)
        .padding(.vertical, Theme.spacing.md)
        .background(Theme.colors.background)
    }
}

// MARK: - Metric Card

struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.lg) {
            HStack(spacing: Theme.spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(color.opacity(0.14))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(color)
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.colors.textSecondary)
                    .textCase(.uppercase)
                    .lineLimit(1)
                Spacer()
            }

            Text(value.isEmpty ? "—————" : value)
                .font(.system(size: 21, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.colors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .textSelection(.enabled)
                .redacted(reason: value.isEmpty ? .placeholder : [])
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.spacing.xl)
        .background(Theme.colors.surface)
        .cornerRadius(Theme.sizes.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.sizes.cardCornerRadius)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 1)
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let title: String
    let value: String
    @State private var isHovering = false

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(Theme.colors.textSecondary)
                .frame(minWidth: 120, alignment: .leading)

            Text(value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(Theme.colors.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            if isHovering && !value.isEmpty && value != "—" {
                CopyButton(value: value, help: "Copy \(title)")
            }
        }
        .padding(.horizontal, Theme.spacing.lg)
        .padding(.vertical, Theme.spacing.md)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }

        Rectangle()
            .fill(Theme.colors.borderSubtle)
            .frame(height: 0.5)
            .edgesIgnoringSafeArea(.horizontal)
    }
}
