import SwiftUI

struct PubSubView: View {
    @EnvironmentObject var appState: AppState
    @State private var leftWidth: CGFloat = 280

    // Per-tab view model so subscriptions/messages survive tab switches.
    private var viewModel: PubSubViewModel {
        appState.activePubSubViewModel ?? PubSubViewModel()
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left panel - subscriptions
            VStack(spacing: 0) {
                PubSubSubscriberPane()
                    .environmentObject(appState)
                    .environmentObject(viewModel)
                    .frame(maxHeight: .infinity)

                Rectangle()
                    .fill(Theme.colors.border)
                    .frame(height: 0.5)

                PubSubPublisherPane()
                    .environmentObject(appState)
                    .environmentObject(viewModel)
                    .frame(height: 100)
            }
            .frame(width: leftWidth)
            .background(Theme.colors.background)

            HResizeHandle(width: $leftWidth, minWidth: 220, maxWidth: 500)

            // Right panel - messages
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.spacing.sm) {
                        if viewModel.messages.isEmpty {
                            VStack(spacing: Theme.spacing.lg) {
                                Image(systemName: "bubble.right")
                                    .font(.system(size: 23, design: .rounded))
                                    .foregroundColor(Theme.colors.textTertiary)
                                    .opacity(0.5)
                                Text("No messages")
                                    .font(.system(size: 13, design: .rounded))
                                    .foregroundColor(Theme.colors.textTertiary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            // Anchor at the very top; messages are newest-first.
                            Color.clear.frame(height: 0).id("top")
                            ForEach(viewModel.messages) { msg in
                                MessageItem(message: msg)
                            }
                        }
                    }
                    .padding(Theme.spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .background(Theme.colors.background)
                // New messages land at the top — keep the newest in view.
                .onChange(of: viewModel.messages.first?.id) { _ in
                    withAnimation { proxy.scrollTo("top", anchor: .top) }
                }
            }
        }
        .onChange(of: viewModel.errorMessage) { msg in
            if let msg = msg, !msg.isEmpty { ToastCenter.shared.error(msg) }
        }
    }
}

// MARK: - Subscriber Pane

struct PubSubSubscriberPane: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var viewModel: PubSubViewModel
    @State private var newChannel = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Subscribe")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.colors.textSecondary)
                    .textCase(.uppercase)
                Spacer()
            }
            .padding(.horizontal, Theme.spacing.lg)
            .padding(.vertical, Theme.spacing.md)

            Rectangle()
                .fill(Theme.colors.borderSubtle)
                .frame(height: 0.5)

            // Channel list
            if viewModel.subscriptionChannels.isEmpty {
                VStack(spacing: Theme.spacing.md) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 18, design: .rounded))
                        .foregroundColor(Theme.colors.textTertiary)
                        .opacity(0.5)
                    Text("No subscriptions")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(Theme.colors.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 20)
            } else {
                ScrollView {
                    VStack(spacing: Theme.spacing.xs) {
                        ForEach(viewModel.subscriptionChannels, id: \.self) { channel in
                            HStack(spacing: Theme.spacing.md) {
                                Image(systemName: "bubble.left.fill")
                                    .font(.system(size: 9, design: .rounded))
                                    .foregroundColor(Theme.colors.primary)
                                Text(channel)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(Theme.colors.text)
                                    .lineLimit(1)
                                Spacer()
                                Button(action: {
                                    Task {
                                        await viewModel.unsubscribe(channel: channel)
                                    }
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12, design: .rounded))
                                        .foregroundColor(Theme.colors.textTertiary)
                                }
                                .buttonStyle(.plain).handCursor()
                                .help("Unsubscribe from \(channel)")
                            }
                            .padding(.horizontal, Theme.spacing.md)
                            .padding(.vertical, Theme.spacing.sm)
                            .background(Theme.colors.surfaceHover)
                            .cornerRadius(Theme.sizes.smallCornerRadius)
                        }
                    }
                    .padding(Theme.spacing.md)
                }
            }

            // Add channel input
            Rectangle()
                .fill(Theme.colors.borderSubtle)
                .frame(height: 0.5)

            HStack(spacing: Theme.spacing.sm) {
                TextField("Channel to subscribe…", text: $newChannel)
                    .inputField()
                    .font(.system(size: 13, design: .monospaced))
                    .onSubmit(subscribe)

                Button(action: subscribe) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(width: Theme.sizes.buttonHeight, height: Theme.sizes.buttonHeight)
                        .background(Theme.colors.primary)
                        .cornerRadius(Theme.sizes.smallCornerRadius)
                }
                .buttonStyle(.plain).handCursor()
                .disabled(newChannel.trimmingCharacters(in: .whitespaces).isEmpty)
                .help("Subscribe")
            }
            .padding(Theme.spacing.md)
        }
    }

    private func subscribe() {
        let trimmed = newChannel.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        Task { await viewModel.subscribe(channels: [trimmed]) }
        newChannel = ""
    }
}

