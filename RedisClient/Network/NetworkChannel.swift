import Foundation
import Network
import os.log

private let logger = Logger(subsystem: "io.clearer.vermi", category: "NetworkChannel")

/// Once-only latch, safe to touch from NWConnection's queue and the timeout queue.
private final class ResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    /// Returns true exactly once — the caller that wins gets to resume the continuation.
    func tryResume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if resumed { return false }
        resumed = true
        return true
    }

    var hasResumed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return resumed
    }
}

actor NetworkChannel: Sendable {
    enum State: Equatable {
        case disconnected
        case connecting
        case connected
        case disconnecting
        case failed(Error)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.disconnected, .disconnected),
                 (.connecting, .connecting),
                 (.connected, .connected),
                 (.disconnecting, .disconnecting):
                return true
            case (.failed, .failed):
                return true
            default:
                return false
            }
        }
    }

    private let host: String
    private let port: UInt16
    private let useTLS: Bool
    private let password: String?
    private var connection: NWConnection?
    private var state: State = .disconnected
    private let commandTimeout: TimeInterval
    private var receivedData = Data()
    private var pendingResponses: [RESPValue] = []
    private var pushHandler: (@Sendable (RESPValue) -> Void)?
    /// Tail of the serialized command chain (see enqueue)
    private var commandQueue: Task<[RESPValue], Error>?
    /// Event-driven response waiter: resumed the instant enough frames arrive
    /// (replaces a 20ms polling loop). Only one at a time (commands serialize).
    private var responseWaiter: (count: Int, cont: CheckedContinuation<[RESPValue], Error>)?
    private var waiterGen = 0

    init(
        host: String,
        port: UInt16,
        useTLS: Bool = false,
        password: String? = nil,
        commandTimeout: TimeInterval = 10.0
    ) {
        self.host = host
        self.port = port
        self.useTLS = useTLS
        self.password = password
        self.commandTimeout = commandTimeout
    }

    func connect() async throws {
        guard state == .disconnected else {
            logger.error("Cannot connect: state is \(String(describing: self.state))")
            throw RESPError.connectionError("Already connected or connecting")
        }

        state = .connecting
        // Clear any stale buffered bytes/responses from a previous session (reconnect)
        receivedData.removeAll()
        pendingResponses.removeAll()
        logger.info("Connecting to \(self.host):\(self.port) TLS=\(self.useTLS)")

        let parameters = NWParameters(tls: useTLS ? .init() : nil)

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            logger.error("Invalid port: \(self.port)")
            throw RESPError.connectionError("Invalid port: \(port)")
        }

        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: nwPort,
            using: parameters
        )
        logger.debug("NWConnection created")

        self.connection = connection

        // NWConnection can fire .ready then .cancelled (or .waiting repeatedly);
        // the continuation must resume exactly once, from a @Sendable handler.
        let resumeGuard = ResumeGuard()

        let (connected, error) = await withCheckedContinuation { (continuation: CheckedContinuation<(Bool, Error?), Never>) in
            let stateHandler: @Sendable (NWConnection.State) -> Void = { [weak self] state in
                logger.info("Connection state: \(String(describing: state))")
                switch state {
                case .ready:
                    guard resumeGuard.tryResume() else { return }
                    logger.info("Connected successfully")
                    Task {
                        await self?.startReceiving()
                    }
                    continuation.resume(returning: (true, nil as Error?))
                case .failed(let err):
                    guard resumeGuard.tryResume() else { return }
                    logger.error("Connection failed: \(String(describing: err))")
                    continuation.resume(returning: (false, err))
                case .cancelled:
                    guard resumeGuard.tryResume() else { return }
                    logger.warning("Connection cancelled")
                    continuation.resume(returning: (false, RESPError.connectionError("Connection cancelled")))
                case .waiting(let err):
                    // .waiting = unreachable/handshake stall; NWConnection retries forever.
                    // Fail fast so UI doesn't spin.
                    guard resumeGuard.tryResume() else { return }
                    logger.warning("Connection waiting: \(String(describing: err))")
                    connection.cancel()
                    continuation.resume(returning: (false, err))
                default:
                    logger.debug("Connection state: preparing")
                }
            }

            connection.stateUpdateHandler = stateHandler
            connection.start(queue: .global())
            logger.debug("Connection started")

            // Overall connect timeout: cancel if neither ready nor failed in 10s.
            // Cancel triggers .cancelled above, which resumes the continuation.
            DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
                if !resumeGuard.hasResumed {
                    logger.error("Connect timeout after 10s, cancelling")
                    connection.cancel()
                }
            }
        }

        if connected {
            state = .connected
        } else {
            state = .disconnected
            throw error ?? RESPError.connectionError("Failed to connect")
        }
    }

    func disconnect() async throws {
        guard state == .connected else {
            return
        }

        state = .disconnecting
        connection?.cancel()
        connection = nil
        state = .disconnected
    }

    func send(_ command: [String]) async throws -> RESPValue {
        let encoder = RESPEncoder()
        let data = encoder.encode(command)
        return try await enqueue(data, count: 1)[0]
    }

    func sendRaw(_ data: Data) async throws -> RESPValue {
        return try await enqueue(data, count: 1)[0]
    }

    /// Pipeline: send many commands in one write and read their replies in order
    /// (one network round-trip instead of one per command). Returns replies
    /// positionally aligned with `commands`.
    func pipeline(_ commands: [[String]]) async throws -> [RESPValue] {
        guard !commands.isEmpty else { return [] }
        let encoder = RESPEncoder()
        var buffer = Data()
        for cmd in commands { buffer.append(encoder.encode(cmd)) }
        return try await enqueue(buffer, count: commands.count)
    }

    /// Serializes commands so exactly one request/response is in flight at a
    /// time. The actor alone is NOT enough: `send` awaits mid-flight, letting a
    /// concurrent caller (e.g. background SCAN loop vs. loadKeyDetails) reenter,
    /// send a second command, and race the shared `pendingResponses` queue —
    /// responses then get matched to the wrong command. Chaining each call onto
    /// the previous one guarantees FIFO request/response pairing.
    private func enqueue(_ data: Data, count: Int) async throws -> [RESPValue] {
        let previous = commandQueue
        let task = Task { () throws -> [RESPValue] in
            _ = try? await previous?.value
            return try await self.performSendAndWait(data, count: count)
        }
        commandQueue = task
        return try await task.value
    }

    private func performSendAndWait(_ data: Data, count: Int) async throws -> [RESPValue] {
        guard state == .connected, let connection = connection else {
            throw RESPError.connectionError("Not connected")
        }

        // Commands are serialized, so before sending there must be no in-flight
        // response for us. Drop any leftover bytes/responses from a previously
        // timed-out command — otherwise a half-parsed frame corrupts this one's
        // parse (symptom: "Invalid response format: Expected CR").
        pendingResponses.removeAll()
        receivedData.removeAll()

        let (sendSuccess, sendError) = await withCheckedContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { error in
                continuation.resume(returning: (error == nil, error))
            })
        }

        if !sendSuccess {
            throw sendError ?? RESPError.connectionError("Failed to send command")
        }

        return try await waitForResponses(count)
    }

    private func startReceiving() {
        guard let connection = connection else {
            return
        }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            Task {
                if error != nil {
                    await self.handleConnectionClosed()
                    return
                }

                if let data = data, !data.isEmpty {
                    await self.handleReceivedData(data)
                }

                if isComplete {
                    await self.handleConnectionClosed()
                } else {
                    await self.startReceiving()
                }
            }
        }
    }

    private func handleReceivedData(_ data: Data) {
        receivedData.append(data)
        drainBuffer()
        fulfillWaiterIfReady()
    }

    /// Resume the pending waiter the moment enough responses have arrived.
    private func fulfillWaiterIfReady() {
        guard let w = responseWaiter, pendingResponses.count >= w.count else { return }
        responseWaiter = nil
        waiterGen += 1   // invalidate the scheduled timeout for this waiter
        let out = Array(pendingResponses.prefix(w.count))
        pendingResponses.removeFirst(w.count)
        w.cont.resume(returning: out)
    }

    /// Parse every complete frame in the buffer, keeping unconsumed bytes.
    /// Push frames (Pub/Sub messages) go to pushHandler; everything else is
    /// queued for waitForResponse(). Fixes: previously the whole buffer was
    /// discarded after one parse, silently dropping any second response.
    private func drainBuffer() {
        while !receivedData.isEmpty {
            let parser = RESPParser(data: receivedData)
            do {
                let value = try parser.parse()
                let consumed = parser.consumedOffset
                if consumed >= receivedData.count {
                    receivedData = Data()
                } else {
                    receivedData = receivedData.subdata(in: consumed..<receivedData.count)
                }

                if isPushMessage(value) {
                    logger.debug("Push frame routed to handler")
                    pushHandler?(value)
                } else {
                    pendingResponses.append(value)
                }
            } catch RESPError.incompleteData {
                return
            } catch {
                logger.error("Protocol desync, dropping buffer: \(String(describing: error))")
                receivedData = Data()
                pendingResponses.append(.error("Protocol error: \(error.localizedDescription)"))
                return
            }
        }
    }

    /// RESP3 push frames, or RESP2 pub/sub arrays ("message"/"pmessage").
    /// SUBSCRIBE/UNSUBSCRIBE confirmations stay in the response queue since
    /// they answer an explicit command.
    private func isPushMessage(_ value: RESPValue) -> Bool {
        if case .push = value { return true }
        if case .array(let elements?) = value,
           let kind = elements.first?.stringValue?.lowercased(),
           kind == "message" || kind == "pmessage" {
            return true
        }
        return false
    }

    func setPushHandler(_ handler: @escaping @Sendable (RESPValue) -> Void) {
        pushHandler = handler
    }

    private func handleConnectionClosed() {
        state = .disconnected
        connection = nil
        // Fail any in-flight waiter so its caller doesn't hang until timeout.
        if let w = responseWaiter {
            responseWaiter = nil
            waiterGen += 1
            w.cont.resume(throwing: RESPError.connectionError("Connection closed"))
        }
    }

    /// Event-driven wait for `count` responses, with a timeout. Resumed by
    /// `fulfillWaiterIfReady()` as soon as the frames arrive.
    private func waitForResponses(_ count: Int) async throws -> [RESPValue] {
        if pendingResponses.count >= count {
            let out = Array(pendingResponses.prefix(count))
            pendingResponses.removeFirst(count)
            return out
        }
        waiterGen += 1
        let gen = waiterGen
        let timeout = commandTimeout
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[RESPValue], Error>) in
            responseWaiter = (count, cont)
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                await self?.timeoutFired(gen)
            }
        }
    }

    private func timeoutFired(_ gen: Int) {
        guard gen == waiterGen, let w = responseWaiter else { return }
        responseWaiter = nil
        // Stream position now unknown — tear down so the next command reconnects
        // cleanly instead of parsing a late reply against the wrong request.
        state = .disconnected
        connection?.cancel()
        connection = nil
        w.cont.resume(throwing: RESPError.timeout)
    }

    func getConnectionState() -> State {
        state
    }
}
