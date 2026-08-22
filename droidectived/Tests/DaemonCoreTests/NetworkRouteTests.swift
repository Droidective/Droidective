import ADBKit
import Foundation
import Testing

@testable import DaemonCore

/// The Wi-Fi and Private DNS routes without a socket.
///
/// Two things are worth defending. First, `cmd wifi connect-network` exits 0
/// while printing "failed" on plenty of ROMs, so the exit code alone reports a
/// success that never happened — the Mac checks the output and the daemon has
/// to make the same call, or the two apps disagree about whether a connect
/// worked. Second, the security mode is the one field on the connect request
/// that reaches an adb argument vector unquoted, because it is a keyword
/// rather than a value: it must come from a closed set.
@Suite struct NetworkRouteTests {
    private struct Refusal: Error, CustomStringConvertible {
        let description: String
    }

    private actor CallLog {
        private(set) var wifi: [NetworkProtocol.WifiWrite] = []
        private(set) var dns: [(DnsStatus.Mode, String)] = []
        func record(_ write: NetworkProtocol.WifiWrite) { wifi.append(write) }
        func record(_ mode: DnsStatus.Mode, _ hostname: String) { dns.append((mode, hostname)) }
    }

    private struct StubBackend: DaemonBackend {
        let log = CallLog()
        var status = WifiStatus(
            enabled: true, connected: true, ssid: "Coffee", ipAddress: "192.168.1.9",
            linkSpeed: "780Mbps", frequency: "5GHz", signal: "-42dBm")
        var networks: [WifiNetwork] = []
        var rooted = false
        var dns = DnsStatus(mode: .automatic, hostname: nil)
        var stdout = ""
        var exitCode: Int32 = 0
        var refusal: Refusal?

        func wifi(serial: String) async -> (WifiStatus, [WifiNetwork], Bool) {
            (status, networks, rooted)
        }

        func writeWifi(
            serial: String, _ write: NetworkProtocol.WifiWrite
        ) async throws -> AdbResult {
            if let refusal { throw refusal }
            await log.record(write)
            return AdbResult(stdout: stdout, stderr: "", exitCode: exitCode, timedOut: false)
        }

        func privateDns(serial: String) async -> DnsStatus { dns }

        func writePrivateDns(
            serial: String, mode: DnsStatus.Mode, hostname: String
        ) async throws -> AdbResult {
            if let refusal { throw refusal }
            await log.record(mode, hostname)
            return AdbResult(stdout: stdout, stderr: "", exitCode: exitCode, timedOut: false)
        }
    }

    private func body(_ value: some Encodable) -> Data { DaemonProtocol.encoded(value) }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    private func device(_ serial: String = "S1") -> Data {
        body(DaemonProtocol.DeviceRequest(serial: serial))
    }

    // MARK: - Wi-Fi, reading

    @Test func theWifiReadCarriesTheWholeConnection() async throws {
        let answer = await NetworkRoutes.wifiRead(body: device(), backend: StubBackend())
        #expect(answer.status == 200)

        let response = try decode(NetworkProtocol.WifiResponse.self, answer.body)
        #expect(response.status.ssid == "Coffee")
        #expect(response.status.ipAddress == "192.168.1.9")
        #expect(response.status.linkSpeed == "780Mbps")
        #expect(response.status.frequency == "5GHz")
        #expect(response.status.signal == "-42dBm")
    }

