import SwiftUI

struct KeyBrowserView: View {
    @EnvironmentObject var appState: AppState
    @State private var showDeleteConfirm = false
    @State private var keyToDelete = ""
    /// List pane width as a fraction of the total: default 30%, clamp 20%–50%
    /// (so the value pane stays 50%–80%).
    @State private var listFraction: CGFloat = 0.30

    private let minFraction: CGFloat = 0.20
    private let maxFraction: CGFloat = 0.50

    private var viewModel: KeyBrowserViewModel {
        appState.activeKeyBrowserViewModel ?? KeyBrowserViewModel()
    }

    var body: some View {
        GeometryReader { geo in
            let listWidth = Binding<CGFloat>(
                get: { geo.size.width * listFraction },
                set: { listFraction = min(max($0 / geo.size.width, minFraction), maxFraction) }
            )

            HStack(spacing: 0) {
                // Key list pane
                VStack(spacing: 0) {
                    KeyBrowserHeader()
                        .environmentObject(appState)
                        .environmentObject(viewModel)

                    KeyListPane()
                        .environmentObject(appState)
                        .environmentObject(viewModel)
                }
                .frame(width: geo.size.width * listFraction)
                .background(Theme.colors.background)

                HResizeHandle(width: listWidth, minWidth: 0, maxWidth: geo.size.width)

                // Detail pane
                KeyDetailPane()
                    .environmentObject(appState)
                    .environmentObject(viewModel)
                    .frame(maxWidth: .infinity)
            }
            // Keyboard navigation for the key list (↑/↓ move + open selection)
            .background {
                Group {
                    Button("") { moveSelection(1) }.keyboardShortcut(.downArrow, modifiers: [])
                    Button("") { moveSelection(-1) }.keyboardShortcut(.upArrow, modifiers: [])
                }
                .opacity(0)
                .allowsHitTesting(false)
            }
        }
        .onAppear {
            if let client = appState.activeClient {
                viewModel.setClient(client)
                // Only load on the very first visit — returning to the Keys tab
                // keeps the existing search/results/selection.
                if !viewModel.didInitialLoad {
                    Task {
                        await viewModel.scan(reset: true)
                    }
                }
            }
        }
    }

    /// Move the selection up/down the key list and open it.
    private func moveSelection(_ delta: Int) {
        let ks = viewModel.keys
        guard !ks.isEmpty else { return }
        let current = viewModel.selectedKey.flatMap { ks.firstIndex(of: $0) } ?? -1
        let next = min(max(current + delta, 0), ks.count - 1)
        guard next != current else { return }
        Task { await viewModel.loadKeyDetails(ks[next]) }
    }
}

// MARK: - Header

