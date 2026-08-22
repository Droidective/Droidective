import ADBKit
import Foundation
import Testing

@testable import DaemonCore

/// The wireless route without adb.
///
/// What is worth defending here is the *parsing*, because it decides what
/// reaches an adb argument vector. Two rules in particular: pairing must never
/// invent a port (the Android 11+ pairing port is random per session, so a
/// default would target the wrong one and report a pairing failure that was
/// really the client's mistake), and disconnect's empty string means "all", not
/// a device named "".
@Suite struct ConnectionRouteTests {
    private struct Refusal: Error, CustomStringConvertible {
        let description: String
    }

    private actor CallLog {
        private(set) var calls: [String] = []
        func record(_ call: String) { calls.append(call) }
    }

    private struct StubBackend: DaemonBackend {
        let log = CallLog()
        var paired = true
        var discovered: WirelessEndpoint?
        var refusal: Refusal?

        func pairWireless(host: String, port: String, code: String) async throws -> FeatureResult {
            if let refusal { throw refusal }
            await log.record("pair \(host) \(port) \(code)")
            return FeatureResult(ok: paired, message: paired ? "Paired" : "Pairing failed")
        }

        func discoverConnectEndpoint(host: String) async -> WirelessEndpoint? {
            await log.record("discover \(host)")
            return discovered
        }

        func connectWireless(host: String, port: String) async throws -> FeatureResult {
            if let refusal { throw refusal }
            await log.record("connect \(host) \(port)")
            return FeatureResult(ok: true, message: "Connected")
        }

        func disconnectWireless(target: String?) async throws -> FeatureResult {
            if let refusal { throw refusal }
            await log.record("disconnect \(target ?? "<all>")")
            return FeatureResult(ok: true, message: "Disconnected")
        }

        func enableTcpip(serial: String) async throws -> FeatureResult {
            if let refusal { throw refusal }
            await log.record("tcpip \(serial)")
            return FeatureResult(ok: true, message: "tcpip")
        }
    }

    private func body(_ value: some Encodable) -> Data { DaemonProtocol.encoded(value) }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    private func request(
        _ action: String, endpoint: String? = nil, code: String? = nil, serial: String? = nil
    ) -> Data {
        body(ConnectionProtocol.ActionRequest(
            action: action, endpoint: endpoint, code: code, serial: serial))
    }

    // MARK: - Every verb has a path

    @Test func everyAdvertisedActionResolves() async throws {
        // A loop over the enum, as the emulator routes do: a verb added to the
        // wire with no path through the backend fails here, not at runtime.
        let complete: [ConnectionProtocol.Action: Data] = [
            .pair: request("pair", endpoint: "10.0.0.5:37199", code: "123456"),
            .connect: request("connect", endpoint: "10.0.0.5:5555"),
            .disconnect: request("disconnect", serial: "10.0.0.5:5555"),
            .tcpip: request("tcpip", serial: "R58M4XYZ"),
        ]
        for action in ConnectionProtocol.Action.allCases {
            let payload = try #require(complete[action], "\(action.rawValue) has no test request")
            let backend = StubBackend()
            let answer = await ConnectionRoutes.action(body: payload, backend: backend)
            #expect(answer.status == 200, "\(action.rawValue) was refused")
            #expect(await !backend.log.calls.isEmpty, "\(action.rawValue) reached nothing")
        }
    }

    @Test func anUnknownActionIsRefused() async {
        let answer = await ConnectionRoutes.action(
            body: request("kill", serial: "R58M4XYZ"), backend: StubBackend())
        #expect(answer.status == 400)
    }

    // MARK: - Pairing

    @Test func pairingInsistsOnTheExplicitPortItWasGiven() async throws {
        // Defaulting to 5555 would pair against the *connection* port and
        // report a failure that was really a wrong argument.
        let backend = StubBackend()
        let answer = await ConnectionRoutes.action(
            body: request("pair", endpoint: "10.0.0.5", code: "123456"), backend: backend)

        #expect(answer.status == 400)
        #expect(await backend.log.calls.isEmpty)
    }

    @Test func pairingWithoutACodeIsRefused() async throws {
        let backend = StubBackend()
        let answer = await ConnectionRoutes.action(
            body: request("pair", endpoint: "10.0.0.5:37199"), backend: backend)
        #expect(answer.status == 400)
        #expect(await backend.log.calls.isEmpty)
    }

