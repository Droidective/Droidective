import Foundation
import Testing
@testable import ADBKit

@Suite struct ScrcpyServerLocatorTests {
    @Test func derivesJarPathFromHomebrewBinary() {
        #expect(ScrcpyServerLocator.jarPath(forBinary: "/opt/homebrew/bin/scrcpy")
            == "/opt/homebrew/share/scrcpy/scrcpy-server")
        #expect(ScrcpyServerLocator.jarPath(forBinary: "/usr/local/bin/scrcpy")
            == "/usr/local/share/scrcpy/scrcpy-server")
    }

    @Test func parsesVersionFromBanner() {
        #expect(ScrcpyServerLocator.parseVersion("scrcpy 4.0 <https://github.com/Genymobile/scrcpy>") == "4.0")
        // The real banner is multi-line; the version is on the first line.
        #expect(ScrcpyServerLocator.parseVersion("scrcpy 2.7\nDependencies (compiled / linked):") == "2.7")
    }

    @Test func returnsNilForUnparseableBanner() {
        #expect(ScrcpyServerLocator.parseVersion("") == nil)
        #expect(ScrcpyServerLocator.parseVersion("not scrcpy output") == nil)
        #expect(ScrcpyServerLocator.parseVersion("scrcpy") == nil)
    }
}

/// The bundled jar's version, against the Mac's own copy of the same fact.
///
/// A cross-file invariant rather than review folklore: the two constants
/// describe one committed file, and a mismatch does not degrade — the
/// device-side server aborts, so the mirror simply never starts.
@Suite struct BundledScrcpyVersionTests {
    @Test func bundledVersionMatchesTheMacsOwn() throws {
        // Located from `#filePath` the way `PortabilityGuardTests` does, so the
        // suite carries no assumption about where it was run from.
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // ADBKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // the package root
            .deletingLastPathComponent()  // the repository
        let bundledTools = repository
            .appendingPathComponent("App/Sources/Bundled/BundledTools.swift")

        // The Mac's half is not in this package, so a checkout without it (a
        // Linux CI job cloning only what it builds) skips rather than fails.
        guard let source = try? String(contentsOf: bundledTools, encoding: .utf8) else { return }

        let pattern = #"scrcpyVersion\s*=\s*"([^"]+)""#
        let match = source.range(of: pattern, options: .regularExpression)
        let declaration = try #require(match.map { String(source[$0]) })
        #expect(
            declaration.contains("\"\(ScrcpyServerLocator.bundledVersion)\""),
            """
            BundledTools.scrcpyVersion and ScrcpyServerLocator.bundledVersion \
            describe the same committed jar and have parted company: \
            \(declaration) vs "\(ScrcpyServerLocator.bundledVersion)".
            """)
    }

    @Test func bundledInfoCarriesThePathItWasGiven() {
        let info = ScrcpyServerLocator.bundled(jarPath: "/opt/app/scrcpy-server")
        #expect(info.jarPath == "/opt/app/scrcpy-server")
        #expect(info.version == ScrcpyServerLocator.bundledVersion)
    }
}