struct KeyBrowserHeader: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var viewModel: KeyBrowserViewModel
    @AppStorage("compactKeyList") private var compact = false
    @AppStorage("keyTreeMode") private var treeMode = false
    @FocusState private var searchFocused: Bool
    @State private var showAddKey = false

    var body: some View {
        VStack(spacing: Theme.spacing.md) {
            // Search bar — auto-detects glob pattern vs. substring
            HStack(spacing: Theme.spacing.md) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(Theme.colors.textTertiary)

                TextField("Search keys (supports * ? [ ] patterns)", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, design: .monospaced))
                    .focused($searchFocused)
                    .onSubmit { performSearch() }

                if !viewModel.searchText.isEmpty {
                    Button(action: {
                        viewModel.searchText = ""
                        Task { await viewModel.scan(pattern: "*", reset: true) }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(Theme.colors.textTertiary)
                    }
                    .buttonStyle(.plain).handCursor()
                }
            }
            .padding(.horizontal, Theme.spacing.md)
            .frame(height: Theme.sizes.buttonHeight)
            .background(Theme.colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.sizes.smallCornerRadius)
                    .stroke(Theme.colors.border, lineWidth: 1)
            )
            .cornerRadius(Theme.sizes.smallCornerRadius)

            // Recent search patterns: 2 most recent as chips + History menu
            if !viewModel.savedPatterns.isEmpty {
                HStack(spacing: Theme.spacing.sm) {
                    ForEach(viewModel.savedPatterns.prefix(2), id: \.self) { pattern in
                        HStack(spacing: 4) {
                            Text(pattern)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button(action: { viewModel.removeSavedPattern(pattern) }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 7, weight: .bold))
                            }
                            .buttonStyle(.plain).handCursor()
                            .help("Remove saved pattern")
                        }
                        .foregroundColor(Theme.colors.textSecondary)
                        .padding(.horizontal, Theme.spacing.md)
                        .padding(.vertical, 3)
                        .background(Theme.colors.muted)
                        .cornerRadius(8)
                        .contentShape(Rectangle())
                        .onTapGesture { runPattern(pattern) }
                        .handCursor()
                    }

                    Menu {
                        Section("Recent Searches") {
                            ForEach(viewModel.savedPatterns, id: \.self) { pattern in
                                Button(pattern) { runPattern(pattern) }
                            }
                        }
                        Divider()
                        Button("Clear History", role: .destructive) {
                            for p in viewModel.savedPatterns { viewModel.removeSavedPattern(p) }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 9))
                            Text("History")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                        }
                        .foregroundColor(Theme.colors.textSecondary)
                        .padding(.horizontal, Theme.spacing.md)
                        .padding(.vertical, 3)
                        .background(Theme.colors.muted)
                        .cornerRadius(8)
                    }
                    .menuStyle(.borderlessButton).handCursor()
                    .menuIndicator(.hidden)
                    .fixedSize()

                    Spacer(minLength: 0)
                }
            }

            // Key count & scan progress
            HStack(spacing: Theme.spacing.md) {
                Text(countLabel)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(Theme.colors.textTertiary)

                Button {
                    Task { await viewModel.scan(pattern: viewModel.searchText.isEmpty ? "*" : viewModel.searchText, reset: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.colors.textTertiary)
                }
                .buttonStyle(.plain).handCursor()
                .help("Reload keys")

                Button { compact.toggle() } label: {
                    Image(systemName: compact ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.colors.textTertiary)
                }
                .buttonStyle(.plain).handCursor()
                .help(compact ? "Comfortable rows" : "Compact rows")

                Button { treeMode.toggle() } label: {
                    Image(systemName: treeMode ? "list.bullet" : "list.bullet.indent")
                        .font(.system(size: 11))
                        .foregroundColor(treeMode ? Theme.colors.primary : Theme.colors.textTertiary)
                }
                .buttonStyle(.plain).handCursor()
                .help(treeMode ? "Flat list" : "Tree view")

                Button { showAddKey = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.colors.textTertiary)
                }
                .buttonStyle(.plain).handCursor()
                .help("Add key")

                Button { viewModel.toggleSelectionMode() } label: {
                    Image(systemName: viewModel.selectionMode ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.system(size: 11))
                        .foregroundColor(viewModel.selectionMode ? Theme.colors.primary : Theme.colors.textTertiary)
                }
                .buttonStyle(.plain).handCursor()
                .help("Select multiple")

                Spacer()

                if viewModel.hasMore {
                    Button(action: {
                        Task {
                            await viewModel.scan(
                                pattern: viewModel.searchText.isEmpty ? "*" : viewModel.searchText
                            )
                        }
                    }) {
                        HStack(spacing: 2) {
                            Text("Load more")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, design: .rounded))
                        }
                        .foregroundColor(Theme.colors.primary)
                    }
                    .buttonStyle(.plain).handCursor()
                } else {
                    Text("Scan complete")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(Theme.colors.success)
                }
            }
        }
        .padding(Theme.spacing.lg)
        .background(Theme.colors.background)
        // ⌘F focus request (token bumped by the app-level shortcut handler)
        .onChange(of: viewModel.focusSearchToken) { _ in searchFocused = true }
        .onAppear {
            if viewModel.focusSearchToken > 0 { searchFocused = true }
        }
        .sheet(isPresented: $showAddKey) {
            AddKeySheet().environmentObject(viewModel)
        }

        Rectangle()
            .fill(Theme.colors.borderSubtle)
            .frame(height: 0.5)
    }

    /// "12 shown · ~10,000 total" (searching) or "12 keys · ~10,000 total" (browse).
    private var countLabel: String {
        let shown = viewModel.keys.count
        let noun = viewModel.searchText.isEmpty ? "keys" : "matched"
        var label = "\(shown) \(noun)"
        if viewModel.totalKeys > 0 {
            label += " · ~\(viewModel.totalKeys.formatted()) total"
        }
        return label
    }

    private func runPattern(_ pattern: String) {
        viewModel.searchText = pattern
        Task { await viewModel.scan(pattern: pattern, reset: true) }
    }

    private func performSearch() {
        let term = viewModel.searchText.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else {
            // Empty search → back to default first-page browse
            Task { await viewModel.scan(pattern: "*", reset: true) }
            return
        }

        // Auto-detect: glob metacharacters → use the pattern verbatim;
        // otherwise treat as a substring match (`*term*`), which also finds
        // an exact key. No manual mode switch needed.
        let hasGlob = term.contains(where: { "*?[]".contains($0) })
        let pattern = hasGlob ? term : "*\(term)*"
        viewModel.savePattern(pattern)
        Task { await viewModel.scan(pattern: pattern, reset: true) }
    }
}

// MARK: - Key List Pane

struct KeyListPane: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var viewModel: KeyBrowserViewModel
    @AppStorage("keyTreeMode") private var treeMode = false

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading && viewModel.keys.isEmpty {
                // Skeleton rows while the first page loads (steadier than a spinner)
                VStack(spacing: 0) {
                    ForEach(0..<12, id: \.self) { i in
                        SkeletonRow()
                            .background(i.isMultiple(of: 2) ? Theme.colors.surface : Theme.colors.surfaceActive)
                    }
                    Spacer()
                }
            } else if let error = viewModel.errorMessage, !error.isEmpty {
                // Distinct error state — red, with a warning icon and the message.
                VStack(spacing: Theme.spacing.lg) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 23, design: .rounded))
                        .foregroundColor(Theme.colors.error)
                    Text(error)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(Theme.colors.text)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                    Button {
                        Task { await viewModel.scan(pattern: viewModel.searchText.isEmpty ? "*" : viewModel.searchText, reset: true) }
                    } label: {
                        HStack(spacing: Theme.spacing.sm) {
                            Image(systemName: "arrow.clockwise").font(.system(size: 10))
                            Text("Retry")
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding(Theme.spacing.xl)
                .frame(maxHeight: .infinity)
            } else if viewModel.keys.isEmpty {
                VStack(spacing: Theme.spacing.lg) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 23, design: .rounded))
                        .foregroundColor(Theme.colors.textTertiary)
                        .opacity(0.5)
                    Text("No keys found")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(Theme.colors.textTertiary)
                        .multilineTextAlignment(.center)
                    Button {
                        Task { await viewModel.scan(pattern: viewModel.searchText.isEmpty ? "*" : viewModel.searchText, reset: true) }
                    } label: {
                        HStack(spacing: Theme.spacing.sm) {
                            Image(systemName: "arrow.clockwise").font(.system(size: 10))
                            Text("Reload")
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding(Theme.spacing.xl)
                .frame(maxHeight: .infinity)
            } else if treeMode {
                KeyTreePane()
                    .environmentObject(appState)
                    .environmentObject(viewModel)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(viewModel.keys.enumerated()), id: \.element) { index, key in
                            KeyListItem(key: key, index: index)
                                .environmentObject(appState)
                                .environmentObject(viewModel)
                        }
                        if viewModel.hasMore {
                            Color.clear
                                .frame(height: 1)
                                .onAppear {
                                    Task {
                                        await viewModel.scan(
                                            pattern: viewModel.searchText.isEmpty ? "*" : viewModel.searchText
                                        )
                                    }
                                }
                        }
                    }
                }
            }

            if viewModel.selectionMode {
                BulkActionBar().environmentObject(viewModel)
            }

            if viewModel.isLoading {
                HStack(spacing: Theme.spacing.sm) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Loading...")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(Theme.colors.textTertiary)
                }
                .padding(Theme.spacing.sm)
                .frame(maxWidth: .infinity)
                .background(Theme.colors.surface)
                // Top border only (the old centered overlay drew a line across the text)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Theme.colors.borderSubtle)
                        .frame(height: 0.5)
                }
            }
        }
    }
}

