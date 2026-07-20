// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ADBKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ADBKit", targets: ["ADBKit"])
    ],
    dependencies: [
        // Linked only off-Apple: swift-crypto's `Crypto` module supplies the
        // CryptoKit-compatible SHA-256 used for tool-download digest checks.
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
            swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)
