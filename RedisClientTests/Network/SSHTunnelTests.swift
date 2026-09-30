import XCTest
@testable import RedisClient

final class SSHTunnelTests: XCTestCase {
    func testArgumentsWithKey() {
        let cfg = SSHTunnel.Config(sshHost: "bastion.example.com", sshPort: 2222,
                                   sshUser: "ec2-user", keyPath: "/Users/me/.ssh/id",
                                   remoteHost: "redis.internal", remotePort: 6379)
        let args = SSHTunnel.arguments(config: cfg, localPort: 51234)
        XCTAssertTrue(args.contains("-N"))
        XCTAssertTrue(args.contains("-L"))
        XCTAssertTrue(args.contains("127.0.0.1:51234:redis.internal:6379"))
        XCTAssertTrue(args.contains("2222"))
        XCTAssertTrue(args.contains("/Users/me/.ssh/id"))
        XCTAssertTrue(args.contains("ec2-user@bastion.example.com"))
        XCTAssertTrue(args.contains("ExitOnForwardFailure=yes"))
    }

    func testArgumentsNoKeyNoUser() {
        let cfg = SSHTunnel.Config(sshHost: "host", sshPort: 22, sshUser: "", keyPath: "",
                                   remoteHost: "r", remotePort: 6379)
        let args = SSHTunnel.arguments(config: cfg, localPort: 60000)
        XCTAssertFalse(args.contains("-i"))
        XCTAssertTrue(args.contains("host"))          // no user@ prefix
        XCTAssertFalse(args.contains { $0.hasPrefix("@") })
    }

    func testFreeLocalPortIsUsable() throws {
        let p = try SSHTunnel.freeLocalPort()
        XCTAssertGreaterThan(p, 0)
    }
}
