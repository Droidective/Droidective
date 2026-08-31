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

    func logcatPid(serial: String, packageId: String) async throws -> Int? { nil }

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

    func apkToolchain() async -> ApkProtocol.Toolchain {
        ApkProtocol.Toolchain(
            aapt2: false, apksigner: false, zipalign: false, java: false, bundletool: false)
    }

    func inspectApk(path: String) async -> ApkReport {
        ApkReport(info: ApkInfo(fileName: "stub.apk", fileSizeBytes: 0))
    }

    func signApk(_ request: ApkProtocol.SignRequest) async throws -> ApkProtocol.SignResponse {
        ApkProtocol.SignResponse(ok: true, message: "stub", output: request.output)
    }

    func convertAab(
        _ request: ApkProtocol.ConvertRequest
    ) async throws -> ApkProtocol.ConvertResponse {
        ApkProtocol.ConvertResponse(path: "\(request.outputDirectory)/universal.apk", sizeBytes: 0)
    }

    func decompileApk(
        _ request: DecompileProtocol.Request
    ) async throws -> DecompileProtocol.Tree {
        DecompileProtocol.Tree(
            root: "/stub", tree: DecompileProtocol.Node(FileNode(name: "stub", path: "/stub")))
    }

    func decompiledFile(
        _ request: DecompileProtocol.FileRequest
    ) async -> DecompileProtocol.FileText? {
        DecompileProtocol.FileText(text: "stub", truncated: false, byteCount: 4)
    }

    func searchDecompiled(
        _ request: DecompileProtocol.SearchRequest
    ) async -> DecompileProtocol.Hits? {
        DecompileProtocol.Hits(hits: [], capped: false)
    }

    func rebuildDecompiled(
        _ request: DecompileProtocol.RebuildRequest
    ) async throws -> DecompileProtocol.RebuildResponse? {
        DecompileProtocol.RebuildResponse(output: request.output)
    }

    func managedTools() async -> DecompileProtocol.ManagedTools {
        DecompileProtocol.ManagedTools(jadx: true, apktool: true)
    }

    func installTool(
        _ tool: DecompileProtocol.Installable
    ) async throws -> DecompileProtocol.InstallResponse {
        DecompileProtocol.InstallResponse(path: "/stub/\(tool.rawValue)")
    }

    func customCommands() async -> [CustomCommand] { [] }

    func writeCustomCommands(_ commands: [CustomCommand]) async throws {}

    func runCustomCommand(
        id: String, serial: String, bundleId: String?
    ) async -> FeatureResult? { nil }

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

    func apiWorkspace() async -> ApiClientData { ApiClientData() }

    func writeApiWorkspace(_ data: ApiClientData) async throws {}

    func sendApiRequest(_ request: ApiClientProtocol.SendRequest) async throws -> ApiSendOutcome {
        ApiSendOutcome(
            response: ApiResponse(
                statusCode: 200, headers: [], body: Data(), elapsedMs: 0, size: 0),
            prepared: PreparedRequest(
                url: request.request.url, method: request.request.method, headers: []))
    }

    func cancelApiSend(sendId: String) async -> Bool { false }

    func apiCode(_ request: ApiClientProtocol.CodeRequest) async -> String { "stub" }

    func parseCurl(_ text: String) async -> CurlImport? { nil }

    func importApiFile(path: String) async throws -> ApiClientProtocol.ImportResponse {
        ApiClientProtocol.ImportResponse(
            collections: [], environments: [], summary: "stub", warnings: [])
    }

    func exportApi(
        _ request: ApiClientProtocol.ExportRequest
    ) async throws -> ApiClientProtocol.ExportResponse {
        ApiClientProtocol.ExportResponse(json: "{}", suggestedName: "stub.json")
    }

    func recordingStatus() async -> RecordProtocol.StatusResponse {
        RecordProtocol.StatusResponse(nil, ffmpegReady: false)
    }

    func startRecording(_ request: RecordProtocol.StartRequest) async throws {}

    func pauseRecording() async throws {}

    func resumeRecording(_ options: RecordProtocol.Options) async throws {}

    func stopRecording() async throws -> DeviceRecorder.Finished {
        DeviceRecorder.Finished(path: "/tmp/stub.mp4", durationSeconds: 0, sizeBytes: 0)
    }

    func managedToolEntries() async -> [ToolStoreProtocol.Entry] { [] }

    func installManagedTool(_ tool: ManagedTool) async throws -> String { "/tmp/stub" }

    func removeManagedTool(_ tool: ManagedTool) async throws {}
}

/// The same trick for `StreamSource`, and for the same reason: a stub testing
/// logcat has no opinion about mirroring.
///
/// `openMirror` throws rather than returning an inert session, because a
/// `ScrcpySession` is only constructible with a real `AdbClient` and there is
/// nothing honest for a stub to hand back. A test that means to exercise the
/// topic overrides this; every other one is saying "not this".
extension StreamSource {
    func openMirror(serial: String, quality: MirrorQuality) async throws -> ScrcpySession {
        throw StubbedOut.notImplemented
    }
}

enum StubbedOut: Error, CustomStringConvertible {
    case notImplemented

    var description: String { "this source does not implement that topic" }
}
