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
        method: String = "POST", token: String?, host: String? = nil, origin: String? = nil
    ) async throws -> (status: Int, body: Data) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        request.httpMethod = method
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
