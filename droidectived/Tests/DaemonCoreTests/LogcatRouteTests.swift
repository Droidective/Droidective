import ADBKit
import Foundation
import Testing

@testable import DaemonCore

/// `/v1/logcat/pid` over a real socket.
///
/// The route exists so a log client can narrow to one app. What it must get
/// right is the *absent* answer: an app that is not running is the ordinary
/// state of one whose log you opened first, and a client that saw a 502 there
/// would report a failure instead of waiting for the launch.
@Suite struct LogcatRouteTests {
    private actor CallLog {
        private(set) var asked: [(serial: String, packageId: String)] = []
        func record(_ serial: String, _ packageId: String) {
            asked.append((serial, packageId))
        }
    }

    private struct Refusal: Error, CustomStringConvertible {
        let description = "device offline"
    }

    private struct StubBackend: DaemonBackend {
        let log: CallLog
        var refuse = false

        func logcatPid(serial: String, packageId: String) async throws -> Int? {
            await log.record(serial, packageId)
            if refuse { throw Refusal() }
            // The one package the fake device is running, so "not running" and
            // "running" are both reachable without a second stub.
            return packageId == "com.example.weather" ? 4211 : nil
        }
    }

    private func withServer(
        refuse: Bool = false,
        _ body: (_ port: Int, _ token: String, _ log: CallLog) async throws -> Void
    ) async throws {
        let token = DaemonToken.generate()
        let log = CallLog()
        let server = DaemonServer(
            backend: StubBackend(log: log, refuse: refuse), token: token)
        let bound = try await server.start(port: 0)
        do { try await body(bound.port, token, log) } catch {
            await server.stop()
            throw error
        }
        await server.stop()
    }

    private func post(
        port: Int, token: String, json: String
    ) async throws -> (status: Int, body: String) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/logcat/pid")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data(json.utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        return (
            (response as? HTTPURLResponse)?.statusCode ?? -1,
            String(decoding: data, as: UTF8.self)
        )
    }

    @Test func namesThePidOfARunningApp() async throws {
        try await withServer { port, token, log in
            let (status, body) = try await self.post(
                port: port, token: token,
                json: #"{"serial":"S1","packageId":"com.example.weather"}"#)
            #expect(status == 200)
            #expect(body.contains(#""pid":4211"#))
            #expect(await log.asked.first?.serial == "S1")
            #expect(await log.asked.first?.packageId == "com.example.weather")
        }
    }

    /// The case the whole design turns on. An omitted key rather than an
    /// explicit null, which is this protocol's convention throughout — a client
    /// reads a missing `pid` as "not running yet" and waits.
    @Test func anAppThatIsNotRunningIsAnAnswerRatherThanAFailure() async throws {
        try await withServer { port, token, _ in
            let (status, body) = try await self.post(
                port: port, token: token,
                json: #"{"serial":"S1","packageId":"com.example.notlaunched"}"#)
            #expect(status == 200)
            #expect(body == "{}")
            #expect(!body.contains("pid"))
        }
    }

    /// A device that genuinely refused is a different thing from an app that is
    /// not running, and collapsing the two would make the client wait forever
    /// for an app on a device that has gone away.
    @Test func aRefusedDeviceIsReportedAsAFailure() async throws {
        try await withServer(refuse: true) { port, token, _ in
            let (status, body) = try await self.post(
                port: port, token: token,
                json: #"{"serial":"S1","packageId":"com.example.weather"}"#)
            #expect(status == 502)
            #expect(body.contains("adb_failed"))
            #expect(body.contains("device offline"))
        }
    }

    @Test func rejectsABodyMissingItsPackage() async throws {
        try await withServer { port, token, log in
            let (status, _) = try await self.post(
                port: port, token: token, json: #"{"serial":"S1"}"#)
            #expect(status == 400)
            // Refused before the device was touched.
            #expect(await log.asked.isEmpty)
        }
    }

    @Test func refusesAnUnauthenticatedCaller() async throws {
        try await withServer { port, _, log in
            let (status, _) = try await self.post(
                port: port, token: "not-the-token",
                json: #"{"serial":"S1","packageId":"com.example.weather"}"#)
            #expect(status == 401)
            #expect(await log.asked.isEmpty)
        }
    }
}