// MARK: - Bulk Action Bar

struct BulkActionBar: View {
    @EnvironmentObject var viewModel: KeyBrowserViewModel
    @State private var showDeleteConfirm = false
    @State private var showTTL = false
    @State private var ttlText = ""

    var body: some View {
        HStack(spacing: Theme.spacing.md) {
            Text("\(viewModel.selectedKeys.count) selected")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.colors.text)

            Button("All") { viewModel.selectAllVisible() }
                .buttonStyle(GhostButtonStyle())
            Button("None") { viewModel.clearSelection() }
                .buttonStyle(GhostButtonStyle())

            Spacer()

            Button { showTTL = true } label: {
                HStack(spacing: 4) { Image(systemName: "clock").font(.system(size: 10)); Text("TTL") }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(viewModel.selectedKeys.isEmpty)

            Button(role: .destructive) { showDeleteConfirm = true } label: {
                HStack(spacing: 4) { Image(systemName: "trash").font(.system(size: 10)); Text("Delete") }
            }
            .buttonStyle(DestructiveButtonStyle())
            .disabled(viewModel.selectedKeys.isEmpty)
        }
        .padding(.horizontal, Theme.spacing.lg)
        .padding(.vertical, Theme.spacing.md)
        .background(Theme.colors.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.colors.border).frame(height: 0.5)
        }
        .alert("Delete \(viewModel.selectedKeys.count) keys?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { Task { await viewModel.bulkDelete() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the selected keys. Cannot be undone.")
        }
        .alert("Set TTL on \(viewModel.selectedKeys.count) keys", isPresented: $showTTL) {
            TextField("Seconds", text: $ttlText)
            Button("Set") { if let s = Int(ttlText), s > 0 { Task { await viewModel.bulkSetTTL(seconds: s) } } }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Add Key Sheet

/// Create a new string key. (Structured types can be created via the Console.)
struct AddKeySheet: View {
    @EnvironmentObject var viewModel: KeyBrowserViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var value = ""
    @State private var ttl = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Key")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.colors.textSecondary)
                        .frame(width: 24, height: 24).background(Theme.colors.muted).cornerRadius(10)
                }
                .buttonStyle(.plain).handCursor()
            }
            .padding(Theme.spacing.xxl)

            SectionDivider().padding(.horizontal, Theme.spacing.xxl)

            VStack(alignment: .leading, spacing: Theme.spacing.xl) {
                FormField(label: "Key") {
                    TextField("my:key", text: $name).inputField().onSubmit(create)
                }
                FormField(label: "Value (string)") {
                    TextField("value", text: $value).inputField().onSubmit(create)
                }
                FormField(label: "TTL seconds (optional)") {
                    TextField("none", text: $ttl).inputField().onSubmit(create)
                }
                if ttlInvalid {
                    Text("TTL must be a whole number of seconds.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(Theme.colors.error)
                }
            }
            .padding(Theme.spacing.xxl)

            SectionDivider().padding(.horizontal, Theme.spacing.xxl)

            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(GhostButtonStyle())
                Spacer()
                Button("Create", action: create)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canCreate)
                    .keyboardShortcut(.return, modifiers: [.command])
            }
            .padding(Theme.spacing.xxl)
        }
        .frame(width: 420)
        .background(Theme.colors.surface)
    }

    private var ttlInvalid: Bool {
        !ttl.trimmingCharacters(in: .whitespaces).isEmpty && Int(ttl) == nil
    }

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !ttlInvalid
    }

    private func create() {
        guard canCreate else { return }
        Task { await viewModel.addStringKey(name, value: value, ttlSeconds: Int(ttl)) }
        dismiss()
    }
}

// MARK: - Key Tree (namespace grouping by ":")

struct KeyTreeNode: Identifiable {
    let id: String            // accumulated path (unique)
    let name: String          // this segment
    var fullKey: String?      // non-nil if an actual key ends here
    var children: [KeyTreeNode]
    var isFolder: Bool { !children.isEmpty }
}

