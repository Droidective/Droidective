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

    func foregroundPackage(serial: String) async throws -> String? { nil }

    func controlApp(
        serial: String, packageId: String, action: AppControlService.AppAction
    ) async throws -> FeatureResult { FeatureResult(ok: true, message: "stub") }

    func deviceProperties(serial: String) async throws -> [String: String] { [:] }

    func reverseTcp(serial: String, port: Int, remove: Bool) async -> AdbResult {
        AdbResult(stdout: "", stderr: "", exitCode: 0, timedOut: false)
    }

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

    func wifi(serial: String) async -> (WifiStatus, [WifiNetwork], Bool) {
        (
            WifiStatus(
                enabled: false, connected: false, ssid: nil, ipAddress: nil,
                linkSpeed: nil, frequency: nil, signal: nil),
            [], false
        )
    }

    func writeWifi(
        serial: String, _ write: NetworkProtocol.WifiWrite
    ) async throws -> AdbResult {
        AdbResult(stdout: "", stderr: "", exitCode: 0, timedOut: false)
    }

    func privateDns(serial: String) async -> DnsStatus {
        DnsStatus(mode: .automatic, hostname: nil)
    }

    func writePrivateDns(
        serial: String, mode: DnsStatus.Mode, hostname: String
    ) async throws -> AdbResult {
        AdbResult(stdout: "", stderr: "", exitCode: 0, timedOut: false)
    }

    func appInfo(serial: String, packageId: String) async throws -> AppInfo { .notInstalled }

    func permissions(serial: String, packageId: String) async throws -> [PermissionEntry] { [] }

    func setPermission(
        serial: String, packageId: String, permission: String, grant: Bool
    ) async throws -> FeatureResult {
        FeatureResult(ok: true, message: "stub")
    }

    func meminfo(serial: String, packageId: String) async throws -> MemInfo {
        MemInfo(running: false, totalPssKb: nil, summary: [])
    }

    func sandboxList(
        serial: String, packageId: String, path: String
    ) async throws -> (entries: [FsEntry], debuggable: Bool) {
        ([], true)
    }

    func sandboxPull(
        serial: String, packageId: String, path: String, to destination: String
    ) async throws -> String { destination }

    func pullApk(
        serial: String, packageId: String, to destination: String
    ) async throws -> [String] { [destination] }

    func emulators() async -> ([Avd], Bool) { ([], true) }

    func emulatorAction(
        _ action: EmulatorProtocol.Action, avd: String, serial: String
    ) async throws -> FeatureResult {
        FeatureResult(ok: true, message: "stub")
    }

    func installPackage(path: String, serial: String) async throws -> FeatureResult {
        FeatureResult(ok: true, message: "stub")
    }

    func pairWireless(host: String, port: String, code: String) async throws -> FeatureResult {
        FeatureResult(ok: true, message: "stub")
    }

    func discoverConnectEndpoint(host: String) async -> WirelessEndpoint? { nil }

    func connectWireless(host: String, port: String) async throws -> FeatureResult {
        FeatureResult(ok: true, message: "stub")
    }

    func disconnectWireless(target: String?) async throws -> FeatureResult {
        FeatureResult(ok: true, message: "stub")
    }

    func enableTcpip(serial: String) async throws -> FeatureResult {
        FeatureResult(ok: true, message: "stub")
    }

    func deepLinks(packageId: String) async -> [DeepLink] { [] }

    func writeDeepLinks(packageId: String, links: [DeepLink]) async throws {}

    func launchDeepLink(serial: String, url: String) async throws -> FeatureResult {
        FeatureResult(ok: true, message: "stub")
    }

    func createBugReport(
        serial: String, packageId: String?, destination: String
    ) async throws -> String { destination }

    func detectTools() async -> [Tool: ToolStatus] { [:] }
}

/// The same trick for `StreamSource`, and for the same reason: a stub testing
/// logcat has no opinion about mirroring.
///
/// `openMirror` throws rather than returning an inert session, because a
/// `ScrcpySession` is only constructible with a real `AdbClient` and there is
/// nothing honest for a stub to hand back. A test that means to exercise the
/// topic overrides this; every other one is saying "not this".
extension StreamSource {
    func openMirror(serial: String) async throws -> ScrcpySession {
        throw StubbedOut.notImplemented
    }
}

enum StubbedOut: Error, CustomStringConvertible {
    case notImplemented

    var description: String { "this source does not implement that topic" }
}