    @Test func aPasswordTravelsOnlyWhenTheDeviceHadARootShell() async throws {
        // Not a policy the daemon applies — it is simply the only case where
        // `WifiConfigStore.xml` was readable. Saying so lets the UI explain the
        // absence instead of implying there are no saved passwords.
        let secret = WifiNetwork(networkId: 1, ssid: "Coffee", security: "WPA2", password: "hunter2")
        let unrooted = await NetworkRoutes.wifiRead(
            body: device(), backend: StubBackend(networks: [secret], rooted: false))
        let rooted = await NetworkRoutes.wifiRead(
            body: device(), backend: StubBackend(networks: [secret], rooted: true))

        #expect(try !decode(NetworkProtocol.WifiResponse.self, unrooted.body).hasRootShell)
        #expect(try decode(NetworkProtocol.WifiResponse.self, rooted.body).hasRootShell)
        #expect(try decode(NetworkProtocol.WifiResponse.self, rooted.body)
            .networks.first?.password == "hunter2")
    }

    @Test func everySavedNetworkGetsAUniqueId() async throws {
        // A credential found only in the config store has no network id, and a
        // row with no key cannot be rendered in a list. The identity is
        // composite — `cmd wifi list-networks` prints the same id twice on an
        // emulator — so what matters is that it is non-empty and unique, not
        // what it spells.
        let backend = StubBackend(
            networks: [
                WifiNetwork(networkId: nil, ssid: "Hotel", security: nil),
                WifiNetwork(networkId: nil, ssid: "Cafe", security: "WPA2"),
            ],
            rooted: true)
        let answer = await NetworkRoutes.wifiRead(body: device(), backend: backend)
        let response = try decode(NetworkProtocol.WifiResponse.self, answer.body)

        let ids = response.networks.map(\.id)
        #expect(ids.allSatisfy { !$0.isEmpty })
        #expect(Set(ids).count == ids.count)
    }

    // MARK: - Wi-Fi, writing

    @Test func enabledTogglesTheRadio() async throws {
        let backend = StubBackend()
        let answer = await NetworkRoutes.wifiWrite(
            body: body(NetworkProtocol.WifiWriteRequest(serial: "S1", enabled: false)),
            backend: backend)

        #expect(answer.status == 200)
        #expect(await backend.log.wifi == [.setEnabled(false)])
        #expect(try decode(ActionProtocol.RunResponse.self, answer.body).message == "Wi-Fi off")
    }

    @Test func aRomThatBlocksSvcWifiGetsTheMacsWording() async throws {
        let backend = StubBackend(exitCode: 1)
        let answer = await NetworkRoutes.wifiWrite(
            body: body(NetworkProtocol.WifiWriteRequest(serial: "S1", enabled: true)),
            backend: backend)

        let response = try decode(ActionProtocol.RunResponse.self, answer.body)
        #expect(answer.status == 200)
        #expect(!response.ok)
        #expect(response.message.contains("svc wifi over adb"))
    }

    @Test func anSsidAndASecurityModeConnect() async throws {
        let backend = StubBackend()
        let answer = await NetworkRoutes.wifiWrite(
            body: body(NetworkProtocol.WifiWriteRequest(
                serial: "S1", ssid: "Coffee", security: "wpa2", password: "hunter2")),
            backend: backend)

        #expect(answer.status == 200)
        #expect(await backend.log.wifi == [.connect(
            ssid: "Coffee", security: "wpa2", password: "hunter2")])
    }

    @Test func anOpenNetworkNeedsNoPassword() async throws {
        let backend = StubBackend()
        let answer = await NetworkRoutes.wifiWrite(
            body: body(NetworkProtocol.WifiWriteRequest(
                serial: "S1", ssid: "Airport", security: "open")),
            backend: backend)

        #expect(answer.status == 200)
        #expect(await backend.log.wifi == [.connect(ssid: "Airport", security: "open", password: "")])
    }

    @Test func aSecurityModeOutsideTheKnownSetIsRefused() async throws {
        // It lands in the argument vector unquoted, being a keyword rather than
        // a value — so this is the one field that must be a closed set.
        let backend = StubBackend()
        let answer = await NetworkRoutes.wifiWrite(
            body: body(NetworkProtocol.WifiWriteRequest(
                serial: "S1", ssid: "Coffee", security: "; rm -rf /")),
            backend: backend)

        #expect(answer.status == 400)
        #expect(await backend.log.wifi.isEmpty)
    }

    @Test func everyAdvertisedSecurityModeIsAccepted() async throws {
        for security in NetworkProtocol.WifiWriteRequest.securities {
            let backend = StubBackend()
            let answer = await NetworkRoutes.wifiWrite(
                body: body(NetworkProtocol.WifiWriteRequest(
                    serial: "S1", ssid: "Net", security: security)),
                backend: backend)
            #expect(answer.status == 200, "\(security) was refused")
        }
    }

    @Test func anEmptySsidIsRefused() async {
        let answer = await NetworkRoutes.wifiWrite(
            body: body(NetworkProtocol.WifiWriteRequest(serial: "S1", ssid: "", security: "wpa2")),
            backend: StubBackend())
        #expect(answer.status == 400)
    }

    @Test func aRequestThatSaysNeitherIsRefused() async {
        let answer = await NetworkRoutes.wifiWrite(
            body: body(NetworkProtocol.WifiWriteRequest(serial: "S1")), backend: StubBackend())
        #expect(answer.status == 400)
    }

    @Test func aConnectThatPrintsFailedIsAFailureDespiteExitingZero() async throws {
        // The whole reason the output is inspected: exit 0 here means "the
        // command ran", not "the device joined the network".
        let backend = StubBackend(stdout: "Failed to connect", exitCode: 0)
        let answer = await NetworkRoutes.wifiWrite(
            body: body(NetworkProtocol.WifiWriteRequest(
                serial: "S1", ssid: "Coffee", security: "wpa2")),
            backend: backend)

        let response = try decode(ActionProtocol.RunResponse.self, answer.body)
        #expect(!response.ok)
        #expect(response.message.contains("may block it over adb"))
    }

    @Test func aCleanConnectSaysItIsConnecting() async throws {
        let answer = await NetworkRoutes.wifiWrite(
            body: body(NetworkProtocol.WifiWriteRequest(
                serial: "S1", ssid: "Coffee", security: "wpa2")),
            backend: StubBackend())
        let response = try decode(ActionProtocol.RunResponse.self, answer.body)
        #expect(response.ok)
        #expect(response.message == "Connecting to Coffee…")
    }

    @Test func adbBeingUnreachableIsAFiveOhTwo() async {
        let answer = await NetworkRoutes.wifiWrite(
            body: body(NetworkProtocol.WifiWriteRequest(serial: "S1", enabled: true)),
            backend: StubBackend(refusal: Refusal(description: "offline")))
        #expect(answer.status == 502)
    }

    // MARK: - Private DNS

    @Test func theDnsReadCarriesModeAndHostname() async throws {
        let backend = StubBackend(dns: DnsStatus(mode: .hostname, hostname: "dns.google"))
        let answer = await NetworkRoutes.dnsRead(body: device(), backend: backend)

        #expect(answer.status == 200)
        let response = try decode(NetworkProtocol.DnsResponse.self, answer.body)
        #expect(response.mode == "hostname")
        #expect(response.hostname == "dns.google")
    }

    @Test func everyModeWrites() async throws {
        for mode in [DnsStatus.Mode.off, .automatic] {
            let backend = StubBackend()
            let answer = await NetworkRoutes.dnsWrite(
                body: body(NetworkProtocol.DnsWriteRequest(serial: "S1", mode: mode.rawValue)),
                backend: backend)
            #expect(answer.status == 200, "\(mode.rawValue) was refused")
            #expect(await backend.log.dns.map(\.0) == [mode])
        }
    }

    @Test func aHostnameModeCarriesItsTrimmedHostname() async throws {
        let backend = StubBackend()
        let answer = await NetworkRoutes.dnsWrite(
            body: body(NetworkProtocol.DnsWriteRequest(
                serial: "S1", mode: "hostname", hostname: "  dns.google  ")),
            backend: backend)

        #expect(answer.status == 200)
        #expect(await backend.log.dns.map(\.1) == ["dns.google"])
    }

    @Test func aHostnameModeWithNothingToPointAtIsRefused() async throws {
        // Writing an empty specifier would leave the device's DNS broken, so
        // it is refused rather than half-applied.
        for hostname in [nil, "", "   "] {
            let backend = StubBackend()
            let answer = await NetworkRoutes.dnsWrite(
                body: body(NetworkProtocol.DnsWriteRequest(
                    serial: "S1", mode: "hostname", hostname: hostname)),
                backend: backend)
            #expect(answer.status == 400, "hostname \(hostname ?? "nil") was accepted")
            #expect(await backend.log.dns.isEmpty)
        }
    }

    @Test func anUnknownModeIsRefused() async {
        let answer = await NetworkRoutes.dnsWrite(
            body: body(NetworkProtocol.DnsWriteRequest(serial: "S1", mode: "opportunistic")),
            backend: StubBackend())
        // "opportunistic" is what the device stores, not what the wire accepts:
        // `DnsStatus.Mode` calls it automatic, and accepting both spellings
        // would be two names for one mode.
        #expect(answer.status == 400)
    }
}
