import SwiftUI

struct CommandExecutorView: View {
    @EnvironmentObject var appState: AppState

    // Per-tab view model so command input / history / result survive tab switches.
    private var viewModel: CommandExecutorViewModel {
        appState.activeCommandExecutorViewModel ?? CommandExecutorViewModel()
    }

    var body: some View {
        VStack(spacing: 0) {
            CommandInputPane()
                .environmentObject(appState)
                .environmentObject(viewModel)

            Rectangle()
                .fill(Theme.colors.border)
                .frame(height: 0.5)

            CommandResultPane()
                .environmentObject(appState)
                .environmentObject(viewModel)
        }
        .onChange(of: viewModel.errorMessage) { msg in
            if let msg = msg, !msg.isEmpty { ToastCenter.shared.error(msg) }
        }
    }
}

// MARK: - Command Input Pane

struct CommandInputPane: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var viewModel: CommandExecutorViewModel
    @AppStorage("textScale") private var textScale = 1.0
    @State private var selectedIndex = 0
    @State private var dismissed = false
    @State private var caret = 0
    @State private var editorHeight: CGFloat = 22
    /// Debounced key-name matches from the DB for the current argument.
    @State private var keyMatches: [String] = []

    /// A unified autocomplete row (command name, subcommand, or a DB key).
    struct Sugg: Identifiable {
        let id = UUID()
        let display: String    // shown in the list
        let detail: String     // summary / label
        let insert: String     // text that replaces the current token
    }

    // MARK: Token model (caret-aware)

    private var ns: NSString { viewModel.commandInput as NSString }
    private var caretClamped: Int { max(0, min(caret, ns.length)) }
    private var prefixText: String { ns.substring(to: caretClamped) }

    private var prefixTokens: [String] {
        prefixText.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init)
    }
    private var endsWithSpace: Bool {
        guard let last = prefixText.last else { return false }
        return last == " " || last == "\t" || last == "\n"
    }
    /// Argument index of the token under the caret (0 = command name).
    private var tokenIndex: Int {
        endsWithSpace ? prefixTokens.count : max(0, prefixTokens.count - 1)
    }
    /// Partial token currently being typed (empty right after a space).
    private var currentToken: String {
        endsWithSpace ? "" : (prefixTokens.last ?? "")
    }
    /// Command name = first token of the WHOLE input.
    private var commandName: String {
        viewModel.commandInput.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
            .first.map(String.init) ?? ""
    }

    /// The resolved syntax info for the current command (or container subcommand).
    private var syntaxHint: RedisCommandInfo? {
        let parts = viewModel.commandInput.split(separator: " ", maxSplits: 1)
        if parts.count == 2, RedisCommandCatalog.hasSubcommands(String(parts[0])) {
            let sub = parts[1].split(separator: " ").first.map(String.init) ?? ""
            let typed = (parts[0] + " " + sub).uppercased()
            if let exact = RedisCommandCatalog
                .subcommandsMatching(container: String(parts[0]), prefix: sub)
                .first(where: { $0.name.uppercased() == typed }) {
                return exact
            }
        }
        return RedisCommandCatalog.info(for: commandName)
    }

    /// Syntax tokens (for arg-position highlighting); [] if unknown.
    private var syntaxTokens: [String] {
        syntaxHint.map { $0.syntax.split(separator: " ").map(String.init) } ?? []
    }

    /// Whether the argument at the caret position expects a key name.
    private var currentArgIsKey: Bool {
        guard tokenIndex >= 1, tokenIndex < syntaxTokens.count else { return false }
        let word = syntaxTokens[tokenIndex].lowercased()
        return ["key", "src", "dst", "source", "destination", "dest", "newkey"].contains { word.contains($0) }
    }

    /// The key-suggestion query (nil when not in a key-argument position).
    private var keyQuery: String? {
        guard !dismissed, tokenIndex >= 1, currentArgIsKey else { return nil }
        // Not while typing a subcommand.
        if tokenIndex == 1, RedisCommandCatalog.hasSubcommands(commandName) { return nil }
        return currentToken
    }

    /// Unified suggestion list for the current caret position.
    private var suggestions: [Sugg] {
        guard !dismissed else { return [] }

        // Command-name phase.
        if tokenIndex == 0 {
            let matches = RedisCommandCatalog.matching(prefix: currentToken)
            if currentToken.isEmpty { return [] }
            if matches.count == 1 && matches[0].name == currentToken.uppercased() { return [] }
            return matches.prefix(8).map { Sugg(display: $0.name, detail: $0.summary, insert: $0.name + " ") }
        }

        // Subcommand phase.
        if tokenIndex == 1, RedisCommandCatalog.hasSubcommands(commandName) {
            let subs = RedisCommandCatalog.subcommandsMatching(container: commandName, prefix: currentToken)
            let typed = (commandName + " " + currentToken).uppercased()
            if subs.count == 1 && subs[0].name.uppercased() == typed { return [] }
            return subs.prefix(8).map { s in
                let sub = s.name.split(separator: " ").dropFirst().joined(separator: " ")
                return Sugg(display: s.name, detail: s.summary, insert: sub + " ")
            }
        }

        // Key-argument phase (matches fetched asynchronously).
        if keyQuery != nil {
            return keyMatches.prefix(10).map { Sugg(display: $0, detail: "key", insert: $0 + " ") }
        }
        return []
    }

    var body: some View {
        VStack(spacing: Theme.spacing.md) {
            // Action toolbar: star + history on the left, Execute on the right.
            HStack(spacing: Theme.spacing.sm) {
                Button(action: { viewModel.toggleFavorite() }) {
                    Image(systemName: viewModel.isCurrentFavorite ? "star.fill" : "star")
                        .font(.system(size: 12))
                        .foregroundColor(viewModel.isCurrentFavorite ? Theme.colors.warning : Theme.colors.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(Theme.colors.muted)
                        .cornerRadius(Theme.sizes.smallCornerRadius)
                }
                .buttonStyle(.plain).handCursor()
                .disabled(viewModel.commandInput.trimmingCharacters(in: .whitespaces).isEmpty)
                .help("Star command")

                Menu {
                    if !viewModel.favorites.isEmpty {
                        Section("Favorites") {
                            ForEach(viewModel.favorites, id: \.self) { cmd in
                                Button(cmd) { viewModel.commandInput = cmd }
                            }
                        }
                    }
                    if !viewModel.recentCommands.isEmpty {
                        Section("Recent") {
                            ForEach(viewModel.recentCommands, id: \.self) { cmd in
                                Button(cmd) { viewModel.commandInput = cmd }
                            }
                        }
                        Divider()
                        Button("Clear History", role: .destructive) { viewModel.clearHistory() }
                    }
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.colors.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(Theme.colors.muted)
                        .cornerRadius(Theme.sizes.smallCornerRadius)
                }
                .menuStyle(.borderlessButton).handCursor()
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(viewModel.favorites.isEmpty && viewModel.recentCommands.isEmpty)
                .help("History & favorites")

                Spacer()

                Button(action: execute) {
                    HStack(spacing: Theme.spacing.sm) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, design: .rounded))
                        Text("Execute")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(viewModel.isLoading)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Execute (⌘↵)")
            }

            // Command input — full width below the toolbar.
            CommandEditor(
                text: $viewModel.commandInput,
                caret: $caret,
                contentHeight: $editorHeight,
                fontSize: 14 * CGFloat(textScale),
                onMoveUp: moveUp,
                onMoveDown: moveDown,
                onAccept: acceptSuggestion,
                onCancel: dismissSuggestions,
                onSubmit: submit
            )
            .frame(height: min(max(editorHeight, Theme.sizes.buttonHeight), 140))
            .padding(.horizontal, Theme.spacing.sm)
            .background(Theme.colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.sizes.smallCornerRadius)
                    .stroke(Theme.colors.border, lineWidth: 1)
            )
            .cornerRadius(Theme.sizes.smallCornerRadius)
            .onChange(of: viewModel.commandInput) { _ in
                // Typing re-opens suggestions and resets the highlight
                dismissed = false
                selectedIndex = 0
            }
            // Fetch DB key suggestions (debounced) when the caret is on a key arg.
            .task(id: keyQuery) {
                guard let q = keyQuery else { keyMatches = []; return }
                try? await Task.sleep(nanoseconds: 150_000_000)
                if Task.isCancelled { return }
                keyMatches = await viewModel.keySuggestions(prefix: q)
            }

            // Autocomplete list (command / subcommand / key), else arg-aware hint
            if !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { idx, s in
                        Button(action: { complete(s) }) {
                            HStack(spacing: Theme.spacing.md) {
                                Text(s.display)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundColor(Theme.colors.primary)
                                    .frame(width: 150, alignment: .leading)
                                    .lineLimit(1).truncationMode(.middle)
                                Text(s.detail)
                                    .font(.system(size: 12, design: .rounded))
                                    .foregroundColor(Theme.colors.textSecondary)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, Theme.spacing.md)
                            .padding(.vertical, 5)
                            .background(idx == selectedIndex ? Theme.colors.primary.opacity(0.12) : Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(SuggestionRowStyle())
                    }

                    Text("↑↓ navigate · ⇥ complete · ⏎ run · ⇧⏎ newline · esc dismiss")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundColor(Theme.colors.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.spacing.md)
                        .padding(.top, 4)
                }
                .padding(.vertical, 4)
                .background(Theme.colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.sizes.smallCornerRadius)
                        .stroke(Theme.colors.border, lineWidth: 1)
                )
                .cornerRadius(Theme.sizes.smallCornerRadius)
            } else if let hint = syntaxHint {
                HStack(spacing: Theme.spacing.md) {
                    // Bold the argument the caret is currently on.
                    HStack(spacing: 4) {
                        ForEach(Array(syntaxTokens.enumerated()), id: \.offset) { i, tok in
                            Text(tok)
                                .font(.system(size: 12, weight: i == tokenIndex ? .bold : .regular, design: .monospaced))
                                .foregroundColor(i == tokenIndex ? Theme.colors.primary : Theme.colors.text)
                        }
                    }
                    Text("·")
                        .foregroundColor(Theme.colors.textTertiary)
                    Text(hint.summary)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(Theme.colors.textTertiary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Theme.spacing.md)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.colors.muted)
                .cornerRadius(Theme.sizes.smallCornerRadius)
            }

            if let errorMsg = viewModel.errorMessage, !errorMsg.isEmpty {
                HStack(spacing: Theme.spacing.md) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(Theme.colors.error)
                    Text(errorMsg)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(Theme.colors.error)
                        .lineLimit(1)
                    Spacer()
                    Button(action: { viewModel.errorMessage = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(Theme.colors.error)
                    }
                    .buttonStyle(.plain).handCursor()
                }
                .padding(Theme.spacing.md)
                .background(Theme.colors.error.opacity(0.08))
                .cornerRadius(Theme.sizes.smallCornerRadius)
            }
        }
        .padding(Theme.spacing.lg)
        .background(Theme.colors.background)
    }

    private func execute() {
        guard !viewModel.isLoading else { return }
        Task { await viewModel.executeCommand() }
    }

    /// Replace the token under the caret with the chosen suggestion.
    private func complete(_ s: Sugg) {
        let start = max(0, caretClamped - (currentToken as NSString).length)
        let range = NSRange(location: start, length: caretClamped - start)
        let newStr = ns.replacingCharacters(in: range, with: s.insert)
        viewModel.commandInput = newStr
        caret = start + (s.insert as NSString).length
        selectedIndex = 0
        // Leave `dismissed` false so the next argument's suggestions can appear.
    }

    // MARK: Keyboard handlers (driven by CommandEditor)

    private func moveDown() -> Bool {
        let list = suggestions
        guard !list.isEmpty else { return false }
        selectedIndex = min(selectedIndex + 1, list.count - 1)
        return true
    }

    private func moveUp() -> Bool {
        guard !suggestions.isEmpty else { return false }
        selectedIndex = max(selectedIndex - 1, 0)
        return true
    }

    /// Tab: accept the highlighted suggestion. Returns true if consumed.
    private func acceptSuggestion() -> Bool {
        let list = suggestions
        guard !list.isEmpty else { return false }
        let idx = min(max(selectedIndex, 0), list.count - 1)
        complete(list[idx])
        return true
    }

    /// Esc: dismiss suggestions. Returns true if there was something to dismiss.
    private func dismissSuggestions() -> Bool {
        guard !suggestions.isEmpty else { return false }
        dismissed = true
        return true
    }

    /// Enter: if the dropdown is open, accept the highlighted item; else run.
    private func submit() {
        if !suggestions.isEmpty {
            _ = acceptSuggestion()
        } else {
            execute()
        }
    }
}

