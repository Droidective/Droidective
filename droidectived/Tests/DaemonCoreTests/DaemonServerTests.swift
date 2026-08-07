import ADBKit
import Foundation
import Testing

@testable import DaemonCore

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Drives the real HTTP stack over a real loopback socket — the
/// `McpHTTPListenerTests` pattern. A hand-rolled request builder would prove
/// the routing but not that NIO is wired up correctly, which is the part most
/// likely to be wrong.
@Suite struct DaemonServerTests {
    private struct StubBackend: DaemonBackend {
        let devices: [Device]
        func listDevices() async -> [Device] { devices }
        func runAction(
            featureID: String, serial: String, platform: DevicePlatform,
            params: [String: FeatureValue]
        ) async -> FeatureResult {
            FeatureResult(ok: true, message: "stub")
        }

        func controlApp(
            serial: String, packageId: String, action: AppControlService.AppAction
        ) async throws -> FeatureResult {
            FeatureResult(ok: true, message: "stub")
        }

        func deviceProperties(serial: String) async throws -> [String: String] {
            ["ro.product.model": "Pixel", "ro.build.version.release": "14"]
        }

        func rootStatus(serial: String) async -> RootStatus {
            RootStatus(
                hasRootShell: true, likelyRooted: true, summary: "Rooted",
                signals: [RootSignal(
                    name: "Root shell (su)", detail: "su -c id → uid=0", indicatesRoot: true)])
        }

        func listFiles(serial: String, path: String, asRoot: Bool) async throws -> [FsEntry] {
            [
                FsEntry(name: "DCIM", isDir: true, size: 4096, perms: "drwxrwx---"),
                FsEntry(name: "note.txt", isDir: false, size: 12, perms: "-rw-rw----"),
            ]
        }

        func fileOperation(
            serial: String, _ operation: FileProtocol.Operation, asRoot: Bool
        ) async throws -> FeatureResult {
            FeatureResult(ok: true, message: "stub")
        }

        func crashes(serial: String) async throws -> [CrashReport] {
            [CrashReport(
                id: "06-12 10:00:02.123|4242|java|boom", kind: .java,
                timestamp: "06-12 10:00:02.123", process: "com.example.app", pid: 4242,
                title: "java.lang.IllegalStateException: boom",
                raw: "E AndroidRuntime: boom", body: "boom")]
        }

    }

    private static func device(_ serial: String) -> Device {
        Device(
            serial: serial, state: "device", model: "Pixel", product: nil,
            transportId: nil, label: "Pixel (\(serial))", isWireless: false,
            platform: .android)
    }

