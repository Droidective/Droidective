// swift-tools-version: 6.1
import PackageDescription

// Split out of the ADBKit package so ADBKit's own graph carries no MCP
// dependency. That is what lets `swift test` run on Windows: the MCP SDK's
// `HTTPClientTransport` imports `EventSource` under `#if !os(Linux)`, a gate
// that wrongly includes Windows, and the module is unbuildable there — so
// merely *resolving* swift-sdk broke the ADBKit test run. It also keeps the
// forthcoming `droidectived` executable on a lean graph.
//
// The whole product is Apple-only at runtime: it serves the
// Network.framework-based Reactotron relay, and every source file is gated
// behind `#if canImport(Network)`, so off-Apple the module exposes nothing.
let package = Package(
    name: "ReactotronMCP",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ReactotronMCP", targets: ["ReactotronMCP"])
    ],
    dependencies: [
        .package(path: "../ADBKit"),
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
        .target(
            name: "ReactotronMCP",
            dependencies: [
                .product(name: "ADBKit", package: "ADBKit"),
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ReactotronMCPTests",
            dependencies: ["ReactotronMCP"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
