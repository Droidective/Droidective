import ADBKit
import Foundation
import Testing

@testable import DaemonCore

/// The phone set-up routes without adb or GitHub.
///
/// What the routes add over `PhoneAppSetupService` is the wire: the derived
/// answers have to travel (a client deciding "needs set-up", or "install",
/// itself would disagree with the Mac), the latest release has to be asked
/// beside the phone, the menu's entry is never an error, and only an
/// unreadable device is a 502.
@Suite struct PhoneSetupRouteTests {
    private struct Unreachable: Error, LocalizedError {
        var errorDescription: String? { "Device is offline." }
    }

    private actor CallLog {
        private(set) var calls: [String] = []
        func record(_ call: String) { calls.append(call) }
    }

    private static let release = PhoneAppRelease(
        version: "0.1.1", apkName: "droidective-android-0.1.1.apk",
        apkURL: "https://github.com/x.apk", apkSize: 1, apkDigest: nil)

    private struct StubBackend: DaemonBackend {
        let log = CallLog()
        var status = PhoneAppSetupStatus(
            appInstalled: true, appVersion: "0.1.1", sdk: 36,
            requiredPermissions: PhoneAppSetupService.requiredPermissions(sdk: 36),
            grantedPermissions: ["android.permission.DUMP"],
            shizukuInstalled: true, shizukuRunning: false)
        var latest = PhoneAppReleaseCheck.Lookup.found(PhoneSetupRouteTests.release)
        var offer: PhoneAppOffer?
        var unreachable = false

        func phoneSetupStatus(serial: String) async throws -> PhoneAppSetupStatus {
            if unreachable { throw Unreachable() }
            await log.record("status \(serial)")
            return status
        }

        func phoneSetupOffer(serial: String) async -> PhoneAppOffer? {
            await log.record("offer \(serial)")
            return offer
        }

        func latestPhoneAppRelease(maxAge: TimeInterval) async -> PhoneAppReleaseCheck.Lookup {
            await log.record("latest \(Int(maxAge))")
            return latest
        }
    }

    private let device = DaemonProtocol.encoded(DaemonProtocol.DeviceRequest(serial: "S1"))

    private func read(_ backend: StubBackend) async throws -> PhoneSetupProtocol.Status {
        let (code, body) = await PhoneSetupRoutes.status(body: device, backend: backend)
        #expect(code == 200)
        return try JSONDecoder().decode(PhoneSetupProtocol.Status.self, from: body)
    }

    @Test func statusCarriesTheDerivedAnswers() async throws {
        let backend = StubBackend()
        let status = try await read(backend)

        #expect(status.appInstalled)
        #expect(status.appVersion == "0.1.1")
        #expect(status.sdk == 36)
        #expect(status.missingPermissions
            == ["android.permission.WRITE_SECURE_SETTINGS", "android.permission.READ_DROPBOX_DATA"])
        #expect(status.needsSetup)
        #expect(status.latestVersion == "0.1.1")
        #expect(status.latestProblem == nil)
        #expect(status.step == .none)
        #expect(status.hasWork)
        // The release is asked at the sheet's freshness, not the menu's.
        #expect(await Set(backend.log.calls)
            == ["status S1", "latest \(Int(PhoneAppReleaseCheck.sheetMaxAge))"])
    }

    @Test func aPhoneWithoutTheAppIsToldItWillBeInstalled() async throws {
        let absent = PhoneAppSetupStatus(
            appInstalled: false, appVersion: nil, sdk: 34, requiredPermissions: [],
            grantedPermissions: [], shizukuInstalled: false, shizukuRunning: false)
        let status = try await read(StubBackend(status: absent))

        #expect(status.step == .install)
        #expect(status.hasWork)
        #expect(!status.needsSetup)
        #expect(status.offer?.kind == .install)

        let unreachable = try await read(StubBackend(
            status: absent, latest: .failed("GitHub's anonymous request limit was reached")))
        #expect(unreachable.step == .none)
        #expect(!unreachable.hasWork)
        #expect(unreachable.latestVersion == nil)
        #expect(unreachable.latestProblem == "GitHub's anonymous request limit was reached")
    }

    @Test func anOlderAppIsToldItWillBeUpdated() async throws {
        let all = PhoneAppSetupService.requiredPermissions(sdk: 36)
        let old = PhoneAppSetupStatus(
            appInstalled: true, appVersion: "0.1.0", sdk: 36, requiredPermissions: all,
            grantedPermissions: all, shizukuInstalled: false, shizukuRunning: false)
        let status = try await read(StubBackend(status: old))

        #expect(status.step == .update)
        #expect(status.hasWork)
        #expect(!status.needsSetup)
        #expect(status.offer == PhoneSetupProtocol.Offer(.update(from: "0.1.0", to: "0.1.1")))
    }

    @Test func theMenusOfferCarriesADBKitsWords() async throws {
        let cases: [(PhoneAppOffer?, String)] = [
            (.install, #"{"offer":{"kind":"install","menuTitle":"Install Droidective on This Phone…"}}"#),
            (.update(from: "0.1.0", to: "0.1.1"),
             #"{"offer":{"from":"0.1.0","kind":"update","menuTitle":"Update Droidective on This Phone…","to":"0.1.1"}}"#),
            (.setUp, #"{"offer":{"kind":"setUp","menuTitle":"Set Up Droidective on This Phone…"}}"#),
        ]
        for (offer, json) in cases {
            let (code, body) = await PhoneSetupRoutes.offer(body: device, backend: StubBackend(offer: offer))
            #expect(code == 200)
            let decoded = try JSONDecoder().decode(PhoneSetupProtocol.OfferResponse.self, from: body)
            let expected = try JSONDecoder().decode(
                PhoneSetupProtocol.OfferResponse.self, from: Data(json.utf8))
            #expect(decoded == expected)
        }
    }

    @Test func nothingToOfferIsANullNotAnError() async throws {
        let (code, body) = await PhoneSetupRoutes.offer(body: device, backend: StubBackend())
        #expect(code == 200)
        #expect(try JSONDecoder().decode(PhoneSetupProtocol.OfferResponse.self, from: body).offer == nil)
    }

    @Test func anUnreadableDeviceIs502WithTheServicesWords() async throws {
        let (code, body) = await PhoneSetupRoutes.status(
            body: device, backend: StubBackend(unreachable: true))
        #expect(code == 502)
        let error = try JSONDecoder().decode(DaemonProtocol.ErrorBody.self, from: body)
        #expect(error.error.code == "adb_failed")
        #expect(error.error.message == "Device is offline.")
    }

    @Test func aBodyWithoutASerialNeverReachesTheDevice() async throws {
        let backend = StubBackend()
        for route in [PhoneSetupRoutes.status, PhoneSetupRoutes.offer] {
            let (code, _) = await route(Data("{}".utf8), backend)
            #expect(code == 400)
        }
        #expect(await backend.log.calls.isEmpty)
    }
}