enum KeyTree {
    /// Build a tree from flat keys, splitting on `delimiter`. Folders sort first,
    /// then leaves; alphabetical within each.
    static func build(_ keys: [String], delimiter: Character = ":") -> [KeyTreeNode] {
        final class Builder {
            var fullKey: String?
            var order: [String] = []
            var kids: [String: Builder] = [:]
            func child(_ name: String) -> Builder {
                if let b = kids[name] { return b }
                let b = Builder(); kids[name] = b; order.append(name); return b
            }
        }
        let root = Builder()
        for key in keys {
            let segments = key.split(separator: delimiter, omittingEmptySubsequences: false).map(String.init)
            var node = root
            for seg in segments { node = node.child(seg) }
            node.fullKey = key
        }
        func convert(_ b: Builder, prefix: String) -> [KeyTreeNode] {
            let nodes = b.order.map { name -> KeyTreeNode in
                let child = b.kids[name]!
                let path = prefix.isEmpty ? name : "\(prefix)\(delimiter)\(name)"
                return KeyTreeNode(id: path, name: name, fullKey: child.fullKey,
                                   children: convert(child, prefix: path))
            }
            return nodes.sorted { a, c in
                if a.isFolder != c.isFolder { return a.isFolder && !c.isFolder }
                return a.name.localizedStandardCompare(c.name) == .orderedAscending
            }
        }
        return convert(root, prefix: "")
    }
}

struct KeyTreePane: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var viewModel: KeyBrowserViewModel
    @State private var expanded: Set<String> = []

    private var tree: [KeyTreeNode] { KeyTree.build(viewModel.keys) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(tree) { node in
                    KeyTreeRow(node: node, depth: 0, expanded: $expanded)
                        .environmentObject(appState)
                        .environmentObject(viewModel)
                }
                if viewModel.hasMore {
                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            Task {
                                await viewModel.scan(
                                    pattern: viewModel.searchText.isEmpty ? "*" : viewModel.searchText
                                )
                            }
                        }
                }
            }
        }
        .onChange(of: viewModel.keys.count) { _ in seedExpansion() }
        .onAppear { seedExpansion() }
    }

    /// Auto-expand top-level folders so the namespace is visible on open.
    private func seedExpansion() {
        for node in tree where node.isFolder { expanded.insert(node.id) }
    }
}

struct KeyTreeRow: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var viewModel: KeyBrowserViewModel
    let node: KeyTreeNode
    let depth: Int
    @Binding var expanded: Set<String>
    @State private var isHovering = false

    private var isOpen: Bool { expanded.contains(node.id) }
    private var isSelected: Bool { node.fullKey != nil && viewModel.selectedKey == node.fullKey }

    private var leafCount: Int { countLeaves(node) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.spacing.sm) {
                // Indent + disclosure
                if node.isFolder {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .foregroundColor(isSelected ? .white : Theme.colors.textTertiary)
                        .frame(width: 12)
                } else {
                    Spacer().frame(width: 12)
                }

                // Selection checkbox for leaf keys in bulk mode
                if viewModel.selectionMode, let key = node.fullKey, !node.isFolder {
                    Image(systemName: viewModel.selectedKeys.contains(key) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12))
                        .foregroundColor(viewModel.selectedKeys.contains(key) ? Theme.colors.primary : Theme.colors.textTertiary)
                }

                Image(systemName: node.isFolder ? "folder.fill" : "key.fill")
                    .font(.system(size: 10))
                    .foregroundColor(isSelected ? .white : (node.isFolder ? Theme.colors.warning : Theme.colors.primary))

                Text(node.name)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(isSelected ? .white : Theme.colors.text)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: Theme.spacing.sm)

                if node.isFolder {
                    Text("\(leafCount)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(isSelected ? .white.opacity(0.7) : Theme.colors.textTertiary)
                } else if let key = node.fullKey, let t = viewModel.keyTypes[key] {
                    TypeBadge(type: t == "ReJSON-RL" ? "json" : t)
                }
            }
            .padding(.leading, CGFloat(depth) * 14 + Theme.spacing.md)
            .padding(.trailing, Theme.spacing.md)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Theme.colors.primary : (isHovering ? Theme.colors.surfaceHover : Color.clear))
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .onTapGesture {
                if node.isFolder {
                    if isOpen { expanded.remove(node.id) } else { expanded.insert(node.id) }
                } else if let key = node.fullKey {
                    if viewModel.selectionMode {
                        viewModel.toggleSelected(key)
                    } else {
                        Task { await viewModel.loadKeyDetails(key) }
                    }
                }
            }
            .handCursor()

            if node.isFolder && isOpen {
                ForEach(node.children) { child in
                    KeyTreeRow(node: child, depth: depth + 1, expanded: $expanded)
                        .environmentObject(appState)
                        .environmentObject(viewModel)
                }
            }
        }
    }

    private func countLeaves(_ n: KeyTreeNode) -> Int {
        if !n.isFolder { return 1 }
        return n.children.reduce(0) { $0 + countLeaves($1) }
    }
}

// MARK: - Skeleton Row

/// Placeholder row shown while the first key page loads.
struct SkeletonRow: View {
    @State private var shimmer = false

    var body: some View {
        HStack(spacing: Theme.spacing.md) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Theme.colors.muted)
                .frame(width: 40, height: 14)
            RoundedRectangle(cornerRadius: 3)
                .fill(Theme.colors.muted)
                .frame(width: .random(in: 120...220), height: 12)
            Spacer()
        }
        .padding(.horizontal, Theme.spacing.md)
        .padding(.vertical, 8)
        .opacity(shimmer ? 0.45 : 0.9)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                shimmer = true
            }
        }
    }
}

// MARK: - Key List Item

