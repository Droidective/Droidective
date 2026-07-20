// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "ADBKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ADBKit", targets: ["ADBKit"]),
        .library(name: "ReactotronMCP", targets: ["ReactotronMCP"]),
    ],
    dependencies: [
        // Pre-1.0 SDK: pinned exactly; upgrades are deliberate, reviewed
        // changes (re-run the MCP socket/contract suites after bumping).
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"),
        // HTTP listener for the MCP endpoint — the same stack the SDK's own
        // conformance server uses. Version graph is pinned by Package.resolved.
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
    ],
    targets: [
        // Pin the Swift 6 language mode (complete strict concurrency) explicitly
        // rather than inheriting it from the tools version, so it can't silently
        // relax if the tools-version line is ever lowered.
        // ADBKit stays dependency-free: everything MCP lives in ReactotronMCP.
        .target(name: "ADBKit", swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(
            name: "ReactotronMCP",
            dependencies: [
                "ADBKit",
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(name: "ADBKitTests", dependencies: ["ADBKit"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(
            name: "ReactotronMCPTests",
            dependencies: ["ReactotronMCP"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
