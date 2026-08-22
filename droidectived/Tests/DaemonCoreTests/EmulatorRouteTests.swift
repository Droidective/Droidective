import ADBKit
import Foundation
import Testing

@testable import DaemonCore

/// The emulator routes without a process.
///
/// The thing worth defending is that a request is checked for *completeness*
/// before anything spawns: stopping without a serial and launching without an
/// AVD name are both the client's mistake, and letting either through would
/// turn a 400 into a process invoked with an empty argument.
@Suite struct EmulatorRouteTests {
    private struct Refusal: Error, CustomStringConvertible {
        let description: String
    }

    private actor CallLog {
        private(set) var actions: [(EmulatorProtocol.Action, String, String)] = []
        func record(_ action: EmulatorProtocol.Action, _ avd: String, _ serial: String) {
            actions.append((action, avd, serial))
        }
    }

    private struct StubBackend: DaemonBackend {
        let log = CallLog()
        var avds: [Avd] = []
        var installed = true
        var refusal: Refusal?

        func emulators() async -> ([Avd], Bool) { (avds, installed) }

        func emulatorAction(
            _ action: EmulatorProtocol.Action, avd: String, serial: String
        ) async throws -> FeatureResult {
            if let refusal { throw refusal }
            await log.record(action, avd, serial)
            return FeatureResult(ok: true, message: "ok")
        }
    }

    private func body(_ value: some Encodable) -> Data { DaemonProtocol.encoded(value) }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    // MARK: - Listing

    @Test func theListCarriesTheDisplayNameRatherThanMakingTheClientDeriveIt() async throws {
        let backend = StubBackend(avds: [Avd(name: "Pixel_8_API_35", runningSerial: nil)])
        let answer = await EmulatorRoutes.list(backend: backend)

        #expect(answer.status == 200)
        let response = try decode(EmulatorProtocol.ListResponse.self, answer.body)
        #expect(response.avds.first?.name == "Pixel_8_API_35")
        #expect(response.avds.first?.displayName == "Pixel 8 API 35")
    }

    @Test func aRunningAvdCarriesItsSerial() async throws {
        let backend = StubBackend(
            avds: [Avd(name: "Pixel_8", runningSerial: "emulator-5554")])
        let answer = await EmulatorRoutes.list(backend: backend)
        let response = try decode(EmulatorProtocol.ListResponse.self, answer.body)
        #expect(response.avds.first?.runningSerial == "emulator-5554")
    }

    @Test func aMissingEmulatorBinaryIsSaidOutrightNotShownAsNoAvds() async throws {
        // An empty list would read as "you have no AVDs", which sends someone
        // to create one they may already have.
        let answer = await EmulatorRoutes.list(backend: StubBackend(installed: false))
        let response = try decode(EmulatorProtocol.ListResponse.self, answer.body)
        #expect(!response.installed)
        #expect(response.avds.isEmpty)
    }

    // MARK: - Actions

    @Test func everyAdvertisedActionResolves() async throws {
        // A loop over the enum: a verb added to the wire without a path
        // through the backend fails here rather than at runtime.
        for action in EmulatorProtocol.Action.allCases {
            let backend = StubBackend()
            let answer = await EmulatorRoutes.action(
                body: body(EmulatorProtocol.ActionRequest(
                    avd: "Pixel_8", serial: "emulator-5554", action: action.rawValue)),
                backend: backend)

            #expect(answer.status == 200, "\(action.rawValue) was refused")
            #expect(await backend.log.actions.first?.0 == action)
        }
    }

    @Test func stopIdentifiesBySerialAndLaunchByName() async throws {
        let stopping = StubBackend()
        _ = await EmulatorRoutes.action(
            body: body(EmulatorProtocol.ActionRequest(serial: "emulator-5554", action: "stop")),
            backend: stopping)
        #expect(await stopping.log.actions.first?.2 == "emulator-5554")

        let launching = StubBackend()
        _ = await EmulatorRoutes.action(
            body: body(EmulatorProtocol.ActionRequest(avd: "Pixel_8", action: "launch")),
            backend: launching)
        #expect(await launching.log.actions.first?.1 == "Pixel_8")
    }

    @Test func stoppingWithoutASerialIsRefusedRatherThanRun() async throws {
        // `emu kill` with no target is not a command worth sending.
        let backend = StubBackend()
        let answer = await EmulatorRoutes.action(
            body: body(EmulatorProtocol.ActionRequest(avd: "Pixel_8", action: "stop")),
            backend: backend)

        #expect(answer.status == 400)
        #expect(await backend.log.actions.isEmpty)
    }

    @Test func launchingWithoutAnAvdIsRefused() async throws {
        for action in ["launch", "coldBoot", "wipeData"] {
            let backend = StubBackend()
            let answer = await EmulatorRoutes.action(
                body: body(EmulatorProtocol.ActionRequest(avd: "", action: action)),
                backend: backend)

            #expect(answer.status == 400, "\(action) with no AVD was accepted")
            #expect(await backend.log.actions.isEmpty)
        }
    }

    @Test func relaunchNeedsBothHalvesBecauseItStopsThenBoots() async throws {
        let backend = StubBackend()
        let answer = await EmulatorRoutes.action(
            body: body(EmulatorProtocol.ActionRequest(avd: "Pixel_8", action: "relaunch")),
            backend: backend)

        #expect(answer.status == 400)
        #expect(await backend.log.actions.isEmpty)
    }

    @Test func anUnknownActionIsRefused() async {
        let answer = await EmulatorRoutes.action(
            body: body(EmulatorProtocol.ActionRequest(avd: "Pixel_8", action: "rm -rf /")),
            backend: StubBackend())
        #expect(answer.status == 400)
    }

    @Test func aFailedLaunchIsAFiveOhTwo() async {
        let answer = await EmulatorRoutes.action(
            body: body(EmulatorProtocol.ActionRequest(avd: "Pixel_8", action: "launch")),
            backend: StubBackend(refusal: Refusal(description: "emulator not found")))
        #expect(answer.status == 502)
    }
}
