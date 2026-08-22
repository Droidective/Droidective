import ADBKit
import Foundation
import Testing

@testable import DaemonCore

/// The device-state routes without a socket.
///
/// The thing worth defending here is that the daemon stays a pass-through over
/// `DeveloperSettingsService`'s and `RestrictionsService`'s own tables. The
/// titles, the details, the scale steps and the `settings put` / `setprop`
/// backing all live in ADBKit; if any of them were re-typed here or in a
/// client, the two apps would eventually disagree about what a toggle is
/// called or what it writes.
@Suite struct DeviceSettingsRouteTests {
    private struct Refusal: Error, CustomStringConvertible {
        let description: String
    }

    private actor CallLog {
        private(set) var devWrites: [DeviceSettingsProtocol.DevWrite] = []
        private(set) var restrictionWrites: [DeviceSettingsProtocol.RestrictionWrite] = []
        func record(_ write: DeviceSettingsProtocol.DevWrite) { devWrites.append(write) }
        func record(_ write: DeviceSettingsProtocol.RestrictionWrite) {
            restrictionWrites.append(write)
        }
    }

    private struct StubBackend: DaemonBackend {
        let log = CallLog()
        var toggles: [String: Bool] = [:]
        var scales: [String: Double] = [:]
        var state = RestrictionsState(
            adbInstallVerification: true, packageVerifier: true, stayAwake: false,
            hiddenApiEnforced: true, selinuxEnforcing: nil)
        var rooted = false
        /// What adb answered. Non-zero is the device saying no, which is not
        /// the same thing as `refusal`.
        var exitCode: Int32 = 0
        var stderr = ""
        var refusal: Refusal?

        func developerSettings(serial: String) async -> DeviceSettingsProtocol.DevState {
            DeviceSettingsProtocol.DevState(toggles: toggles, scales: scales)
        }

        func writeDeveloperSetting(
            serial: String, _ write: DeviceSettingsProtocol.DevWrite
        ) async throws -> AdbResult {
            if let refusal { throw refusal }
            await log.record(write)
            return AdbResult(stdout: "", stderr: stderr, exitCode: exitCode, timedOut: false)
        }

        func restrictions(serial: String) async -> RestrictionsState { state }

        func rootStatus(serial: String) async -> RootStatus {
            RootStatus(
                hasRootShell: rooted, likelyRooted: rooted,
                summary: rooted ? "Rooted" : "Not rooted", signals: [])
        }

        func writeRestriction(
            serial: String, _ write: DeviceSettingsProtocol.RestrictionWrite
        ) async throws -> AdbResult {
            if let refusal { throw refusal }
            await log.record(write)
            return AdbResult(stdout: "", stderr: stderr, exitCode: exitCode, timedOut: false)
        }
    }

