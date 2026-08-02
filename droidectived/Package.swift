// swift-tools-version: 6.1
import PackageDescription

// The local daemon that exposes ADBKit to a non-Swift UI (see
// docs/droidectived-protocol.md). Its own package, like ReactotronMCP, so
// ADBKit's graph stays free of swift-nio — that leanness is what lets
// `swift test` run on Windows, and the daemon must not undo it.
//
// macOS never talks to this: the Mac app keeps linking ADBKit directly, by
// decision. Nothing here can reach the shipping Mac flow.
let package = Package(
    name: "droidectived",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "droidectived", targets: ["droidectived"])
    ],
    dependencies: [
        .package(path: "../ADBKit"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
    ],
    targets: [
        // The logic lives in a library so the tests can reach it; the
        // executable is a thin `main` over `Daemon.run`.
        .target(
            name: "DaemonCore",
            dependencies: [
                .product(name: "ADBKit", package: "ADBKit"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "droidectived",
            dependencies: ["DaemonCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DaemonCoreTests",
            dependencies: ["DaemonCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
