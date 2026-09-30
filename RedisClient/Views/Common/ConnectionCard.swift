import SwiftUI

/// Connection card shown in the EmptyStateView management grid. Double-click /
/// hover-play / context-menu opens the connection.
struct ConnectionCard: View {
    @EnvironmentObject var appState: AppState
    let connection: RedisConnection
    @State private var isHovering = false
    @State private var showDeleteConfirm = false
    @Environment(\.colorScheme) private var colorScheme

    private var avatarColor: Color {
        Theme.colors.avatarColor(for: connection.name)
    }

    var body: some View {
        HStack(spacing: Theme.spacing.lg) {
            // Avatar with initial
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(avatarColor.opacity(0.12))
                    .frame(width: 32, height: 32)
                Text(String(connection.name.prefix(1)).uppercased())
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(avatarColor)
            }

            // Name + host info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(connection.name)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.colors.text)
                        .lineLimit(1)

                    if connection.connectionType != .single {
                        Text(connection.connectionType.rawValue.uppercased())
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .foregroundColor(Theme.colors.primary)
                            .background(Theme.colors.primary.opacity(0.1))
                            .cornerRadius(2)
                    }

                    if connection.useTLS {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundColor(Theme.colors.success)
                    }
                }

                Text("\(connection.host):\(String(connection.port))")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Theme.colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Connect button appears on hover
            if isHovering {
                Button(action: { open() }) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 21, design: .rounded))
                        .foregroundColor(Theme.colors.primary)
                }
                .buttonStyle(.plain).handCursor()
                .help("Connect")
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(Theme.spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.sizes.cardCornerRadius)
                .fill(isHovering ? Theme.colors.surfaceHover : Theme.colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.sizes.cardCornerRadius)
                .stroke(
                    isHovering ? Theme.colors.primary.opacity(0.3) : Theme.colors.borderSubtle,
                    lineWidth: 0.5
                )
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onTapGesture(count: 2) {
            open()
        }
        .handCursor()
        .contextMenu {
            Button("Connect") { open() }
            Button("Edit…") { appState.editingConnection = connection }
            Divider()
            Button("Delete…", role: .destructive) { showDeleteConfirm = true }
        }
        .alert("Delete \(connection.name)?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                Task { await appState.removeSavedConnection(connection) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the saved connection and its stored password.")
        }
        .help("Double-click to connect")
    }

    private func open() {
        Task {
            await appState.openConnectionTab(connection)
        }
    }
}
