import ADBKit
import Foundation
import Testing

@testable import DaemonCore

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The Command Log: the two routes, and — the part worth the socket — that the
/// task-local scope really reaches the backend, since that is the whole
/// mechanism by which anything gets recorded at all.
@Suite struct CommandLogRouteTests {
    /// Reports what `CommandLog.isUserInitiated` was when the route ran, which
    /// is exactly what `AdbClient.run` reads to decide whether to record.
    private actor Witness {
        private(set) var sawUserInitiated: [Bool] = []
        private(set) var cleared = 0
        var entries: [CommandLogEntry] = []

        func note(_ value: Bool) { sawUserInitiated.append(value) }
        func noteClear() { cleared += 1 }
        func setEntries(_ value: [CommandLogEntry]) { entries = value }
    }

    private struct WitnessBackend: DaemonBackend {
        let witness: Witness

        func listDevices() async -> [Device] {
            await witness.note(CommandLog.isUserInitiated)
            return []
        }

        func commandLog() async -> [CommandLogEntry] {
            await witness.note(CommandLog.isUserInitiated)
            return await witness.entries
        }

        func clearCommandLog() async {
            await witness.noteClear()
        }
    }

    private func withServer(
        witness: Witness, _ body: (_ port: Int, _ token: String) async throws -> Void
    ) async throws {
        let token = DaemonToken.generate()
        let server = DaemonServer(backend: WitnessBackend(witness: witness), token: token)
        let bound = try await server.start(port: 0)
        do {
            try await body(bound.port, token)
        } catch {
            await server.stop()
            throw error
        }
        await server.stop()
    }

    private func send(
        port: Int, path: String, token: String, background: String? = nil
    ) async throws -> (status: Int, body: Data) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let background {
            request.setValue(background, forHTTPHeaderField: CommandLogProtocol.header)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? -1, data)
    }

    // MARK: - The header rule

    @Test func anUnmarkedRequestIsRecorded() async throws {
        // Absent means recorded, deliberately: a forgotten header on a poll is
        // visible noise, where the opposite default loses an action silently.
        let witness = Witness()
        try await withServer(witness: witness) { port, token in
            let (status, _) = try await send(
                port: port, path: DaemonProtocol.Route.devicesList.rawValue, token: token)
            #expect(status == 200)
        }
        #expect(await witness.sawUserInitiated == [true])
    }

    @Test func aBackgroundRequestIsNotRecorded() async throws {
        let witness = Witness()
        try await withServer(witness: witness) { port, token in
            _ = try await send(
                port: port, path: DaemonProtocol.Route.devicesList.rawValue, token: token,
                background: "1")
        }
        #expect(await witness.sawUserInitiated == [false])
    }

    @Test func anExplicitlyFalseHeaderIsStillRecorded() async throws {
        // A client that computes the header from a boolean sends "false" for a
        // user action rather than omitting it; that must not silence the log.
        let witness = Witness()
        try await withServer(witness: witness) { port, token in
            _ = try await send(
                port: port, path: DaemonProtocol.Route.devicesList.rawValue, token: token,
                background: "false")
        }
        #expect(await witness.sawUserInitiated == [true])
    }

    @Test(arguments: [
        (nil as String?, false),
        ("", false),
        ("0", false),
        ("false", false),
        ("False", false),
        ("  0  ", false),
        ("1", true),
        ("true", true),
        ("yes", true),
    ])
    func classifiesTheHeader(value: String?, expected: Bool) {
        #expect(CommandLogProtocol.isBackground(value) == expected)
    }

    // MARK: - The two routes

    @Test func listsTheLogMostRecentFirst() async throws {
        let witness = Witness()
        await witness.setEntries([
            Self.entry(command: "adb -s emulator-5554 shell input text hi", exitCode: 0),
            Self.entry(command: "adb devices", exitCode: 1),
        ])
        try await withServer(witness: witness) { port, token in
            let (status, body) = try await send(
                port: port, path: DaemonProtocol.Route.commandLogList.rawValue, token: token)
            #expect(status == 200)
            let decoded = try JSONDecoder().decode(
                CommandLogProtocol.ListResponse.self, from: body)
            #expect(decoded.entries.map(\.command) == [
                "adb -s emulator-5554 shell input text hi", "adb devices",
            ])
            #expect(decoded.entries.map(\.exitCode) == [0, 1])
        }
    }

    @Test func clearingAnswersOkAndReachesTheLog() async throws {
        let witness = Witness()
        try await withServer(witness: witness) { port, token in
            let (status, body) = try await send(
                port: port, path: DaemonProtocol.Route.commandLogClear.rawValue, token: token)
            #expect(status == 200)
            let decoded = try JSONDecoder().decode(ActionProtocol.RunResponse.self, from: body)
            #expect(decoded.ok)
        }
        #expect(await witness.cleared == 1)
    }

    // MARK: - The wire shape

    @Test func convertsADurationToWholeMilliseconds() {
        let entry = CommandLogProtocol.Entry(
            Self.entry(command: "adb devices", exitCode: 0, duration: .milliseconds(1250)))
        #expect(entry.durationMs == 1250)
    }

    @Test func convertsSubMillisecondAndMultiSecondDurations() {
        // The Mac's `exitLabel` sums both components; a duration under a
        // millisecond must not become a negative or a rounded-up number.
        #expect(CommandLogProtocol.Entry.milliseconds(.microseconds(400)) == 0)
        #expect(CommandLogProtocol.Entry.milliseconds(.seconds(3) + .milliseconds(7)) == 3007)
    }

    @Test func aKilledProcessCarriesNoExitCode() {
        // `CommandLogRow` renders a nil exit code as "killed"; the wire has to
        // preserve the distinction rather than substituting a number.
        let entry = CommandLogProtocol.Entry(
            Self.entry(command: "adb shell sleep 99", exitCode: nil))
        #expect(entry.exitCode == nil)
    }

    @Test func carriesTheTimestampAsEpochMilliseconds() {
        let when = Date(timeIntervalSince1970: 1_700_000_000.5)
        let entry = CommandLogProtocol.Entry(CommandLogEntry(
            id: UUID(), timestamp: when, command: "adb devices", exitCode: 0,
            duration: .zero, stdout: "", stderr: ""))
        #expect(entry.at == 1_700_000_000_500)
    }

    private static func entry(
        command: String, exitCode: Int32?, duration: Duration = .milliseconds(12)
    ) -> CommandLogEntry {
        CommandLogEntry(
            id: UUID(), timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            command: command, exitCode: exitCode, duration: duration,
            stdout: "out", stderr: "")
    }
}
