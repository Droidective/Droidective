import ADBKit
import Foundation
import Testing

@testable import DaemonCore

/// The Tailscale routes without adb or a tailnet.
///
/// What the routes add over `TailscaleService` is the wire: a phone adb
/// already lists is not offered again, the security warning travels rather
/// than being restated by the client, and a connect is refused anything that
/// is not a tailnet address.
@Suite struct TailscaleRouteTests {
    private struct Unreachable: Error, LocalizedError {
        var errorDescription: String? { "adb not found." }
    }

    private actor CallLog {
        private(set) var calls: [String] = []
        func record(_ call: String) { calls.append(call) }
    }

    private struct StubBackend: DaemonBackend {
        let log = CallLog()
        var status: TailscaleStatus? = TailscaleStatus(
            flavor: .appBundle, backendState: "Running",
            androidPeers: [
                TailscalePeer(id: "nGALAXY", name: "galaxy-s24", ipv4: "100.88.0.9"),
                TailscalePeer(id: "nPIXEL", name: "pixel-7", ipv4: "100.101.102.103"),
            ])
        var devices: [Device] = [
            Device(serial: "100.101.102.103:5555", state: "device", model: "Pixel 7",
                   product: nil, transportId: nil, label: "Pixel 7", isWireless: true),
        ]
        var unreachable = false

        func tailscaleStatus() async -> TailscaleStatus? { status }

        func listDevices() async -> [Device] {
            await log.record("devices")
            return devices
        }

        func connectTailscale(_ peer: TailscalePeer) async throws -> FeatureResult {
            if unreachable { throw Unreachable() }
            await log.record("connect \(peer.ipv4)")
            return FeatureResult(ok: true, message: "Connected to \(peer.name) over Tailscale")
        }

        func prepareForTailscale(serial: String) async throws -> FeatureResult {
            if unreachable { throw Unreachable() }
            await log.record("prepare \(serial)")
            return FeatureResult(ok: false, message: "Device is unauthorized.")
        }
    }

    @Test func statusOffersOnlyPeersAdbDoesNotListYet() async throws {
        let (code, body) = await TailscaleRoutes.status(backend: StubBackend())
        #expect(code == 200)
        let status = try JSONDecoder().decode(TailscaleProtocol.Status.self, from: body)
        #expect(status.installed)
        #expect(status.flavor == "appBundle")
        #expect(status.running)
        #expect(status.notice == nil)
        #expect(status.peers.map(\.name) == ["galaxy-s24"])
        #expect(status.prepareWarning == TailscaleService.prepareWarning)
    }

    @Test func noCLIIsNotInstalledAndAsksAdbNothing() async throws {
        let backend = StubBackend(status: nil)
        let (code, body) = await TailscaleRoutes.status(backend: backend)
        #expect(code == 200)
        let status = try JSONDecoder().decode(TailscaleProtocol.Status.self, from: body)
        #expect(!status.installed)
        #expect(status.peers.isEmpty)
        #expect(await backend.log.calls.isEmpty)
    }

    @Test func aStoppedTailnetCarriesItsNotice() async throws {
        let backend = StubBackend(
            status: TailscaleStatus(flavor: .standalone, backendState: "Stopped", androidPeers: []))
        let (_, body) = await TailscaleRoutes.status(backend: backend)
        let status = try JSONDecoder().decode(TailscaleProtocol.Status.self, from: body)
        #expect(!status.running)
        #expect(status.notice == "Tailscale is stopped")
    }

    @Test func connectTakesThePeerAsTheStatusSentIt() async throws {
        let backend = StubBackend()
        let peer = DaemonProtocol.encoded(
            TailscalePeer(id: "nGALAXY", name: "galaxy-s24", ipv4: "100.88.0.9"))
        let (code, body) = await TailscaleRoutes.connect(body: peer, backend: backend)
        #expect(code == 200)
        let result = try JSONDecoder().decode(ActionProtocol.RunResponse.self, from: body)
        #expect(result.ok)
        #expect(result.message == "Connected to galaxy-s24 over Tailscale")
        #expect(await backend.log.calls == ["connect 100.88.0.9"])
    }

    @Test func connectRefusesAnAddressOffTheTailnet() async throws {
        let backend = StubBackend()
        for ipv4 in ["192.168.1.20", "100.128.0.1", "pixel-7.example.ts.net", ""] {
            let peer = DaemonProtocol.encoded(TailscalePeer(id: "n", name: "x", ipv4: ipv4))
            let (code, body) = await TailscaleRoutes.connect(body: peer, backend: backend)
            #expect(code == 400, "\(ipv4) was accepted")
            let error = try JSONDecoder().decode(DaemonProtocol.ErrorBody.self, from: body)
            #expect(error.error.code == "bad_tailscale_peer")
        }
        #expect(await backend.log.calls.isEmpty)
    }

    @Test func prepareRunsOnTheNamedDeviceAndARefusalIsA200() async throws {
        let backend = StubBackend()
        let request = DaemonProtocol.encoded(DaemonProtocol.DeviceRequest(serial: "R58M123ABC"))
        let (code, body) = await TailscaleRoutes.prepare(body: request, backend: backend)
        #expect(code == 200)
        let result = try JSONDecoder().decode(ActionProtocol.RunResponse.self, from: body)
        #expect(!result.ok)
        #expect(await backend.log.calls == ["prepare R58M123ABC"])
    }

    @Test func malformedBodiesAre400sAndAMissingAdbIsA502() async throws {
        let backend = StubBackend()
        #expect(await TailscaleRoutes.connect(body: Data("{".utf8), backend: backend).0 == 400)
        #expect(await TailscaleRoutes.prepare(body: Data("{}".utf8), backend: backend).0 == 400)
        let blank = DaemonProtocol.encoded(DaemonProtocol.DeviceRequest(serial: ""))
        #expect(await TailscaleRoutes.prepare(body: blank, backend: backend).0 == 400)

        let broken = StubBackend(unreachable: true)
        let request = DaemonProtocol.encoded(DaemonProtocol.DeviceRequest(serial: "R58M123ABC"))
        #expect(await TailscaleRoutes.prepare(body: request, backend: broken).0 == 502)
    }

    @Test func theRegistryFlagsTravelWithEveryFeature() throws {
        let features = ActionProtocol.features().features
        let flagged = Set(features.filter { $0.remoteLinkWarning != nil }.map(\.id))
        #expect(flagged == Set(FeatureRegistry.remoteLinkWarnings.keys))
        let wifi = try #require(features.first { $0.id == "wifi" })
        #expect(wifi.remoteLinkWarning == FeatureRegistry.remoteLinkWarnings["wifi"])
    }
}
