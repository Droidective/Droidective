#if canImport(Network)
import Testing
@testable import ADBKit

/// The `adb reverse` half of the relay — the tunnel that lets a device's
/// localhost:9090 reach the Mac. Arg-vector tests, because the port is a
/// contract with `reactotron-react-native` and a wrong or missing tunnel is
/// a client that simply never appears.
@Suite struct ReactotronServiceTests {
    @Test func reverseUsesTheClientsAgreedPortOnEachSerial() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s"], stdout: "")
        let service = ReactotronService(client: await makeTestClient(runner: runner))

        let results = await service.reverse(serials: ["S1", "S2"])

        #expect(results.map(\.ok) == [true, true])
        #expect(runner.invocations.map(\.arguments) == [
            ["-s", "S1", "reverse", "tcp:9090", "tcp:9090"],
            ["-s", "S2", "reverse", "tcp:9090", "tcp:9090"],
        ])
    }

    /// 9090 is upstream's number, not a preference — if this changes, every
    /// `reactotron-react-native` client in the wild stops connecting.
    @Test func defaultPortIsUpstreams() {
        #expect(ReactotronService.defaultPort == 9090)
    }

    /// A freshly attached or just-booted device rejects the first reverse, so
    /// giving up on one refusal is the difference between a working tunnel and
    /// a permanent "waiting for a connection".
    @Test func aRefusedReverseIsRetried() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s"], stderr: "error: device offline", exitCode: 1)
        let service = ReactotronService(client: await makeTestClient(runner: runner))

        let results = await service.reverse(serials: ["S1"])

        #expect(results.count == 1)
        #expect(results[0].ok == false)
        #expect(results[0].serial == "S1")
        // The adb reason reaches the UI, which shows it in the tunnel banner.
        #expect(results[0].detail.contains("device offline"))
        #expect(runner.invocations.count == 3)
    }

    @Test func stopRemovesTheTunnelPerSerial() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s"], stdout: "")
        let service = ReactotronService(client: await makeTestClient(runner: runner))

        await service.stop(serials: ["S1", "S2"])

        #expect(runner.invocations.map(\.arguments) == [
            ["-s", "S1", "reverse", "--remove", "tcp:9090"],
            ["-s", "S2", "reverse", "--remove", "tcp:9090"],
        ])
    }

    /// Shown in the Commands tab so the tunnel can be reproduced by hand.
    @Test func reverseCommandMatchesWhatIsRun() async {
        let runner = MockProcessRunner()
        let service = ReactotronService(client: await makeTestClient(runner: runner))
        #expect(await service.reverseCommand == "adb reverse tcp:9090 tcp:9090")
    }
}
#endif
