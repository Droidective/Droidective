// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "ADBKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ADBKit", targets: ["ADBKit"])
    ],
    dependencies: [
        // The only dependency, and it links only off-Apple: swift-crypto's
        // `Crypto` module supplies the CryptoKit-compatible SHA-256 used for
        // tool-download digest checks.
        //
        // Everything MCP lives in the sibling `ReactotronMCP` package rather
        // than a target here, so this graph stays free of swift-sdk and
        // swift-nio. That is load-bearing for the port: the MCP SDK's
        // `HTTPClientTransport` imports `EventSource` behind `#if !os(Linux)`,
        // a gate that wrongly includes Windows where the module is
        // unbuildable — so merely resolving swift-sdk broke `swift test` on
        // Windows even though nothing there uses MCP.
        .package(url: "https://github.com/apple/swift-crypto.git", from: "4.5.1")
    ],
    targets: [
        // Pin the Swift 6 language mode (complete strict concurrency) explicitly
        // rather than inheriting it from the tools version, so it can't silently
        // relax if the tools-version line is ever lowered.
        .target(
            name: "ADBKit",
            dependencies: [
                .product(
                    name: "Crypto", package: "swift-crypto",
                    condition: .when(platforms: [.linux, .windows]))
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]),
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
    ]
)
