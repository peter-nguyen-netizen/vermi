import Foundation
import Network

/// Local port-forward over the system `ssh` binary:
///   ssh -N -L 127.0.0.1:<local>:<redisHost>:<redisPort> [-p sshPort] [-i key] user@sshHost
/// Vermi then connects to 127.0.0.1:<local>. Uses key / ssh-agent auth
/// (password SSH auth needs a tty/askpass and isn't supported).
actor SSHTunnel {
    struct Config {
        let sshHost: String
        let sshPort: UInt16
        let sshUser: String
        let keyPath: String     // empty → agent / ~/.ssh/config
        let remoteHost: String
        let remotePort: UInt16
    }

    private var process: Process?
    private(set) var localPort: UInt16 = 0

    /// Build the ssh argument list (pure, unit-tested).
    static func arguments(config: Config, localPort: UInt16) -> [String] {
        var args = [
            "-N",                                   // no remote command
            "-o", "ExitOnForwardFailure=yes",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ServerAliveInterval=30",
            "-L", "127.0.0.1:\(localPort):\(config.remoteHost):\(config.remotePort)",
            "-p", String(config.sshPort)
        ]
        if !config.keyPath.isEmpty {
            args += ["-i", config.keyPath, "-o", "IdentitiesOnly=yes"]
        }
        let userHost = config.sshUser.isEmpty ? config.sshHost : "\(config.sshUser)@\(config.sshHost)"
        args.append(userHost)
        return args
    }

    /// Start the tunnel and wait until the local port accepts connections.
    func start(config: Config) async throws {
        let port = try Self.freeLocalPort()
        localPort = port

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        proc.arguments = Self.arguments(config: config, localPort: port)
        proc.standardOutput = FileHandle.nullDevice
        let errPipe = Pipe()
        proc.standardError = errPipe
        do {
            try proc.run()
        } catch {
            throw RESPError.connectionError("Failed to launch ssh: \(error.localizedDescription)")
        }
        process = proc

        // Wait for the forwarded port to become connectable (or ssh to exit).
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if !proc.isRunning {
                let err = String(data: errPipe.fileHandleForReading.availableData, encoding: .utf8) ?? ""
                throw RESPError.connectionError("SSH tunnel failed: \(err.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            if Self.canConnect(port: port) { return }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        stop()
        throw RESPError.connectionError("SSH tunnel timed out establishing the forward")
    }

    func stop() {
        process?.terminate()
        process = nil
    }

    // MARK: helpers

    /// Ask the OS for a free TCP port (bind to 0, read assignment, close).
    static func freeLocalPort() throws -> UInt16 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw RESPError.connectionError("socket() failed") }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { throw RESPError.connectionError("bind() failed") }
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &len)
            }
        }
        return UInt16(bigEndian: addr.sin_port)
    }

    private static func canConnect(port: UInt16) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = port.bigEndian
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return r == 0
    }
}
