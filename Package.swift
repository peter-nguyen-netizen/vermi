// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RedisClient",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        // Product (binary/.app) is "Vermi"; the target/module stays "RedisClient".
        .executable(name: "Vermi", targets: ["RedisClient"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "RedisClient",
            dependencies: [],
            path: "RedisClient",
            exclude: ["Info.plist"],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "RedisClientTests",
            dependencies: ["RedisClient"],
            path: "RedisClientTests"
        )
    ]
)
