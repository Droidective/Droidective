import ADBKit
import Foundation

@testable import DaemonCore

/// Inert defaults for every `DaemonBackend` method, so a route's stub
/// implements only the route it is testing.
///
/// These live in the **test** target on purpose. `DaemonBackend` itself stays
/// exhaustive — `LiveBackend`'s conformance is declared in `DaemonCore`, where
/// these defaults are not visible, so forgetting to wire a new route into it is
/// still a compile error. Only conformances declared *here* pick them up.
///
/// Without this, every new route edited six stubs that had no interest in it,
/// and the cost of adding one was measured in unrelated files.
extension DaemonBackend {
    func listDevices() async -> [Device] { [] }

    func runAction(
        featureID: String, serial: String, platform: DevicePlatform,
        params: [String: FeatureValue]
    ) async -> FeatureResult { FeatureResult(ok: true, message: "stub") }

    func listApps(serial: String) async throws -> [AppListing] { [] }

    func controlApp(
        serial: String, packageId: String, action: AppControlService.AppAction
    ) async throws -> FeatureResult { FeatureResult(ok: true, message: "stub") }

    func deviceProperties(serial: String) async throws -> [String: String] { [:] }

    func rootStatus(serial: String) async -> RootStatus {
        RootStatus(hasRootShell: false, likelyRooted: false, summary: "stub", signals: [])
    }

    func listFiles(serial: String, path: String, asRoot: Bool) async throws -> [FsEntry] { [] }

    func fileOperation(
        serial: String, _ operation: FileProtocol.Operation, asRoot: Bool
    ) async throws -> FeatureResult { FeatureResult(ok: true, message: "stub") }

    func fileInfo(
        serial: String, path: String, asRoot: Bool
    ) async throws -> FileExplorerService.FileInfo? { nil }

    func pullFile(
        serial: String, path: String, to destination: String, asRoot: Bool
    ) async throws -> String { destination }

    func crashes(serial: String) async throws -> [CrashReport] { [] }

    func clearCrashBuffer(serial: String) async throws {}

    func developerSettings(serial: String) async -> DeviceSettingsProtocol.DevState {
        DeviceSettingsProtocol.DevState(toggles: [:], scales: [:])
    }

    func writeDeveloperSetting(
        serial: String, _ write: DeviceSettingsProtocol.DevWrite
    ) async throws -> AdbResult {
        AdbResult(stdout: "", stderr: "", exitCode: 0, timedOut: false)
    }

    func restrictions(serial: String) async -> RestrictionsState {
        RestrictionsState(
            adbInstallVerification: true, packageVerifier: true, stayAwake: false,
            hiddenApiEnforced: true, selinuxEnforcing: nil)
    }

    func writeRestriction(
        serial: String, _ write: DeviceSettingsProtocol.RestrictionWrite
    ) async throws -> AdbResult {
        AdbResult(stdout: "", stderr: "", exitCode: 0, timedOut: false)
    }
}
