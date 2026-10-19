import ADBKit
import Foundation
import Testing

@testable import DaemonCore

/// The phone set-up routes without adb.
///
/// What the routes add over `PhoneAppSetupService` is the wire: the derived
/// answers have to travel (a client deciding "needs set-up" itself would
/// disagree with the Mac about Shizuku being optional), a step the phone
/// refused has to stay a 200, and only an unreadable device is a 502.
@Suite struct PhoneSetupRouteTests {
    private struct Unreachable: Error, LocalizedError {
        var errorDescription: String? { "Device is offline." }
    }

    private actor CallLog {
        private(set) var calls: [String] = []
        func record(_ call: String) { calls.append(call) }
    }

    private struct StubBackend: DaemonBackend {
        let log = CallLog()
        var status = PhoneAppSetupStatus(
            appInstalled: true, appVersion: "0.1.0", sdk: 36,
            requiredPermissions: PhoneAppSetupService.requiredPermissions(sdk: 36),
            grantedPermissions: ["android.permission.DUMP"],
            shizukuInstalled: true, shizukuRunning: false)
        var failure: String?
        var unreachable = false

        func phoneSetupStatus(serial: String) async throws -> PhoneAppSetupStatus {
            if unreachable { throw Unreachable() }
            await log.record("status \(serial)")
            return status
        }

        func setUpPhone(serial: String) async throws -> PhoneAppSetupOutcome {
            if unreachable { throw Unreachable() }
            await log.record("setup \(serial)")
            return PhoneAppSetupOutcome(status: status, failure: failure)
        }
    }

    private let device = DaemonProtocol.encoded(DaemonProtocol.DeviceRequest(serial: "S1"))

    @Test func statusCarriesTheDerivedAnswers() async throws {
        let backend = StubBackend()
        let (code, body) = await PhoneSetupRoutes.status(body: device, backend: backend)

        #expect(code == 200)
        let status = try JSONDecoder().decode(PhoneSetupProtocol.Status.self, from: body)
        #expect(status.appInstalled)
        #expect(status.appVersion == "0.1.0")
        #expect(status.missingPermissions
            == ["android.permission.WRITE_SECURE_SETTINGS", "android.permission.READ_DROPBOX_DATA"])
        #expect(status.needsSetup)
        #expect(await backend.log.calls == ["status S1"])
    }

    @Test func aPhoneWithoutShizukuIsDoneOnceGranted() async throws {
        let all = PhoneAppSetupService.requiredPermissions(sdk: 36)
        let backend = StubBackend(status: PhoneAppSetupStatus(
            appInstalled: true, appVersion: nil, sdk: 36, requiredPermissions: all,
            grantedPermissions: all, shizukuInstalled: false, shizukuRunning: false))
        let (_, body) = await PhoneSetupRoutes.status(body: device, backend: backend)

        let status = try JSONDecoder().decode(PhoneSetupProtocol.Status.self, from: body)
        #expect(!status.needsSetup)
        #expect(status.missingPermissions.isEmpty)
    }

    @Test func aRefusedStepIsAnAnswerNotAnError() async throws {
        let backend = StubBackend(failure: "Shizuku didn't start: fatal: can't start server")
        let (code, body) = await PhoneSetupRoutes.run(body: device, backend: backend)

        #expect(code == 200)
        let run = try JSONDecoder().decode(PhoneSetupProtocol.RunResponse.self, from: body)
        #expect(run.failure == "Shizuku didn't start: fatal: can't start server")
        #expect(run.status.needsSetup)
        #expect(await backend.log.calls == ["setup S1"])
    }

    @Test func aCleanRunCarriesNoFailure() async throws {
        let (code, body) = await PhoneSetupRoutes.run(body: device, backend: StubBackend())
        #expect(code == 200)
        let json = try #require(String(data: body, encoding: .utf8))
        let run = try JSONDecoder().decode(PhoneSetupProtocol.RunResponse.self, from: body)
        #expect(run.failure == nil)
        #expect(!json.contains("\"failure\":\"")) // absent or null, never a string
    }

    @Test func anUnreadableDeviceIs502WithTheServicesWords() async throws {
        let backend = StubBackend(unreachable: true)
        for route in [PhoneSetupRoutes.status, PhoneSetupRoutes.run] {
            let (code, body) = await route(device, backend)
            #expect(code == 502)
            let error = try JSONDecoder().decode(DaemonProtocol.ErrorBody.self, from: body)
            #expect(error.error.code == "adb_failed")
            #expect(error.error.message == "Device is offline.")
        }
    }

    @Test func aBodyWithoutASerialNeverReachesTheDevice() async throws {
        let backend = StubBackend()
        for route in [PhoneSetupRoutes.status, PhoneSetupRoutes.run] {
            let (code, _) = await route(Data("{}".utf8), backend)
            #expect(code == 400)
        }
        #expect(await backend.log.calls.isEmpty)
    }
}