/// Ghost-like row that highlights on hover, for the suggestions dropdown.
struct SuggestionRowStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(isHovering ? Theme.colors.surfaceHover : Color.clear)
            .onHover { isHovering = $0 }
    }
}

// MARK: - Command Result Pane

struct CommandResultPane: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var viewModel: CommandExecutorViewModel
    @State private var showClearHistoryConfirm = false
    @AppStorage("textScale") private var textScale = 1.0
    private var resultFontSize: CGFloat { 13 * CGFloat(textScale) }

    /// JSON rendering of the current result, if one is available.
    private var jsonText: String? { viewModel.resultAsJSON() }

    /// Text to display for the current result, honoring the Raw/JSON toggle.
    private var displayText: String {
        if viewModel.resultType == .json, !isError, let j = jsonText { return j }
        return viewModel.result
    }

    private var isError: Bool { viewModel.lastValue?.isError ?? false }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: Theme.spacing.lg) {
                Picker("", selection: $viewModel.resultType) {
                    Text("Raw").tag(CommandExecutorViewModel.ResultType.raw)
                    Text("JSON").tag(CommandExecutorViewModel.ResultType.json)
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
                .disabled(jsonText == nil)   // JSON only when the reply is representable

                Spacer()

                if viewModel.didRun && !viewModel.result.isEmpty {
                    CopyButton(value: displayText, size: 12, help: "Copy result")
                }

                Menu {
                    Button("Clear command history…", role: .destructive) {
                        showClearHistoryConfirm = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.colors.textSecondary)
                        .frame(width: 20, height: 20)
                        .background(Theme.colors.muted)
                        .cornerRadius(8)
                }
                .menuStyle(.borderlessButton).handCursor()
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More actions")
            }
            .padding(.horizontal, Theme.spacing.lg)
            .padding(.vertical, Theme.spacing.md)
            .background(Theme.colors.background)

            Rectangle()
                .fill(Theme.colors.borderSubtle)
                .frame(height: 0.5)

            // Current result only
            Group {
                if viewModel.isLoading {
                    VStack(spacing: Theme.spacing.md) {
                        ProgressView().scaleEffect(0.8)
                        Text("Running command…")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(Theme.colors.textTertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !viewModel.didRun {
                    VStack(spacing: Theme.spacing.md) {
                        Image(systemName: "terminal")
                            .font(.system(size: 22))
                            .foregroundColor(Theme.colors.textTertiary)
                            .opacity(0.5)
                        Text("Results appear here")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(Theme.colors.textTertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical) {
                        if isError {
                            Text(displayText)
                                .font(.system(size: resultFontSize, design: .monospaced))
                                .foregroundColor(Theme.colors.error)
                                .textSelection(.enabled)
                                .lineSpacing(3)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .padding(Theme.spacing.lg)
                        } else {
                            JSONHighlightedText(text: displayText, fontSize: resultFontSize)
                                .padding(Theme.spacing.lg)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.colors.codeBackground)
        }
        .alert("Clear command history?", isPresented: $showClearHistoryConfirm) {
            Button("Clear", role: .destructive) { viewModel.clearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears the saved command history. Favorites are not affected.")
        }
    }
}
