import Foundation
import Testing
@testable import ADBKit

/// Installs or updates Droidective for Android on a real phone from the real
/// latest GitHub release: the release lookup, the download, the digest and
/// signer checks against the published APK, and `adb install -r`, then the
/// grants. Gated on PHONE_APP_LIVE=1 so it never runs in CI; it changes the
/// phone named by MIRROR_SERIAL.
@Suite struct PhoneAppLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PHONE_APP_LIVE"] == "1"))
    func installsTheLatestReleaseOnARealPhone() async throws {
        let serial = ProcessInfo.processInfo.environment["MIRROR_SERIAL"] ?? "emulator-5554"
        let service = PhoneAppSetupService(
            client: AdbClient(locator: ToolLocator(), runner: SystemProcessRunner(), log: CommandLog()))
        let lookup = await PhoneAppReleaseCheck().latest(maxAge: 0)
        let latest = try #require(lookup.release, "GitHub: \(lookup)")
        print("LIVE latest release: \(latest.version), \(latest.apkSize) bytes, \(latest.apkDigest ?? "no digest")")

        let offer = await service.offer(serial: serial, latest: { latest })
        print("LIVE offer before: \(offer.map(\.menuTitle) ?? "nothing")")

        let outcome = try await service.setUp(serial: serial, release: latest) { stage in
            print("LIVE stage: \(stage.label)")
        }
        print("LIVE outcome: \(outcome.failure ?? "all set"), app \(outcome.status.appVersion ?? "?")")
        #expect(outcome.failure == nil)
        #expect(outcome.status.appVersion == latest.version)
        #expect(outcome.status.permissionsGranted)
        #expect(await service.offer(serial: serial, latest: { latest }) == nil)
    }
}