/// Dense table-style row (Proxyman-like): index, status dot, monospaced key.
/// Selected row gets a solid accent fill with contrasting text.
struct KeyListItem: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var viewModel: KeyBrowserViewModel
    let key: String
    let index: Int
    @State private var isHovering = false
    @State private var showDeleteConfirm = false
    @AppStorage("compactKeyList") private var compact = false
    @AppStorage("confirmDeletes") private var confirmDeletes = true

    private var isSelected: Bool { viewModel.selectedKey == key }

    private var rowBackground: Color {
        if isSelected { return Theme.colors.primary.opacity(0.12) }
        if isHovering { return Theme.colors.surfaceHover }
        return index.isMultiple(of: 2) ? Theme.colors.surface : Theme.colors.surfaceActive
    }

    private var keyColor: Color { isSelected ? Theme.colors.primary : Theme.colors.text }

    private var type: String? { viewModel.keyTypes[key] }

    /// Whether size has been fetched yet (drives the dim placeholder).
    private var sizeLoaded: Bool { viewModel.keySizes[key] != nil }

    private var sizeText: String {
        let bytes = viewModel.keySizes[key] ?? 0
        let mb = Double(bytes) / (1024 * 1024)
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        let kb = Double(bytes) / 1024
        if kb >= 1 { return String(format: "%.0f KB", kb) }
        return "\(bytes) B"
    }

    var body: some View {
        HStack(spacing: Theme.spacing.md) {
            if viewModel.selectionMode {
                Image(systemName: viewModel.selectedKeys.contains(key) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundColor(viewModel.selectedKeys.contains(key) ? Theme.colors.primary : Theme.colors.textTertiary)
            }
            // Type badge (fixed slot so key names line up)
            Group {
                if let type = type {
                    TypeBadge(type: shortType(type))
                }
            }
            .frame(width: 52, alignment: .leading)

            Text(key)
                .font(.system(size: compact ? 12 : 13, design: .monospaced))
                .foregroundColor(keyColor)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: Theme.spacing.md)

            // Copy the key name on hover (hidden in selection mode).
            if isHovering && !viewModel.selectionMode {
                CopyButton(value: key, size: 10, help: "Copy key name")
            }

            // Size badge — shows a dim "0 B" placeholder immediately, updated
            // once the background loader resolves the real size.
            Text(sizeText)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(isSelected ? .white : Theme.colors.textSecondary)
                .opacity(sizeLoaded ? 1 : 0.4)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(isSelected ? Color.white.opacity(0.2) : Theme.colors.muted)
                .cornerRadius(8)
        }
        .padding(.horizontal, Theme.spacing.md)
        .padding(.vertical, compact ? 3 : 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle().fill(Theme.colors.primary).frame(width: 3)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        // Tap handling lives on the same view as the context menu so macOS
        // gesture arbitration doesn't swallow the right-click menu.
        .onTapGesture {
            if viewModel.selectionMode { viewModel.toggleSelected(key) }
            else { Task { await viewModel.loadKeyDetails(key) } }
        }
        .handCursor()
        .contextMenu {
            Button("Open") { Task { await viewModel.loadKeyDetails(key) } }
            Button("Copy key name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(key, forType: .string)
            }
            Divider()
            Button("Delete…", role: .destructive) {
                if confirmDeletes { showDeleteConfirm = true }
                else { Task { await viewModel.deleteKey(key) } }
            }
        }
        .alert("Delete \(key)?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { Task { await viewModel.deleteKey(key) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the key. This cannot be undone.")
        }
    }

    /// Compact type label for the badge (RedisJSON → "json").
    private func shortType(_ type: String) -> String {
        type == "ReJSON-RL" ? "json" : type
    }
}

// MARK: - Key Detail Pane

