import Foundation
import Testing

@testable import DaemonCore

/// The guards are the security boundary, so they are tested directly rather
/// than only through the socket suite below.
@Suite struct DaemonGuardsTests {
    /// Generated rather than a literal: a fixed hex string here trips the
    /// repo's gitleaks hook as a generic API key. Stable within a test, since
    /// swift-testing builds a fresh suite instance per test.
    private let token = DaemonToken.generate()

    // MARK: token

    @Test func acceptsTheExactBearerToken() {
        #expect(DaemonGuards.checkAuthorization(header: "Bearer \(token)", expected: token) == nil)
    }

    @Test func rejectsAMissingOrMalformedHeader() {
        #expect(DaemonGuards.checkAuthorization(header: nil, expected: token) == .missingToken)
        #expect(DaemonGuards.checkAuthorization(header: "", expected: token) == .missingToken)
        // The scheme matters: a bare token is not a bearer credential.
        #expect(DaemonGuards.checkAuthorization(header: token, expected: token) == .missingToken)
        #expect(
            DaemonGuards.checkAuthorization(header: "Basic \(token)", expected: token)
                == .missingToken)
    }

    @Test func rejectsAWrongToken() {
        #expect(DaemonGuards.checkAuthorization(header: "Bearer nope", expected: token) == .badToken)
        // A correct prefix must not pass — the comparison is whole-string.
        #expect(
            DaemonGuards.checkAuthorization(
                header: "Bearer \(token.dropLast())", expected: token) == .badToken)
        #expect(
            DaemonGuards.checkAuthorization(header: "Bearer \(token)x", expected: token)
                == .badToken)
    }

    @Test func constantTimeCompareStillAnswersCorrectly() {
        // Timing is not observable from a unit test; correctness is, and a
        // hand-rolled compare is exactly where an off-by-one hides.
        #expect(DaemonGuards.constantTimeEquals("", ""))
        #expect(DaemonGuards.constantTimeEquals("a", "a"))
        #expect(!DaemonGuards.constantTimeEquals("a", "b"))
        #expect(!DaemonGuards.constantTimeEquals("a", "aa"))
        #expect(!DaemonGuards.constantTimeEquals("aa", "a"))
        #expect(DaemonGuards.constantTimeEquals("é-ünïcode", "é-ünïcode"))
        #expect(!DaemonGuards.constantTimeEquals("é-ünïcode", "e-unicode"))
    }

    // MARK: host

    @Test func acceptsLoopbackHostOnTheBoundPort() {
        #expect(DaemonGuards.checkHost(header: "127.0.0.1:54123", port: 54123) == nil)
        #expect(DaemonGuards.checkHost(header: "localhost:54123", port: 54123) == nil)
        #expect(DaemonGuards.checkHost(header: "LocalHost:54123", port: 54123) == nil)
        #expect(DaemonGuards.checkHost(header: "[::1]:54123", port: 54123) == nil)
    }

    @Test func rejectsAForeignOrMisportedHost() {
        // The DNS-rebinding shape: a name that resolves to loopback but is not
        // one of ours.
        #expect(DaemonGuards.checkHost(header: "evil.example:54123", port: 54123) == .badHost)
        #expect(DaemonGuards.checkHost(header: "127.0.0.1:1", port: 54123) == .badHost)
        #expect(DaemonGuards.checkHost(header: "127.0.0.1", port: 54123) == .badHost)
        #expect(DaemonGuards.checkHost(header: nil, port: 54123) == .badHost)
    }

    // MARK: origin

    @Test func absentOriginIsAllowedBecauseNativeClientsSendNone() {
        #expect(DaemonGuards.checkOrigin(header: nil) == nil)
        #expect(DaemonGuards.checkOrigin(header: "") == nil)
    }

    @Test func acceptsALoopbackOrigin() {
        #expect(DaemonGuards.checkOrigin(header: "http://localhost:1420") == nil)
        #expect(DaemonGuards.checkOrigin(header: "http://127.0.0.1:5173") == nil)
        #expect(DaemonGuards.checkOrigin(header: "https://localhost") == nil)
        #expect(DaemonGuards.checkOrigin(header: "http://[::1]:8080") == nil)
    }

    @Test func rejectsAForeignOrigin() {
        #expect(DaemonGuards.checkOrigin(header: "http://evil.example") == .badOrigin)
        #expect(DaemonGuards.checkOrigin(header: "https://evil.example:1420") == .badOrigin)
        // A hostname that merely starts with a loopback name is not loopback.
        #expect(DaemonGuards.checkOrigin(header: "http://localhost.evil.example") == .badOrigin)
        #expect(DaemonGuards.checkOrigin(header: "null") == .badOrigin)
    }

    // MARK: order

    @Test func transportChecksRunBeforeTheSecret() {
        // A foreign origin must not learn whether its token guess was right,
        // so the shape checks answer first.
        let refusal = DaemonGuards.check(
            authorization: "Bearer \(token)", host: "evil.example:1", origin: "http://evil.example",
            port: 54123, expectedToken: token)
        #expect(refusal == .badHost)
    }

    @Test func aFullyValidRequestPasses() {
        #expect(
            DaemonGuards.check(
                authorization: "Bearer \(token)", host: "127.0.0.1:54123",
                origin: nil, port: 54123, expectedToken: token) == nil)
    }
}