    private func body(_ value: some Encodable) -> Data {
        DaemonProtocol.encoded(value)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    // MARK: - Developer Options, reading

    @Test func developerReadServesEveryToggleInTheServicesOwnOrder() async throws {
        let backend = StubBackend(toggles: ["show-touches": true])
        let answer = await DeviceSettingsRoutes.developerRead(
            body: body(DaemonProtocol.DeviceRequest(serial: "S1")), backend: backend)

        #expect(answer.status == 200)
        let response = try decode(DeviceSettingsProtocol.DevResponse.self, answer.body)
        #expect(response.toggles.map(\.id) == DeveloperSettingsService.toggles.map(\.id))
        #expect(response.scales.map(\.id) == DeveloperSettingsService.animationScales.map(\.id))
    }

    @Test func developerReadCarriesTheTitleAndDetailFromTheServiceTable() async throws {
        // The definitions travel with the values so no client re-types them.
        let backend = StubBackend()
        let answer = await DeviceSettingsRoutes.developerRead(
            body: body(DaemonProtocol.DeviceRequest(serial: "S1")), backend: backend)
        let response = try decode(DeviceSettingsProtocol.DevResponse.self, answer.body)

        let served = try #require(response.toggles.first { $0.id == "show-touches" })
        let defined = try #require(DeveloperSettingsService.toggles.first { $0.id == "show-touches" })
        #expect(served.title == defined.title)
        #expect(served.detail == defined.detail)
    }

    @Test func developerReadCarriesTheServicesScaleSteps() async throws {
        let answer = await DeviceSettingsRoutes.developerRead(
            body: body(DaemonProtocol.DeviceRequest(serial: "S1")), backend: StubBackend())
        let response = try decode(DeviceSettingsProtocol.DevResponse.self, answer.body)
        #expect(response.scaleChoices == DeveloperSettingsService.scaleChoices)
    }

    @Test func anUnreadToggleIsOffAndAnUnreadScaleIsTheOneTimesDefault() async throws {
        // `settings get` prints `null` for a key nobody set; the platform
        // default for a scale is 1×, not 0 — 0 means animations are *off*.
        let answer = await DeviceSettingsRoutes.developerRead(
            body: body(DaemonProtocol.DeviceRequest(serial: "S1")), backend: StubBackend())
        let response = try decode(DeviceSettingsProtocol.DevResponse.self, answer.body)

        #expect(response.toggles.allSatisfy { !$0.on })
        #expect(response.scales.allSatisfy { $0.value == 1.0 })
    }

    @Test func developerReadRefusesABodyItCannotRead() async {
        let answer = await DeviceSettingsRoutes.developerRead(
            body: Data("not json".utf8), backend: StubBackend())
        #expect(answer.status == 400)
    }

    // MARK: - Developer Options, writing

    @Test func aToggleWriteResolvesToTheServicesOwnDefinition() async throws {
        let backend = StubBackend()
        let answer = await DeviceSettingsRoutes.developerWrite(
            body: body(DeviceSettingsProtocol.DevWriteRequest(
                serial: "S1", id: "layout-bounds", on: true)),
            backend: backend)

        #expect(answer.status == 200)
        let expected = try #require(
            DeveloperSettingsService.toggles.first { $0.id == "layout-bounds" })
        #expect(await backend.log.devWrites == [.toggle(expected, on: true)])
    }