struct KeyDetailPane: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var viewModel: KeyBrowserViewModel
    @AppStorage("confirmDeletes") private var confirmDeletes = true
    @State private var showDeleteConfirm = false
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showTTL = false
    @State private var ttlText = ""

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.selectedKey == nil {
                VStack(spacing: Theme.spacing.lg) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 23, design: .rounded))
                        .foregroundColor(Theme.colors.textTertiary)
                        .opacity(0.5)
                    Text("Select a key")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(Theme.colors.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Header with key name + actions (copy, delete)
                HStack(spacing: Theme.spacing.md) {
                    Text(viewModel.selectedKey ?? "")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.colors.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)

                    Spacer()

                    CopyButton(value: viewModel.selectedKey ?? "", size: 13)

                    Button(action: {
                        renameText = viewModel.selectedKey ?? ""
                        showRename = true
                    }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(Theme.colors.textSecondary)
                    }
                    .buttonStyle(.plain).handCursor()
                    .help("Rename key")

                    Menu {
                        Button("Set TTL…") {
                            ttlText = viewModel.selectedKeyTTL > 0 ? "\(viewModel.selectedKeyTTL)" : ""
                            showTTL = true
                        }
                        if viewModel.selectedKeyTTL > 0 {
                            Button("Remove TTL (persist)") {
                                if let k = viewModel.selectedKey { Task { await viewModel.persistKey(k) } }
                            }
                        }
                    } label: {
                        Image(systemName: "clock")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(Theme.colors.textSecondary)
                    }
                    .menuStyle(.borderlessButton).handCursor()
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("TTL")

                    Button(action: {
                        if confirmDeletes { showDeleteConfirm = true }
                        else if let k = viewModel.selectedKey { Task { await viewModel.deleteKey(k) } }
                    }) {
                        HStack(spacing: Theme.spacing.sm) {
                            Image(systemName: "trash")
                                .font(.system(size: 12, design: .rounded))
                            Text("Delete")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                        }
                        .foregroundColor(Theme.colors.error)
                    }
                    .buttonStyle(.plain).handCursor()
                    .help("Delete key")
                }
                .padding(Theme.spacing.lg)

                Rectangle()
                    .fill(Theme.colors.borderSubtle)
                    .frame(height: 0.5)

                // Metadata (fixed)
                HStack(spacing: Theme.spacing.xl) {
                    MetadataBadge(label: "Type", value: viewModel.selectedKeyType, valueColor: Theme.colors.primary)
                    MetadataBadge(label: "Size", value: formatBytes(viewModel.selectedKeySize))
                    MetadataBadge(label: countLabel, value: countValue)
                    MetadataBadge(label: "TTL", value: formatTTL(viewModel.selectedKeyTTL))
                    Spacer()
                }
                .padding(.horizontal, Theme.spacing.lg)
                .padding(.top, Theme.spacing.lg)

                if let error = viewModel.errorMessage, !error.isEmpty {
                    HStack(spacing: Theme.spacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, design: .rounded))
                        Text(error)
                            .font(.system(size: 13, design: .rounded))
                        Spacer()
                    }
                    .foregroundColor(Theme.colors.error)
                    .padding(Theme.spacing.md)
                    .background(Theme.colors.error.opacity(0.1))
                    .cornerRadius(Theme.sizes.smallCornerRadius)
                    .padding(.horizontal, Theme.spacing.lg)
                    .padding(.top, Theme.spacing.md)
                }

                // Large value deferred → offer explicit load; else show the viewer.
                if let bytes = viewModel.deferredValueBytes {
                    LargeValuePrompt(bytes: bytes) {
                        Task { await viewModel.loadDeferredValue() }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(Theme.spacing.lg)
                } else {
                    // Value fills the remaining pane. `.id` recreates the editor
                    // per key so its @State (editText) re-initializes immediately.
                    TypedValueViewer(typedValue: viewModel.typedValue)
                        .environmentObject(viewModel)
                        .id(viewModel.selectedKey)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(Theme.spacing.lg)
                }
            }
        }
        .background(Theme.colors.background)
        .alert("Delete Key?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let key = viewModel.selectedKey {
                    Task {
                        await viewModel.deleteKey(key)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .alert("Rename Key", isPresented: $showRename) {
            TextField("New key name", text: $renameText)
            Button("Rename") {
                let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                guard let old = viewModel.selectedKey else { return }
                guard !trimmed.isEmpty else {
                    ToastCenter.shared.error("Key name required")
                    return
                }
                guard trimmed != old else { return }
                Task { await viewModel.renameKey(old, to: trimmed) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Set TTL (seconds)", isPresented: $showTTL) {
            TextField("Seconds", text: $ttlText)
            Button("Set") {
                guard let k = viewModel.selectedKey else { return }
                guard let secs = Int(ttlText), secs > 0 else {
                    ToastCenter.shared.error("Enter a positive whole number of seconds")
                    return
                }
                Task { await viewModel.setTTL(k, seconds: secs) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Expire the key after N seconds.")
        }
    }

    /// Secondary metric next to memory Size: element count for collections,
    /// byte length for strings.
    private var countLabel: String {
        switch viewModel.selectedKeyType {
        case "list": return "Items"
        case "hash": return "Fields"
        case "set", "zset": return "Members"
        case "string", "ReJSON-RL": return "Length"
        default: return "Count"
        }
    }

    private var countValue: String {
        switch viewModel.selectedKeyType {
        case "string", "ReJSON-RL":
            return formatBytes(viewModel.selectedKeyCount)   // byte length
        default:
            return "\(viewModel.selectedKeyCount)"           // element count
        }
    }

    private func formatBytes(_ size: Int) -> String {
        if size == 0 { return "0 B" }
        let units = ["B", "KB", "MB", "GB"]
        let bytes = Double(size)
        var unitIndex = 0
        var value = bytes

        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        return String(format: "%.1f %@", value, units[unitIndex])
    }

    private func formatTTL(_ ttl: Int) -> String {
        if ttl == -1 { return "∞" }
        if ttl == -2 { return "—" }
        return String(ttl) + "s"
    }
}

// MARK: - Typed Value Viewer

/// Value panel as a JSON editor: shows the full content (not a tree). String
/// keys are editable with Save/Format; structured types render as pretty,
/// syntax-highlighted JSON (read-only).
struct TypedValueViewer: View {
    let typedValue: TypedKeyValue
    @EnvironmentObject var viewModel: KeyBrowserViewModel

    @State private var editText: String = ""
    @State private var isEditing = false
    @State private var showCancelConfirm = false
    @State private var findTerm = ""
    @State private var currentMatch = 0
    @State private var structuredMode = true
    @AppStorage("textScale") private var textScale = 1.0

    // Cached JSON — computed once off main thread, read many times.
    @State private var cachedJSON: String = ""
    @State private var isFormattingJSON = false
    @State private var editIsJSON = false

    /// Base value font (14pt) scaled by the "Text size" preference.
    private var valueFontSize: CGFloat { 14 * CGFloat(textScale) }

    private var isStringKey: Bool {
        if case .string = typedValue { return true }
        return false
    }

    /// Hash/list/set/zset — support the per-element structured editor.
    private var isStructured: Bool {
        switch typedValue {
        case .hash, .list, .set, .zset: return true
        default: return false
        }
    }

    /// Find is available for any value (read-only JSON, string editor, and the
    /// structured table where it filters rows).
    private var canFind: Bool {
        if case .none = typedValue { return false }
        return true
    }

    /// The structured table editor is active (search filters rows there).
    private var tableMode: Bool { isStructured && structuredMode && !isEditing }

    /// Text the search runs over: the editor buffer while editing, else the value.
    private var searchSource: String { isEditing ? editText : displayText }

    /// Number of matching hash/list/set/zset rows for the current term.
    private var structuredMatchCount: Int {
        let f = findTerm.trimmingCharacters(in: .whitespaces)
        guard !f.isEmpty else { return 0 }
        func hit(_ a: String?, _ b: String) -> Bool {
            (a?.localizedCaseInsensitiveContains(f) ?? false) || b.localizedCaseInsensitiveContains(f)
        }
        switch typedValue {
        case .hash(let fs): return fs.filter { hit($0.field, $0.value) }.count
        case .list(let items): return items.filter { hit(nil, $0) }.count
        case .set(let ms): return ms.filter { hit(nil, $0) }.count
        case .zset(let ms): return ms.filter { hit(nil, $0.member) }.count
        default: return 0
        }
    }

    private var matchCount: Int {
        guard !findTerm.isEmpty else { return 0 }
        if tableMode { return structuredMatchCount }
        return searchSource.lowercased().components(separatedBy: findTerm.lowercased()).count - 1
    }

    /// Cycle the current match index, wrapping around.
    private func advanceMatch(_ delta: Int) {
        guard matchCount > 0 else { return }
        currentMatch = ((currentMatch + delta) % matchCount + matchCount) % matchCount
    }

    /// The 0-based line index that contains the Nth (0-based) match, if any.
    private func lineForMatch(_ n: Int) -> Int? {
        guard !findTerm.isEmpty else { return nil }
        let needle = findTerm.lowercased()
        var seen = 0
        for (idx, line) in displayText.components(separatedBy: "\n").enumerated() {
            let inLine = line.lowercased().components(separatedBy: needle).count - 1
            if inLine > 0 && n < seen + inLine { return idx }
            seen += inLine
        }
        return nil
    }

    /// canonicalText capped for rendering; huge values are truncated with a note.
    private var displayText: String {
        let full = canonicalText
        guard full.count > displayCharLimit else { return full }
        let prefix = String(full.prefix(displayCharLimit))
        let shownKB = displayCharLimit / 1024
        return prefix + "\n\n… (truncated — showing first \(shownKB) KB; use Copy for the full value)"
    }

    /// Pretty-printing / prettifying above this size is skipped (too slow).
    private let prettyLimit = 256 * 1024
    /// Rendered display is capped to this many characters to keep the UI snappy.
    private let displayCharLimit = 200_000

    /// Cached canonical text — populated asynchronously by `.task(id:)`.
    /// All read sites use this instead of recomputing every render.
    private var canonicalText: String { cachedJSON }

    /// Format JSON off main thread. Called via `.task(id:)` when value changes.
    private func formatCanonicalText() async {
        isFormattingJSON = true
        let value = typedValue
        let limit = prettyLimit
        let result: String = await Task.detached(priority: .userInitiated) {
            switch value {
            case .none:
                return ""
            case .string(let str):
                if str.utf8.count > limit { return str }
                return JSONFormatter.pretty(str) ?? str
            case .list(let items):
                return prettyPrintJSON(items)
            case .set(let members):
                return prettyPrintJSON(members.sorted())
            case .hash(let fields):
                return prettyPrintJSON(Dictionary(fields.map { ($0.field, $0.value) }, uniquingKeysWith: { a, _ in a }))
            case .zset(let members):
                return prettyPrintJSON(members.map { ["score": $0.score, "member": $0.member] as [String: Any] })
            }
        }.value
        if !Task.isCancelled {
            cachedJSON = result
            isFormattingJSON = false
        }
    }

    /// Instance wrapper for the free-function prettyPrint.
    private func prettyPrint(_ object: Any) -> String { prettyPrintJSON(object) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.md) {
            HStack(spacing: Theme.spacing.md) {
                Text("Value")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.colors.textTertiary)
                    .textCase(.uppercase)

                // Find in value — read-only JSON view and the string editor
                // (both highlight + scroll to match). Hidden for the structured
                // table editor where per-value search doesn't apply.
                if canFind {
                    HStack(spacing: Theme.spacing.sm) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.colors.textTertiary)
                        TextField("Find in value…", text: $findTerm)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 140)
                            .onChange(of: findTerm) { _ in currentMatch = 0 }
                            .onSubmit { advanceMatch(1) }
                        if !findTerm.isEmpty {
                            Text(tableMode ? "\(matchCount)" : (matchCount == 0 ? "0/0" : "\(currentMatch + 1)/\(matchCount)"))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(Theme.colors.textTertiary)
                            if !tableMode {
                                Button(action: { advanceMatch(-1) }) {
                                    Image(systemName: "chevron.up").font(.system(size: 10))
                                        .foregroundColor(Theme.colors.textTertiary)
                                }
                                .buttonStyle(.plain).handCursor().disabled(matchCount == 0).help("Previous match")
                                Button(action: { advanceMatch(1) }) {
                                    Image(systemName: "chevron.down").font(.system(size: 10))
                                        .foregroundColor(Theme.colors.textTertiary)
                                }
                                .buttonStyle(.plain).handCursor().disabled(matchCount == 0).help("Next match")
                            }
                            Button(action: { findTerm = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(Theme.colors.textTertiary)
                            }
                            .buttonStyle(.plain).handCursor().help("Clear")
                        }
                    }
                    .padding(.horizontal, Theme.spacing.md)
                    .padding(.vertical, 4)
                    .background(Theme.colors.muted)
                    .cornerRadius(Theme.sizes.smallCornerRadius)
                }

                Spacer()

                if isEditing {
                    if editIsJSON {
                        Button("Format") { editText = JSONFormatter.pretty(editText) ?? editText }
                            .buttonStyle(GhostButtonStyle())
                    }
                    Button("Cancel") {
                        if editText != cachedJSON { showCancelConfirm = true }
                        else { isEditing = false }
                    }
                    .buttonStyle(GhostButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    Button("Save") {
                        Task { await viewModel.saveStringValue(editText); isEditing = false }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.return, modifiers: [.command])
                } else {
                    if case .none = typedValue {} else {
                        CopyButton(value: cachedJSON, help: "Copy full value")
                    }
                    if isStringKey {
                        Button {
                            editText = cachedJSON
                            isEditing = true
                        } label: {
                            HStack(spacing: Theme.spacing.sm) {
                                Image(systemName: "pencil").font(.system(size: 10))
                                Text("Edit")
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    if isStructured {
                        Picker("", selection: $structuredMode) {
                            Text("Edit").tag(true)
                            Text("JSON").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 110)
                    }
                }
            }

            Group {
                if case .none = typedValue {
                    Text("No value")
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(Theme.colors.textTertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(Theme.spacing.lg)
                } else if isEditing {
                    // Editable buffer with find highlighting + scroll-to-match.
                    HighlightingTextEditor(
                        text: $editText,
                        highlight: findTerm,
                        activeMatch: currentMatch,
                        fontSize: valueFontSize
                    )
                    .padding(Theme.spacing.sm)
                } else if isStructured && structuredMode {
                    // Per-element editor for hash / list / set / zset
                    StructuredValueEditor(typedValue: typedValue, filter: findTerm)
                        .environmentObject(viewModel)
                } else if !findTerm.isEmpty {
                    // With an active find term, render line-by-line so we can
                    // scroll the current match into view via prev/next.
                    ScrollViewReader { proxy in
                        ScrollView(.vertical) {
                            let lines = displayText.components(separatedBy: "\n")
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                                    JSONHighlightedText(text: line, highlight: findTerm, fontSize: valueFontSize)
                                        .frame(maxWidth: .infinity, alignment: .topLeading)
                                        .id(idx)
                                }
                            }
                            .padding(Theme.spacing.md)
                        }
                        .onChange(of: currentMatch) { _ in
                            if let line = lineForMatch(currentMatch) {
                                withAnimation { proxy.scrollTo(line, anchor: .center) }
                            }
                        }
                    }
                } else {
                    // Read-only, syntax-highlighted full JSON — rendered directly
                    // from canonicalText (the current value), so it appears
                    // immediately on selection with no state-sync lag. Vertical
                    // scroll only (horizontal would center-align content).
                    ScrollView(.vertical) {
                        JSONHighlightedText(text: displayText, highlight: findTerm, fontSize: valueFontSize)
                            .padding(Theme.spacing.md)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.colors.codeBackground)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.sizes.smallCornerRadius)
                    .stroke(Theme.colors.border, lineWidth: 1)
            )
            // Loading overlay while a (possibly large) value is being fetched
            .overlay {
                if (viewModel.isLoadingValue || isFormattingJSON) && !isEditing {
                    ZStack {
                        Theme.colors.codeBackground.opacity(0.7)
                        VStack(spacing: Theme.spacing.md) {
                            ProgressView().scaleEffect(0.8)
                            Text("Loading value…")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundColor(Theme.colors.textSecondary)
                        }
                    }
                }
            }
            .cornerRadius(Theme.sizes.smallCornerRadius)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: viewModel.selectedKey) { _ in isEditing = false }
        // Async JSON formatting — runs once when value/mode changes, caches result.
        .task(id: "\(viewModel.selectedKey ?? "")_\(structuredMode)_\(typedValue == .none ? "0" : "1")") {
            await formatCanonicalText()
        }
        // Debounced isJSON check during editing (500ms pause).
        .task(id: editText) {
            guard isEditing else { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            let text = editText
            let result = await Task.detached(priority: .utility) {
                JSONFormatter.isJSON(text)
            }.value
            if !Task.isCancelled { editIsJSON = result }
        }
        .alert("Discard changes?", isPresented: $showCancelConfirm) {
            Button("Discard", role: .destructive) { isEditing = false }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Your edits to this value have not been saved.")
        }
    }

}

/// Nonisolated JSON pretty-printer — safe to call from detached tasks.
private func prettyPrintJSON(_ object: Any) -> String {
    guard JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
          let str = String(data: data, encoding: .utf8) else {
        return String(describing: object)
    }
    return str.replacingOccurrences(of: "\\/", with: "/")
}

// MARK: - Large value prompt

/// Shown instead of the value viewer when a value is too big to auto-load.
struct LargeValuePrompt: View {
    let bytes: Int
    let onLoad: () -> Void

    private var sizeText: String {
        let mb = Double(bytes) / (1024 * 1024)
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        return String(format: "%.0f KB", Double(bytes) / 1024)
    }

    var body: some View {
        VStack(spacing: Theme.spacing.lg) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 28))
                .foregroundColor(Theme.colors.textTertiary)
            VStack(spacing: Theme.spacing.sm) {
                Text("Large value — \(sizeText)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.colors.text)
                Text("Not loaded automatically to keep the app responsive.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(Theme.colors.textTertiary)
                    .multilineTextAlignment(.center)
            }
            Button(action: onLoad) {
                HStack(spacing: Theme.spacing.sm) {
                    Image(systemName: "arrow.down.circle").font(.system(size: 11))
                    Text("Load value")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.colors.codeBackground)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.sizes.smallCornerRadius)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
        .cornerRadius(Theme.sizes.smallCornerRadius)
    }
}

// MARK: - MetadataBadge component

struct MetadataBadge: View {
    let label: String
    let value: String
    var valueColor: Color = Theme.colors.text

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Theme.colors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.6)
            Text(value)
                .font(.system(size: 14, weight: .heavy, design: .monospaced))
                .foregroundColor(valueColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.colors.surface)
        .cornerRadius(Theme.sizes.smallCornerRadius)
        .softShadowSmall()
    }
}
