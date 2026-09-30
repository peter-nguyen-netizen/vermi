import SwiftUI

// MARK: - Empty State View

struct EmptyStateView: View {
    @EnvironmentObject var appState: AppState
    @Binding var showConnectionSheet: Bool
    @Binding var appearance: AppearanceMode

    var body: some View {
        ZStack {
            GradientBackground()
            GridBackground()

            // Appearance toggle, top-right
            VStack {
                HStack {
                    Spacer()
                    AppearanceToggle(mode: $appearance)
                }
                Spacer()
            }
            .padding(Theme.spacing.xl)

            ScrollView {
                VStack(spacing: Theme.spacing.xxl) {
                    // Hero
                    VStack(spacing: Theme.spacing.lg) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Theme.colors.primary.opacity(0.12))
                                .frame(width: 64, height: 64)
                            Image(systemName: "cylinder.split.1x2.fill")
                                .font(.system(size: 32, design: .rounded))
                                .foregroundColor(Theme.colors.primary)
                        }

                        VStack(spacing: Theme.spacing.sm) {
                            Text("Vermi")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.colors.text)
                            Text("Connect to a Redis server or cluster to get started")
                                .font(.system(size: 15, design: .rounded))
                                .foregroundColor(Theme.colors.textSecondary)
                        }

                        Button(action: { showConnectionSheet = true }) {
                            HStack(spacing: Theme.spacing.sm) {
                                Image(systemName: "plus")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                Text("New Connection")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    .padding(.top, Theme.spacing.xxxl)

                    // Saved connections
                    if appState.savedConnections.isEmpty {
                        VStack(spacing: Theme.spacing.md) {
                            Image(systemName: "tray")
                                .font(.system(size: 25, design: .rounded))
                                .foregroundColor(Theme.colors.textTertiary)
                            Text("No saved connections yet")
                                .font(.system(size: 14, design: .rounded))
                                .foregroundColor(Theme.colors.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.spacing.xxxl)
                        .background(Theme.colors.surface.opacity(0.6))
                        .cornerRadius(Theme.sizes.cardCornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.sizes.cardCornerRadius)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .foregroundColor(Theme.colors.border)
                        )
                    } else {
                        VStack(alignment: .leading, spacing: Theme.spacing.lg) {
                            Text("Saved Connections")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(Theme.colors.textSecondary)
                                .textCase(.uppercase)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 280), spacing: Theme.spacing.lg)],
                                spacing: Theme.spacing.lg
                            ) {
                                ForEach(appState.savedConnections) { connection in
                                    ConnectionCard(connection: connection)
                                        .environmentObject(appState)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: 760)
                .padding(Theme.spacing.xxxl)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Connection Details View

struct ConnectionDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    /// Non-nil when editing an existing connection; nil when creating a new one.
    let editing: RedisConnection?

    @State private var name: String
    @State private var host: String
    @State private var port: String
    @State private var password: String
    @State private var useTLS: Bool
    @State private var tlsVerify: Bool
    @State private var connectionType: RedisConnection.ConnectionType
    @State private var database: String
    @State private var useSSH: Bool
    @State private var sshHost: String
    @State private var sshPort: String
    @State private var sshUser: String
    @State private var sshKeyPath: String
    @State private var errorMessage = ""
    @State private var isTestingConnection = false
    @State private var testMessage = ""
    @State private var testSucceeded = false
    @State private var revealPassword = false
    @FocusState private var focusedField: Field?

    enum Field: Hashable {
        case name, host, port, password
    }

    init(editing: RedisConnection? = nil) {
        self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
        _host = State(initialValue: editing?.host ?? "localhost")
        _port = State(initialValue: editing.map { String($0.port) } ?? "6379")
        _password = State(initialValue: editing?.password ?? "")
        _useTLS = State(initialValue: editing?.useTLS ?? false)
        _tlsVerify = State(initialValue: editing?.tlsVerify ?? true)
        _connectionType = State(initialValue: editing?.connectionType ?? .single)
        _database = State(initialValue: editing.map { String($0.database) } ?? "0")
        _useSSH = State(initialValue: editing?.useSSH ?? false)
        _sshHost = State(initialValue: editing?.sshHost ?? "")
        _sshPort = State(initialValue: editing.map { String($0.sshPort) } ?? "22")
        _sshUser = State(initialValue: editing?.sshUser ?? "")
        _sshKeyPath = State(initialValue: editing?.sshKeyPath ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(editing == nil ? "New Connection" : "Edit Connection")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.colors.text)
                        Text("Connect to a Redis server or cluster.")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundColor(Theme.colors.textSecondary)
                    }
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.colors.textSecondary)
                            .frame(width: 24, height: 24)
                            .background(Theme.colors.muted)
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain).handCursor()
                }
            }
            .padding(Theme.spacing.xxl)

            SectionDivider()
                .padding(.horizontal, Theme.spacing.xxl)

            // Form
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacing.xl) {
                    FormField(label: "Connection Type") {
                        Picker("", selection: $connectionType) {
                            Text("Standalone").tag(RedisConnection.ConnectionType.single)
                            Text("Cluster").tag(RedisConnection.ConnectionType.cluster)
                            Text("Sentinel").tag(RedisConnection.ConnectionType.sentinel)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    FormField(label: "Name") {
                        TextField("My Redis", text: $name)
                            .inputField()
                            .focused($focusedField, equals: .name)
                    }

                    FormField(label: "Host") {
                        TextField("localhost", text: $host)
                            .inputField()
                            .focused($focusedField, equals: .host)
                            .onChange(of: host) { newValue in
                                normalizeHostInput(newValue)
                            }
                    }

                    HStack(alignment: .top, spacing: Theme.spacing.lg) {
                        FormField(label: "Port") {
                            TextField("6379", text: $port)
                                .inputField()
                                .focused($focusedField, equals: .port)
                        }

                        FormField(label: "Database") {
                            TextField("0", text: $database)
                                .inputField()
                                .disabled(connectionType == .cluster)
                                .opacity(connectionType == .cluster ? 0.5 : 1)
                        }
                    }

                    FormField(label: "Password") {
                        HStack(spacing: Theme.spacing.sm) {
                            Group {
                                if revealPassword {
                                    TextField("Leave empty if none", text: $password)
                                } else {
                                    SecureField("Leave empty if none", text: $password)
                                }
                            }
                            .inputField()
                            .focused($focusedField, equals: .password)

                            Button { revealPassword.toggle() } label: {
                                Image(systemName: revealPassword ? "eye.slash" : "eye")
                                    .font(.system(size: 12))
                                    .foregroundColor(Theme.colors.textTertiary)
                            }
                            .buttonStyle(.plain).handCursor()
                            .help(revealPassword ? "Hide password" : "Show password")
                        }
                    }

                    // TLS options as clean rows
                    VStack(spacing: Theme.spacing.md) {
                        ToggleRow(title: "Use TLS", subtitle: "Encrypt the connection", isOn: $useTLS)
                        if useTLS {
                            ToggleRow(title: "Verify certificate", subtitle: "Reject invalid TLS certificates", isOn: $tlsVerify)
                        }
                    }

                    // SSH tunnel
                    VStack(spacing: Theme.spacing.md) {
                        ToggleRow(title: "SSH tunnel", subtitle: "Reach the host via a bastion (key/agent auth)", isOn: $useSSH)
                        if useSSH {
                            FormField(label: "SSH Host") { TextField("bastion.example.com", text: $sshHost).inputField() }
                            HStack(alignment: .top, spacing: Theme.spacing.lg) {
                                FormField(label: "SSH Port") { TextField("22", text: $sshPort).inputField() }
                                FormField(label: "SSH User") { TextField("ec2-user", text: $sshUser).inputField() }
                            }
                            FormField(label: "Identity file (optional)") {
                                TextField("~/.ssh/id_ed25519 (blank = agent)", text: $sshKeyPath).inputField()
                            }
                        }
                    }

                    if !errorMessage.isEmpty {
                        InlineBanner(text: errorMessage, isError: true)
                    }
                    if !testMessage.isEmpty {
                        InlineBanner(text: testMessage, isError: !testSucceeded)
                    }
                }
                .padding(Theme.spacing.xxl)
            }

            SectionDivider()
                .padding(.horizontal, Theme.spacing.xxl)

            // Footer
            HStack(spacing: Theme.spacing.md) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(GhostButtonStyle())

                Spacer()

                Button(action: { Task { await testConnection() } }) {
                    if isTestingConnection {
                        HStack(spacing: Theme.spacing.sm) {
                            ProgressView().scaleEffect(0.6, anchor: .center)
                            Text("Testing…")
                        }
                    } else {
                        Text("Test Connection")
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(isTestingConnection || host.isEmpty)

                Button("Save") { saveConnection() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(Theme.spacing.xxl)
        }
        .frame(width: 440, height: 600)
        .background(Theme.colors.surface)
        .onAppear {
            focusedField = .name
        }
    }

    /// Auto-detect `host:port` (or a redis:// URL) pasted into the Host field and
    /// split the port into the Port field. Leaves bare hosts and raw IPv6 alone.
    private func normalizeHostInput(_ raw: String) {
        var s = raw.trimmingCharacters(in: .whitespaces)

        // Strip a redis scheme if pasted (redis://, rediss://).
        for scheme in ["rediss://", "redis://"] where s.lowercased().hasPrefix(scheme) {
            s = String(s.dropFirst(scheme.count))
        }
        // Drop anything after a path/query (redis://host:port/0).
        if let slash = s.firstIndex(of: "/") { s = String(s[s.startIndex..<slash]) }

        var newHost: String?
        var newPort: String?

        if s.hasPrefix("[") {
            // Bracketed IPv6: [::1]:6379
            if let close = s.firstIndex(of: "]") {
                newHost = String(s[s.index(after: s.startIndex)..<close])
                let rest = s[s.index(after: close)...]
                if rest.hasPrefix(":"), let p = portValue(String(rest.dropFirst())) {
                    newPort = p
                }
            }
        } else {
            let parts = s.split(separator: ":", omittingEmptySubsequences: false)
            // Exactly one colon + numeric right side → host:port. More colons =
            // raw IPv6 (leave as-is).
            if parts.count == 2, let p = portValue(String(parts[1])), !parts[0].isEmpty {
                newHost = String(parts[0])
                newPort = p
            }
        }

        guard let h = newHost else {
            // Only rewrite if we stripped a scheme/path
            if s != raw.trimmingCharacters(in: .whitespaces) { host = s }
            return
        }
        if h != host { host = h }
        if let p = newPort, p != port { port = p }
    }

    /// Return the string if it is a valid 1–65535 port, else nil.
    private func portValue(_ s: String) -> String? {
        guard let n = UInt16(s), n > 0 else { return nil }
        return String(n)
    }

    private func saveConnection() {
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            errorMessage = "Connection name required"
            return
        }

        if host.trimmingCharacters(in: .whitespaces).isEmpty {
            errorMessage = "Host required"
            return
        }

        guard let portNum = UInt16(port) else {
            errorMessage = "Invalid port number"
            return
        }

        let connection = RedisConnection(
            id: editing?.id ?? UUID(),
            name: name,
            host: host,
            port: portNum,
            password: password.isEmpty ? nil : password,
            useTLS: useTLS,
            tlsVerify: tlsVerify,
            connectionType: connectionType,
            database: Int(database) ?? 0,
            lastConnected: editing?.lastConnected,
            isFavorite: editing?.isFavorite ?? false,
            colorTag: editing?.colorTag,
            useSSH: useSSH,
            sshHost: sshHost.trimmingCharacters(in: .whitespaces),
            sshPort: UInt16(sshPort) ?? 22,
            sshUser: sshUser.trimmingCharacters(in: .whitespaces),
            sshKeyPath: expandTilde(sshKeyPath.trimmingCharacters(in: .whitespaces))
        )
        if editing == nil {
            appState.addSavedConnection(connection)
            ToastCenter.shared.success("Saved connection \(connection.name)")
        } else {
            appState.updateSavedConnection(connection)
            ToastCenter.shared.success("Updated connection \(connection.name)")
        }
        dismiss()
    }

    private func expandTilde(_ path: String) -> String {
        path.hasPrefix("~") ? (path as NSString).expandingTildeInPath : path
    }

    @MainActor
    private func testConnection() async {
        errorMessage = ""
        testMessage = ""

        if host.trimmingCharacters(in: .whitespaces).isEmpty {
            errorMessage = "Host required"
            return
        }

        guard let portNum = UInt16(port) else {
            errorMessage = "Invalid port number"
            return
        }

        isTestingConnection = true

        let client = RedisClient(
            host: host,
            port: portNum,
            useTLS: useTLS,
            password: password.isEmpty ? nil : password,
            isCluster: connectionType == .cluster
        )

        do {
            try await client.connect()
            defer { Task { try? await client.disconnect() } }
            let pong = try await client.ping()
            testSucceeded = true
            testMessage = "✓ Connected successfully! PING returned: \(pong)"
            ToastCenter.shared.success("Connection test succeeded (PING → \(pong))")
        } catch {
            testSucceeded = false
            testMessage = "Failed to connect: \(error.localizedDescription)"
            ToastCenter.shared.error("Connection test failed: \(error.localizedDescription)")
        }

        isTestingConnection = false
    }
}

// MARK: - Form components

/// Labeled form field: sentence-case label above the control (shadcn form row).
struct FormField<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.md) {
            Text(label)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(Theme.colors.text)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A bordered row with title/subtitle and a trailing switch.
struct ToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: Theme.spacing.lg) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.colors.text)
                Text(subtitle)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(Theme.colors.textTertiary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .scaleEffect(0.85)
        }
        .padding(.horizontal, Theme.spacing.lg)
        .padding(.vertical, Theme.spacing.md)
        .background(Theme.colors.muted)
        .cornerRadius(Theme.sizes.smallCornerRadius)
    }
}

/// Inline success/error banner used inside forms.
struct InlineBanner: View {
    let text: String
    let isError: Bool

    private var color: Color { isError ? Theme.colors.error : Theme.colors.success }

    var body: some View {
        HStack(spacing: Theme.spacing.md) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 13, design: .rounded))
            Text(text)
                .font(.system(size: 13, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundColor(color)
        .padding(Theme.spacing.lg)
        .background(color.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.sizes.smallCornerRadius)
                .stroke(color.opacity(0.2), lineWidth: 0.5)
        )
        .cornerRadius(Theme.sizes.smallCornerRadius)
    }
}