    @Test func aSuccessfulPairCarriesTheEndpointTheDeviceThenAdvertised() async throws {
        // The Mac's sheet connects straight after pairing; without the port on
        // the reply, the client would have to ask for one the phone never showed.
        let backend = StubBackend(
            discovered: WirelessEndpoint(host: "10.0.0.5", port: "40913"))
        let answer = await ConnectionRoutes.action(
            body: request("pair", endpoint: "10.0.0.5:37199", code: "123456"), backend: backend)

        let response = try decode(ConnectionProtocol.PairResponse.self, answer.body)
        #expect(response.result.ok)
        #expect(response.discovered?.port == "40913")
    }

    @Test func aFailedPairIsNotFollowedByALookup() async throws {
        // Nothing has been paired, so there is nothing advertising itself.
        let backend = StubBackend(paired: false)
        let answer = await ConnectionRoutes.action(
            body: request("pair", endpoint: "10.0.0.5:37199", code: "000000"), backend: backend)

        let response = try decode(ConnectionProtocol.PairResponse.self, answer.body)
        #expect(!response.result.ok)
        #expect(response.discovered == nil)
        #expect(await backend.log.calls == ["pair 10.0.0.5 37199 000000"])
    }

    @Test func aPairedDeviceThatAdvertisesNothingStillReportsTheSuccess() async throws {
        // mDNS off in this adb, or the advertisement has not landed yet. The
        // pairing worked; the sheet asks for the port.
        let answer = await ConnectionRoutes.action(
            body: request("pair", endpoint: "10.0.0.5:37199", code: "123456"),
            backend: StubBackend())
        let response = try decode(ConnectionProtocol.PairResponse.self, answer.body)
        #expect(response.result.ok)
        #expect(response.discovered == nil)
    }

    // MARK: - Connect

    @Test func connectingToABareHostTakesAdbsOwnDefaultPort() async throws {
        let backend = StubBackend()
        _ = await ConnectionRoutes.action(
            body: request("connect", endpoint: "10.158.128.7"), backend: backend)
        #expect(await backend.log.calls == ["connect 10.158.128.7 5555"])
    }

    @Test func aPastedEndpointIsToleratedTheWayTheSheetPastesIt() async throws {
        let backend = StubBackend()
        _ = await ConnectionRoutes.action(
            body: request("connect", endpoint: "  10.0.0.5:37199\n"), backend: backend)
        #expect(await backend.log.calls == ["connect 10.0.0.5 37199"])
    }

    @Test func aBareIPv6IsBracketedForAdb() async throws {
        let backend = StubBackend()
        _ = await ConnectionRoutes.action(
            body: request("connect", endpoint: "fe80::1"), backend: backend)
        #expect(await backend.log.calls == ["connect [fe80::1] 5555"])
    }

    @Test func somethingThatIsNotAnEndpointNeverReachesAdb() async throws {
        // A truncated IPv4, an out-of-range port, and free text: all the
        // client's mistake, and all a 400 rather than an adb invocation.
        for endpoint in ["1.1.1", "10.0.0.5:99999", "not a host", ""] {
            let backend = StubBackend()
            let answer = await ConnectionRoutes.action(
                body: request("connect", endpoint: endpoint), backend: backend)
            #expect(answer.status == 400, "\(endpoint) was accepted")
            #expect(await backend.log.calls.isEmpty, "\(endpoint) reached adb")
        }
    }

    // MARK: - Disconnect

    @Test func disconnectWithNoSerialMeansEveryWirelessDevice() async throws {
        let backend = StubBackend()
        let answer = await ConnectionRoutes.action(body: request("disconnect"), backend: backend)
        #expect(answer.status == 200)
        #expect(await backend.log.calls == ["disconnect <all>"])
    }

    @Test func anEmptySerialIsAllRatherThanADeviceNamedNothing() async throws {
        // `adb disconnect ""` is not a request adb can answer.
        let backend = StubBackend()
        _ = await ConnectionRoutes.action(
            body: request("disconnect", serial: ""), backend: backend)
        #expect(await backend.log.calls == ["disconnect <all>"])
    }

    // MARK: - tcpip

    @Test func theBootstrapNeedsTheUsbDeviceItIsBootstrapping() async throws {
        let backend = StubBackend()
        let answer = await ConnectionRoutes.action(body: request("tcpip"), backend: backend)
        #expect(answer.status == 400)
        #expect(await backend.log.calls.isEmpty)
    }

    // MARK: - Failures

    @Test func adbRefusingIsAFiveOhTwoNotAFiveHundred() async {
        let answer = await ConnectionRoutes.action(
            body: request("connect", endpoint: "10.0.0.5:5555"),
            backend: StubBackend(refusal: Refusal(description: "adb not found")))
        #expect(answer.status == 502)
    }
}
