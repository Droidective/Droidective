import ADBKit
import Foundation
import Testing

@testable import DaemonCore

/// The crash routes without a socket.
///
/// What matters here is that the daemon stays a pass-through: `CrashExtractor`
/// decides which buffer to read and `CrashParser` where one crash ends, and the
/// wire must carry that answer intact rather than reshaping it. A client that
/// re-derived any of it would eventually disagree with the Mac about how many
/// crashes a device has.
@Suite struct CrashRouteTests {
    private struct Refusal: Error, CustomStringConvertible {
        let description: String
    }

    private actor CallLog {
        private(set) var cleared: [String] = []
        func recordClear(_ serial: String) { cleared.append(serial) }
    }

    private struct StubBackend: DaemonBackend {
        let log: CallLog
        var reports: [CrashReport] = []
        var refusal: Refusal?

        func crashes(serial: String) async throws -> [CrashReport] {
            if let refusal { throw refusal }
            return reports
        }

        func clearCrashBuffer(serial: String) async throws {
            if let refusal { throw refusal }
            await log.recordClear(serial)
        }
    }

    /// A real Java crash, split by the real parser — so the DTO is exercised
    /// against what a device actually produces rather than a hand-built value
    /// that could quietly disagree with `CrashReport`.
    private static let javaCrash = """
        06-12 10:00:02.123  4242  4242 E AndroidRuntime: FATAL EXCEPTION: main
        06-12 10:00:02.123  4242  4242 E AndroidRuntime: Process: com.example.app, PID: 4242
        06-12 10:00:02.123  4242  4242 E AndroidRuntime: java.lang.IllegalStateException: boom
        06-12 10:00:02.123  4242  4242 E AndroidRuntime: \tat com.example.app.Main.run(Main.java:9)
        """

    private func backend(
        _ text: String = javaCrash, refusal: Refusal? = nil
    ) -> (StubBackend, CallLog) {
        let log = CallLog()
        return (
            StubBackend(
                log: log, reports: CrashParser.parse(text, source: .crashBuffer),
                refusal: refusal),
            log
        )
    }

    private func json(_ body: String) -> Data { Data(body.utf8) }

    @Test func aCrashSurvivesTheWireWithEverythingAListRowNeeds() async throws {
        let (stub, _) = backend()
        let answer = await CrashRoutes.list(
            body: json(#"{"serial":"emulator-5554"}"#), backend: stub)
        #expect(answer.status == 200)

        let decoded = try JSONDecoder().decode(
            CrashProtocol.ListResponse.self, from: answer.body)
        let crash = try #require(decoded.crashes.first)
        #expect(crash.kind == "java")
        #expect(crash.title == "java.lang.IllegalStateException: boom")
        #expect(crash.process == "com.example.app")
        #expect(crash.pid == 4242)
        #expect(crash.timestamp == "06-12 10:00:02.123")
        // Both renderings travel: the Raw log toggle switches between them, and
        // re-deriving one from the other client-side means re-implementing the
        // threadtime prefix strip.
        #expect(crash.body.contains("FATAL EXCEPTION: main"))
        #expect(crash.raw.contains("E AndroidRuntime:"))
        #expect(!crash.body.contains("E AndroidRuntime:"))
    }

    @Test func theKindsLabelTravelsRatherThanBeingReimplemented() async throws {
        // The same reason `AppSummary.displayName` is sent: a client with its
        // own copy of the mapping drifts from the one the Mac shows.
        let (stub, _) = backend()
        let answer = await CrashRoutes.list(
            body: json(#"{"serial":"S1"}"#), backend: stub)
        let decoded = try JSONDecoder().decode(
            CrashProtocol.ListResponse.self, from: answer.body)
        #expect(decoded.crashes.first?.kindLabel == CrashReport.Kind.java.label)
    }

    @Test func everyKindRoundTripsItsRawValue() throws {
        // A kind added to the enum but spelled differently on the wire would
        // land in the client's "unknown" bucket without anything failing.
        for kind in CrashReport.Kind.allCases {
            let report = CrashProtocol.Report(
                CrashReport(
                    id: "1", kind: kind, timestamp: nil, process: nil, pid: nil,
                    title: "t", raw: "r", body: "b"))
            #expect(CrashReport.Kind(rawValue: report.kind) == kind)
            #expect(!report.kindLabel.isEmpty)
        }
    }

    @Test func anEmptyBufferIsAnEmptyListNotAnError() async throws {
        let (stub, _) = backend("")
        let answer = await CrashRoutes.list(
            body: json(#"{"serial":"S1"}"#), backend: stub)
        #expect(answer.status == 200)
        let decoded = try JSONDecoder().decode(
            CrashProtocol.ListResponse.self, from: answer.body)
        #expect(decoded.crashes.isEmpty)
    }

    @Test func clearingEmptiesTheBufferAndSaysSo() async throws {
        let (stub, log) = backend()
        let answer = await CrashRoutes.clear(
            body: json(#"{"serial":"emulator-5554"}"#), backend: stub)
        #expect(answer.status == 200)
        let decoded = try JSONDecoder().decode(ActionProtocol.RunResponse.self, from: answer.body)
        #expect(decoded.ok)
        #expect(await log.cleared == ["emulator-5554"])
    }

    @Test func aDeviceRefusalIsA502CarryingAdbsOwnWords() async throws {
        let (stub, _) = backend(refusal: Refusal(description: "adb: device offline"))
        for answer in await [
            CrashRoutes.list(body: json(#"{"serial":"S1"}"#), backend: stub),
            CrashRoutes.clear(body: json(#"{"serial":"S1"}"#), backend: stub),
        ] {
            #expect(answer.status == 502)
            let decoded = try JSONDecoder().decode(
                DaemonProtocol.ErrorBody.self, from: answer.body)
            #expect(decoded.error.code == "adb_failed")
            #expect(decoded.error.detail?.contains("device offline") == true)
        }
    }

    @Test func aBodyTheRouteCannotReadIsABadRequest() async throws {
        let (stub, log) = backend()
        for answer in await [
            CrashRoutes.list(body: json("not json"), backend: stub),
            CrashRoutes.clear(body: json("not json"), backend: stub),
        ] {
            #expect(answer.status == 400)
        }
        #expect(await log.cleared.isEmpty)
    }
}