    /// Boots a server on an OS-chosen port, runs `body`, always tears down.
    private func withServer(
        devices: [Device] = [DaemonServerTests.device("emulator-5554")],
        _ body: (_ port: Int, _ token: String) async throws -> Void
    ) async throws {
        let token = DaemonToken.generate()
        let server = DaemonServer(backend: StubBackend(devices: devices), token: token)
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
        port: Int, path: String = DaemonProtocol.Route.devicesList.rawValue,
        method: String = "POST", token: String?, host: String? = nil, origin: String? = nil,
        body: String? = nil
    ) async throws -> (status: Int, body: Data) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        request.httpMethod = method
        if let body { request.httpBody = Data(body.utf8) }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let host { request.setValue(host, forHTTPHeaderField: "Host") }
        if let origin { request.setValue(origin, forHTTPHeaderField: "Origin") }
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? -1, data)
    }

    @Test func bindsAnOSChosenPortSoTwoDaemonsNeverCollide() async throws {
        try await withServer { port, _ in
            #expect(port > 0)
        }
    }

    @Test func listsDevicesForAnAuthorisedRequest() async throws {
        let devices = [Self.device("emulator-5554"), Self.device("R58M12345")]
        try await withServer(devices: devices) { port, token in
            let (status, body) = try await send(port: port, token: token)
            #expect(status == 200)
            let decoded = try JSONDecoder().decode(DaemonProtocol.DevicesResponse.self, from: body)
            #expect(decoded.devices == devices)
        }
    }

    @Test func refusesAMissingOrWrongToken() async throws {
        try await withServer { port, _ in
            let missing = try await send(port: port, token: nil)
            #expect(missing.status == 401)
            let decoded = try JSONDecoder().decode(DaemonProtocol.ErrorBody.self, from: missing.body)
            #expect(decoded.error.code == "missing_token")

            let wrong = try await send(port: port, token: DaemonToken.generate())
            #expect(wrong.status == 401)
        }
    }

    @Test func refusesAForeignOrigin() async throws {
        try await withServer { port, token in
            let (status, body) = try await send(
                port: port, token: token, origin: "http://evil.example")
            #expect(status == 403)
            let decoded = try JSONDecoder().decode(DaemonProtocol.ErrorBody.self, from: body)
            #expect(decoded.error.code == "bad_origin")
        }
    }

    @Test func refusesAForeignHostHeader() async throws {
        // The DNS-rebinding shape: the socket is loopback, the Host is not.
        try await withServer { port, token in
            let (status, body) = try await send(
                port: port, token: token, host: "evil.example:\(port)")
            #expect(status == 403)
            let decoded = try JSONDecoder().decode(DaemonProtocol.ErrorBody.self, from: body)
            #expect(decoded.error.code == "bad_host")
        }
    }

    @Test func unknownRoutesAre404AndGetIs405() async throws {
        try await withServer { port, token in
            let unknown = try await send(port: port, path: "/v1/nope", token: token)
            #expect(unknown.status == 404)

            let wrongMethod = try await send(port: port, method: "GET", token: token)
            #expect(wrongMethod.status == 405)
        }
    }

    @Test func devicePropsPassesGetpropStraightThrough() async throws {
        // The daemon picks no subset: which property matters is the reader's
        // question, and a client that got a curated list could not ask it.
        try await withServer { port, token in
            let (status, body) = try await send(
                port: port, path: DaemonProtocol.Route.deviceProps.rawValue, token: token,
                body: #"{"serial":"emulator-5554"}"#)
            #expect(status == 200)
            let decoded = try JSONDecoder().decode(
                DaemonProtocol.DevicePropsResponse.self, from: body)
            #expect(decoded.properties["ro.product.model"] == "Pixel")
            #expect(decoded.properties["ro.build.version.release"] == "14")
        }
    }

    @Test func devicePropsRefusesABodyItCannotRead() async throws {
        try await withServer { port, token in
            let (status, _) = try await send(
                port: port, path: DaemonProtocol.Route.deviceProps.rawValue, token: token,
                body: "not json")
            #expect(status == 400)
        }
    }

    @Test func listsADirectoryAndEchoesThePathItRead() async throws {
        // The echo is what lets a client that has already navigated on tell a
        // late reply from the current one.
        try await withServer { port, token in
            let (status, body) = try await send(
                port: port, path: DaemonProtocol.Route.filesList.rawValue, token: token,
                body: #"{"serial":"emulator-5554","path":"/sdcard"}"#)
            #expect(status == 200)
            let decoded = try JSONDecoder().decode(FileProtocol.ListResponse.self, from: body)
            #expect(decoded.path == "/sdcard")
            #expect(decoded.entries.map(\.name) == ["DCIM", "note.txt"])
            #expect(decoded.entries.first?.isDir == true)
        }
    }

    @Test func theRootProbeCarriesItsSignalsNotJustTheVerdict() async throws {
        try await withServer { port, token in
            let (status, body) = try await send(
                port: port, path: DaemonProtocol.Route.deviceRoot.rawValue, token: token,
                body: #"{"serial":"emulator-5554"}"#)
            #expect(status == 200)
            let decoded = try JSONDecoder().decode(
                DaemonProtocol.RootStatusResponse.self, from: body)
            #expect(decoded.hasRootShell)
            #expect(decoded.signals.first?.name == "Root shell (su)")
        }
    }

    @Test func aPullAnswersWhereTheFileLanded() async throws {
        try await withServer { port, token in
            let (status, body) = try await send(
                port: port, path: DaemonProtocol.Route.filesPull.rawValue, token: token,
                body: #"{"serial":"emulator-5554","path":"/sdcard/note.txt","destination":"/tmp/note.txt"}"#)
            #expect(status == 200)
            let decoded = try JSONDecoder().decode(FileProtocol.PullResponse.self, from: body)
            #expect(decoded.path == "/tmp/note.txt")
        }
    }

    @Test func listsTheDevicesCrashes() async throws {
        try await withServer { port, token in
            let (status, body) = try await send(
                port: port, path: DaemonProtocol.Route.crashesList.rawValue, token: token,
                body: #"{"serial":"emulator-5554"}"#)
            #expect(status == 200)
            let decoded = try JSONDecoder().decode(CrashProtocol.ListResponse.self, from: body)
            #expect(decoded.crashes.first?.process == "com.example.app")
            #expect(decoded.crashes.first?.kind == "java")
        }
    }

    @Test func everyRouteIsReachable() async throws {
        // The registry-invariant pattern: a route added to the table but never
        // wired into the handler would answer 404 and nobody would notice.
        try await withServer { port, token in
            for route in DaemonProtocol.Route.allCases {
                let (status, _) = try await send(port: port, path: route.rawValue, token: token)
                // Reachable, not necessarily satisfied: routes that need a body
                // answer 400 to this empty probe, and that still proves they
                // are wired. Only 404/405 mean the table and the handler have
                // drifted apart, which is what this guards.
                #expect(
                    status != 404 && status != 405,
                    "\(route.rawValue) is in the table but not routed (\(status))")
            }
        }
    }
}
