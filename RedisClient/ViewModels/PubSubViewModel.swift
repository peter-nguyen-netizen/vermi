import Foundation

@MainActor
final class PubSubViewModel: NSObject, ObservableObject {
    @Published var subscriptionChannels: [String] = []
    @Published var messages: [PubSubMessage] = []
    @Published var publishChannel: String = ""
    @Published var publishMessage: String = ""
    @Published var isSubscribing: Bool = false
    @Published var isPublishing: Bool = false
    @Published var errorMessage: String?

    /// Shared client for PUBLISH (a subscribed connection can't run other commands)
    private var redisClient: RedisClientProtocol?
    /// Dedicated connection for SUBSCRIBE — required by Redis protocol
    private var subscriberClient: RedisClientProtocol?
    private var connectionInfo: RedisConnection?

    func setClient(_ client: RedisClientProtocol) {
        self.redisClient = client
    }

    func setConnectionInfo(_ connection: RedisConnection) {
        self.connectionInfo = connection
    }

    func subscribe(channels: [String]) async {
        guard !channels.isEmpty else {
            errorMessage = "Channel list empty"
            return
        }

        guard let info = connectionInfo else {
            errorMessage = "No connection"
            return
        }

        do {
            isSubscribing = true
            errorMessage = nil

            // Lazily open the dedicated subscriber connection
            if subscriberClient == nil {
                let client = RedisClient(
                    host: info.host,
                    port: info.port,
                    useTLS: info.useTLS,
                    password: info.password
                )
                try await client.connect()
                await client.setPushHandler { value in
                    Task { @MainActor [weak self] in
                        self?.handlePush(value)
                    }
                }
                subscriberClient = client
            }

            guard let subscriber = subscriberClient else { return }

            for channel in channels {
                _ = try await subscriber.execute(["SUBSCRIBE", channel])
                subscriptionChannels.append(channel)
                messages.insert(
                    PubSubMessage(channel: channel, message: "✓ Subscribed", receivedAt: Date()),
                    at: 0
                )
            }
        } catch {
            errorMessage = error.localizedDescription
            isSubscribing = false
        }
    }

    /// Push frames: RESP2 ["message", channel, payload] / RESP3 push equivalent
    private func handlePush(_ value: RESPValue) {
        guard let elements = value.arrayValue,
              elements.count >= 3,
              let kind = elements[0].stringValue?.lowercased() else {
            return
        }

        let channel: String
        let payload: String

        switch kind {
        case "message":
            channel = elements[1].stringValue ?? "?"
            payload = elements[2].stringValue ?? ""
        case "pmessage" where elements.count >= 4:
            channel = elements[2].stringValue ?? "?"
            payload = elements[3].stringValue ?? ""
        default:
            return
        }

        messages.insert(
            PubSubMessage(channel: channel, message: payload, receivedAt: Date()),
            at: 0
        )
    }

    func unsubscribe(channel: String) async {
        if let subscriber = subscriberClient {
            _ = try? await subscriber.execute(["UNSUBSCRIBE", channel])
        }

        subscriptionChannels.removeAll { $0 == channel }

        if subscriptionChannels.isEmpty {
            isSubscribing = false
            if let subscriber = subscriberClient {
                try? await subscriber.disconnect()
                subscriberClient = nil
            }
        }
    }

    func publish() async {
        guard !publishChannel.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Channel name required"
            return
        }

        guard !publishMessage.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Message required"
            return
        }

        guard let client = redisClient else {
            errorMessage = "No connection"
            return
        }

        do {
            isPublishing = true
            errorMessage = nil

            let result = try await client.execute(["PUBLISH", publishChannel, publishMessage])
            let receivers = result.intValue ?? 0

            messages.insert(
                PubSubMessage(
                    channel: publishChannel,
                    message: "→ Published (\(receivers) receivers): \(publishMessage)",
                    receivedAt: Date()
                ),
                at: 0
            )
            publishMessage = ""
        } catch {
            errorMessage = error.localizedDescription
        }

        isPublishing = false
    }

    func clearMessages() {
        messages = []
    }

    func reset() {
        let subscriber = subscriberClient
        subscriberClient = nil
        if let subscriber = subscriber {
            Task {
                try? await subscriber.disconnect()
            }
        }

        subscriptionChannels = []
        messages = []
        publishChannel = ""
        publishMessage = ""
        isSubscribing = false
        isPublishing = false
        errorMessage = nil
    }
}
