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
        // Linked only off-Apple: swift-crypto's `Crypto` module supplies the
        // CryptoKit-compatible SHA-256 used for tool-download digest checks.
        .package(url: "https://github.com/apple/swift-crypto.git", from: "4.5.1"),
    ],
    targets: [
        // Pin the Swift 6 language mode (complete strict concurrency) explicitly
        // rather than inheriting it from the tools version, so it can't silently
        // relax if the tools-version line is ever lowered.
        //
        // ADBKit carries no unconditional dependency: Crypto links only on Linux
        // and Windows (CryptoKit covers Apple platforms), and everything MCP
        // lives in the separate ReactotronMCP target.
        .target(
            name: "ADBKit",
            dependencies: [
                .product(
                    name: "Crypto", package: "swift-crypto",
                    condition: .when(platforms: [.linux, .windows]))
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]),
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
        .testTarget(
            name: "ADBKitTests",
            dependencies: [
                "ADBKit",
                .product(
                    name: "Crypto", package: "swift-crypto",
                    condition: .when(platforms: [.linux, .windows])),
            ],
            // Recorded device fixtures are read from the source tree via
            // `#filePath`, not from a bundle, so SwiftPM should ignore them
            // rather than warn about unhandled files.
            exclude: ["Fixtures"],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(
            name: "ReactotronMCPTests",
            dependencies: ["ReactotronMCP"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
