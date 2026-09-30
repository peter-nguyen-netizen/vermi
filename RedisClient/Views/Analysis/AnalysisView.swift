import SwiftUI

/// Thin wrapper: resolves the per-tab view model and injects it so the content
/// (which observes it via @ObservedObject) survives tab switches.
struct AnalysisView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if let vm = appState.activeAnalysisViewModel {
            AnalysisContent(viewModel: vm)
                .environmentObject(appState)
        }
    }
}

struct AnalysisContent: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var viewModel: AnalysisViewModel
    @AppStorage("analysisSampleSize") private var sampleLimit = 1000

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: Theme.spacing.lg) {
                Text("Memory Analysis")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.colors.textSecondary)
                    .textCase(.uppercase)

                Picker("", selection: $sampleLimit) {
                    Text("Sample 500").tag(500)
                    Text("Sample 1,000").tag(1000)
                    Text("Sample 5,000").tag(5000)
                }
                .pickerStyle(.menu)
                .frame(width: 130)

                Button {
                    Task { await viewModel.run(limit: sampleLimit) }
                } label: {
                    HStack(spacing: Theme.spacing.sm) {
                        if viewModel.isRunning { ProgressView().scaleEffect(0.6) }
                        Image(systemName: "chart.bar.fill").font(.system(size: 10))
                        Text(viewModel.isRunning ? "Scanning \(viewModel.scanned)…" : "Analyze")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(viewModel.isRunning)

                Spacer()
                if viewModel.didRun {
                    Text("sampled \(viewModel.scanned) of ~\(viewModel.totalKeys.formatted())")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(Theme.colors.textTertiary)
                }
            }
            .padding(.horizontal, Theme.spacing.xl)
            .padding(.vertical, Theme.spacing.md)
            .background(Theme.colors.background)

            Rectangle().fill(Theme.colors.border).frame(height: 0.5)

            if let error = viewModel.errorMessage, !error.isEmpty, !viewModel.isRunning {
                VStack(spacing: Theme.spacing.md) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 28)).foregroundColor(Theme.colors.error)
                    Text(error)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(Theme.colors.text)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                    Button {
                        Task { await viewModel.run(limit: sampleLimit) }
                    } label: {
                        HStack(spacing: Theme.spacing.sm) {
                            Image(systemName: "arrow.clockwise").font(.system(size: 10))
                            Text("Retry")
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding(Theme.spacing.xl)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !viewModel.didRun {
                VStack(spacing: Theme.spacing.md) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 28)).foregroundColor(Theme.colors.textTertiary).opacity(0.5)
                    Text("Run an analysis to find big keys and memory breakdown")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(Theme.colors.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.spacing.xxl) {
                        breakdown("By Type", viewModel.byType)
                        breakdown("By Namespace", viewModel.byNamespace)
                        topKeysSection
                    }
                    .padding(Theme.spacing.xl)
                }
            }
        }
        .background(Theme.colors.background)
        .onAppear { if let c = appState.activeClient { viewModel.setClient(c) } }
    }

    @ViewBuilder
    private func breakdown(_ title: String, _ groups: [GroupStat]) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing.md) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.colors.textSecondary).textCase(.uppercase)
            let maxSize = groups.first?.totalSize ?? 1
            VStack(spacing: 2) {
                ForEach(groups.prefix(8)) { g in
                    HStack(spacing: Theme.spacing.md) {
                        Text(g.name)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(Theme.colors.text)
                            .lineLimit(1).frame(width: 160, alignment: .leading)
                            .textSelection(.enabled)
                            .help(g.name)
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Theme.colors.primary.opacity(0.7))
                                .frame(width: max(4, geo.size.width * CGFloat(g.totalSize) / CGFloat(max(maxSize, 1))))
                        }
                        .frame(height: 12)
                        Text("\(formatBytes(g.totalSize)) · \(g.count)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Theme.colors.textTertiary)
                            .frame(width: 130, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var topKeysSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.md) {
            Text("Biggest Keys")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.colors.textSecondary).textCase(.uppercase)
            VStack(spacing: 0) {
                ForEach(Array(viewModel.topKeys.enumerated()), id: \.element.id) { i, s in
                    TopKeyRow(stat: s, even: i.isMultiple(of: 2),
                              sizeText: formatBytes(s.size),
                              onOpen: { openKey(s.key) })
                }
            }
            .overlay(RoundedRectangle(cornerRadius: Theme.sizes.smallCornerRadius).stroke(Theme.colors.border, lineWidth: 1))
            .cornerRadius(Theme.sizes.smallCornerRadius)
        }
    }

    /// Jump to the Keys tab and load this key's details.
    private func openKey(_ key: String) {
        appState.setMainTab(.keyBrowser)
        if let kvm = appState.activeKeyBrowserViewModel {
            Task { await kvm.loadKeyDetails(key) }
        }
    }

    private func formatBytes(_ size: Int) -> String {
        let mb = Double(size) / (1024 * 1024)
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        let kb = Double(size) / 1024
        if kb >= 1 { return String(format: "%.0f KB", kb) }
        return "\(size) B"
    }
}

/// One "Biggest Keys" row. The whole row is clickable (opens the key in the
/// Keys tab); a trailing arrow signals it. Copy stays a separate button.
private struct TopKeyRow: View {
    let stat: KeyStat
    let even: Bool
    let sizeText: String
    let onOpen: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: Theme.spacing.md) {
            TypeBadge(type: stat.type == "ReJSON-RL" ? "json" : stat.type)
            Text(stat.key)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Theme.colors.text)
                .lineLimit(1).truncationMode(.middle)
            CopyButton(value: stat.key)
            Spacer(minLength: Theme.spacing.md)
            Text(sizeText)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.colors.textSecondary)
            Image(systemName: "arrow.right.circle\(isHovering ? ".fill" : "")")
                .font(.system(size: 12))
                .foregroundColor(isHovering ? Theme.colors.primary : Theme.colors.textTertiary)
        }
        .padding(.horizontal, Theme.spacing.md)
        .padding(.vertical, 5)
        .background(isHovering ? Theme.colors.surfaceHover
                    : (even ? Theme.colors.surface : Theme.colors.surfaceActive))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { onOpen() }
        .handCursor()
        .help("Open \(stat.key) in the key browser")
    }
}