@Suite struct DaemonOptionsTests {
    @Test func defaultsToAnOSChosenPort() throws {
        #expect(try DaemonOptions.parse([]) == DaemonOptions(port: 0))
    }

    @Test func parsesEveryFlag() throws {
        let parsed = try DaemonOptions.parse([
            "--port", "5000", "--token-file", "/tmp/t", "--parent-pid", "42",
            "--scrcpy-server", "/opt/app/scrcpy-server",
        ])
        #expect(
            parsed
                == DaemonOptions(
                    port: 5000, tokenFile: "/tmp/t", parentPID: 42,
                    scrcpyServer: "/opt/app/scrcpy-server"))
    }

    @Test func theBundledServerIsOptional() throws {
        // A daemon someone started by hand has no bundle to point at, and falls
        // back to an installed scrcpy rather than refusing to run.
        #expect(try DaemonOptions.parse([]).scrcpyServer == nil)
    }

    @Test func aBundledServerPathNeedsAValue() {
        #expect(throws: DaemonOptions.ParseError.missingValue("--scrcpy-server")) {
            try DaemonOptions.parse(["--scrcpy-server"])
        }
    }

    @Test func rejectsBadInputLoudlyRatherThanDefaulting() {
        #expect(throws: DaemonOptions.ParseError.missingValue("--port")) {
            try DaemonOptions.parse(["--port"])
        }
        #expect(throws: DaemonOptions.ParseError.notANumber(flag: "--port", value: "abc")) {
            try DaemonOptions.parse(["--port", "abc"])
        }
        #expect(throws: DaemonOptions.ParseError.portOutOfRange(70000)) {
            try DaemonOptions.parse(["--port", "70000"])
        }
        // A typo in the UI's spawn arguments must fail at startup, not run on
        // silent defaults.
        #expect(throws: DaemonOptions.ParseError.unknownFlag("--prot")) {
            try DaemonOptions.parse(["--prot", "5000"])
        }
    }
}

@Suite struct DaemonTokenTests {
    @Test func generatesA64CharHexSecret() {
        let token = DaemonToken.generate()
        #expect(token.count == 64)
        #expect(token.allSatisfy { $0.isHexDigit && $0.isASCII })
    }

    @Test func successiveTokensDiffer() {
        #expect(DaemonToken.generate() != DaemonToken.generate())
    }

    @Test func writesTheTokenOwnerOnly() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("droidectived-token-\(UUID().uuidString)").path
        let token = DaemonToken.generate()
        let restricted = try DaemonToken.write(token, to: path)

        #expect(try String(contentsOfFile: path, encoding: .utf8) == token)
        #if !os(Windows)
        #expect(restricted)
        let mode = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        #expect(mode == 0o600, "the shared secret must not be world-readable")
        #endif
        try? FileManager.default.removeItem(atPath: path)
    }
}

@Suite struct ParentWatchTests {
    @Test func seesItsOwnProcessAsAlive() {
        #expect(ParentWatch.isAlive(ProcessInfo.processInfo.processIdentifier))
    }

    @Test func reportsAnImpossiblePIDAsGone() {
        // Nothing is ever pid 0 in the sense we mean, and a huge id will not
        // exist. Either way the daemon must decide "parent gone" and exit
        // rather than linger holding adb children.
        #expect(!ParentWatch.isAlive(Int32.max))
    }
}