// MARK: - Publisher Pane

struct PubSubPublisherPane: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var viewModel: PubSubViewModel

    var body: some View {
        VStack(spacing: Theme.spacing.md) {
            // Header
            HStack {
                Text("Publish")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.colors.textSecondary)
                    .textCase(.uppercase)
                Spacer()
            }
            .padding(.horizontal, Theme.spacing.lg)
            .padding(.top, Theme.spacing.md)

            // Channel
            TextField("Channel", text: $viewModel.publishChannel)
                .inputField()
                .font(.system(size: 13, design: .monospaced))
                .padding(.horizontal, Theme.spacing.lg)

            // Message & Send
            HStack(spacing: Theme.spacing.sm) {
                TextField("Message", text: $viewModel.publishMessage)
                    .inputField()
                    .font(.system(size: 13, design: .monospaced))
                    .onSubmit { if canPublish { publish() } }

                Button(action: publish) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.white)
                        .frame(width: Theme.sizes.buttonHeight, height: Theme.sizes.buttonHeight)
                        .background(canPublish ? Theme.colors.primary : Theme.colors.muted)
                        .cornerRadius(Theme.sizes.smallCornerRadius)
                }
                .buttonStyle(.plain).handCursor()
                .disabled(!canPublish)
                .help("Publish message")
            }
            .padding(.horizontal, Theme.spacing.lg)

            if let errorMsg = viewModel.errorMessage, !errorMsg.isEmpty {
                Text(errorMsg)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(Theme.colors.error)
                    .padding(.horizontal, Theme.spacing.lg)
            }
        }
        .padding(.bottom, Theme.spacing.md)
    }

    private var canPublish: Bool {
        !viewModel.isPublishing
            && !viewModel.publishChannel.trimmingCharacters(in: .whitespaces).isEmpty
            && !viewModel.publishMessage.isEmpty
    }

    private func publish() {
        guard canPublish else { return }
        Task { await viewModel.publish() }
    }
}

// MARK: - Message Item

struct MessageItem: View {
    let message: PubSubMessage

    private var kind: (label: String, color: Color) {
        if message.message.hasPrefix("→") { return ("PUB", Theme.colors.warning) }
        if message.message.hasPrefix("✓") { return ("SUB", Theme.colors.success) }
        return ("MSG", Theme.colors.primary)
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacing.md) {
            RoundedRectangle(cornerRadius: 2)
                .fill(kind.color)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: Theme.spacing.sm) {
                HStack(spacing: Theme.spacing.sm) {
                    Badge(text: kind.label, color: kind.color)
                    Text(message.channel)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(Theme.colors.text)
                        .lineLimit(1)
                    Spacer()
                    Text(formatTime(message.receivedAt))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Theme.colors.textTertiary)
                    CopyButton(value: message.message, size: 10, help: "Copy message")
                }

                Text(message.message)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(Theme.colors.textSecondary)
                    .lineLimit(6)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(Theme.spacing.md)
        .background(Theme.colors.surface)
        .cornerRadius(Theme.sizes.smallCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.sizes.smallCornerRadius)
                .stroke(Theme.colors.borderSubtle, lineWidth: 0.5)
        )
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