    @Test func aScaleWriteResolvesAgainstTheScaleTable() async throws {
        let backend = StubBackend()
        let answer = await DeviceSettingsRoutes.developerWrite(
            body: body(DeviceSettingsProtocol.DevWriteRequest(
                serial: "S1", id: "window-scale", value: 0.5)),
            backend: backend)

        #expect(answer.status == 200)
        let expected = try #require(
            DeveloperSettingsService.animationScales.first { $0.id == "window-scale" })
        #expect(await backend.log.devWrites == [.scale(expected, value: 0.5)])
    }

    @Test func anUnknownIdIsRefusedRatherThanWritten() async throws {
        // Resolution *is* the validation: an id no table knows cannot produce
        // a `DevWrite`, so nothing downstream has to handle one.
        let backend = StubBackend()
        let answer = await DeviceSettingsRoutes.developerWrite(
            body: body(DeviceSettingsProtocol.DevWriteRequest(
                serial: "S1", id: "no-such-toggle", on: true)),
            backend: backend)

        #expect(answer.status == 400)
        #expect(await backend.log.devWrites.isEmpty)
    }

    @Test func aWriteThatSaysNeitherOnNorValueIsRefused() async throws {
        let backend = StubBackend()
        let answer = await DeviceSettingsRoutes.developerWrite(
            body: body(DeviceSettingsProtocol.DevWriteRequest(serial: "S1", id: "show-touches")),
            backend: backend)

        #expect(answer.status == 400)
        #expect(await backend.log.devWrites.isEmpty)
    }

    @Test func theDeviceRefusingAWriteIsATwoHundredCarryingItsWords() async throws {
        // A non-zero adb exit is the device's answer, not a daemon fault. A 5xx
        // here would make "the setting would not stick" indistinguishable from
        // "the daemon broke".
        let backend = StubBackend(exitCode: 1, stderr: "Permission denial")
        let answer = await DeviceSettingsRoutes.developerWrite(
            body: body(DeviceSettingsProtocol.DevWriteRequest(
                serial: "S1", id: "show-touches", on: true)),
            backend: backend)

        #expect(answer.status == 200)
        let response = try decode(ActionProtocol.RunResponse.self, answer.body)
        #expect(!response.ok)
        #expect(response.message.contains("Permission denial"))
    }

    @Test func adbBeingUnreachableIsAFiveOhTwo() async {
        let backend = StubBackend(refusal: Refusal(description: "device offline"))
        let answer = await DeviceSettingsRoutes.developerWrite(
            body: body(DeviceSettingsProtocol.DevWriteRequest(
                serial: "S1", id: "show-touches", on: true)),
            backend: backend)
        #expect(answer.status == 502)
    }

    // MARK: - Restrictions

    @Test func restrictionsReadCarriesWhetherTheRootHalfIsReachable() async throws {
        // The Mac loads both together and hides the Root section without a
        // shell; asking separately would render it, then take it away.
        let backend = StubBackend(rooted: true)
        let answer = await DeviceSettingsRoutes.restrictionsRead(
            body: body(DaemonProtocol.DeviceRequest(serial: "S1")), backend: backend)

        #expect(answer.status == 200)
        let response = try decode(DeviceSettingsProtocol.RestrictionsResponse.self, answer.body)
        #expect(response.hasRootShell)
    }

    @Test func anUnknownSelinuxModeStaysUnknownRatherThanBecomingFalse() async throws {
        // `getenforce` on an unrooted device says neither, and "permissive" is
        // a very different claim from "we could not tell".
        let backend = StubBackend()
        let answer = await DeviceSettingsRoutes.restrictionsRead(
            body: body(DaemonProtocol.DeviceRequest(serial: "S1")), backend: backend)
        let response = try decode(DeviceSettingsProtocol.RestrictionsResponse.self, answer.body)
        #expect(response.selinuxEnforcing == nil)
    }

    @Test func everyRestrictionKeyResolves() async throws {
        // A loop over the enum rather than five near-identical tests: a key
        // added to the wire without a write path fails here.
        for key in DeviceSettingsProtocol.RestrictionKey.allCases {
            let backend = StubBackend()
            let answer = await DeviceSettingsRoutes.restrictionsWrite(
                body: body(DeviceSettingsProtocol.RestrictionWriteRequest(
                    serial: "S1", key: key.rawValue, on: true)),
                backend: backend)

            #expect(answer.status == 200, "\(key.rawValue) was refused")
            #expect(await backend.log.restrictionWrites == [.toggle(key, on: true)])
        }
    }

    @Test func remountIsAVerbRatherThanAToggle() async throws {
        let backend = StubBackend()
        let answer = await DeviceSettingsRoutes.restrictionsWrite(
            body: body(DeviceSettingsProtocol.RestrictionWriteRequest(
                serial: "S1", key: DeviceSettingsProtocol.RestrictionWriteRequest.remountKey)),
            backend: backend)

        #expect(answer.status == 200)
        #expect(await backend.log.restrictionWrites == [.remountSystemReadWrite])
    }

    @Test func aRestrictionToggleWithoutAValueIsRefused() async throws {
        let backend = StubBackend()
        let answer = await DeviceSettingsRoutes.restrictionsWrite(
            body: body(DeviceSettingsProtocol.RestrictionWriteRequest(
                serial: "S1", key: "stayAwake")),
            backend: backend)

        #expect(answer.status == 400)
        #expect(await backend.log.restrictionWrites.isEmpty)
    }

    @Test func anUnknownRestrictionKeyIsRefused() async {
        let answer = await DeviceSettingsRoutes.restrictionsWrite(
            body: body(DeviceSettingsProtocol.RestrictionWriteRequest(
                serial: "S1", key: "rm -rf /", on: true)),
            backend: StubBackend())
        #expect(answer.status == 400)
    }
}
