import ADBKit
import Foundation
import NIOConcurrencyHelpers
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOWebSocket

/// What a route needs from the rest of the app. A protocol so the socket tests
/// drive the real HTTP stack against a scripted device list instead of
/// requiring adb on the test host.
public protocol DaemonBackend: Sendable {
    func listDevices() async -> [Device]
    /// Runs a registry feature. The daemon holds no feature knowledge of its
    /// own — this is a straight pass-through to `FeatureEngine`.
    func runAction(
        featureID: String, serial: String, platform: DevicePlatform,
        params: [String: FeatureValue]
    ) async -> FeatureResult
    /// Every installed app on the device, user and system.
    func listApps(serial: String) async throws -> [AppListing]
    /// The package of the frontmost activity, or nil when there is nothing
    /// worth naming. Not an error when absent: the launcher is in front more
    /// often than any app is.
    func foregroundPackage(serial: String) async throws -> String?
    /// One verb against one package.
    func controlApp(
        serial: String, packageId: String, action: AppControlService.AppAction
    ) async throws -> FeatureResult
    /// Every `getprop` key and value on the device.
    func deviceProperties(serial: String) async throws -> [String: String]
    /// Whether this device gives a root shell, and the signals behind the
    /// verdict. Best-effort by design — a probe that fails is a negative
    /// signal, not an error — so it does not throw.
    func rootStatus(serial: String) async -> RootStatus
    /// One directory listing.
    func listFiles(serial: String, path: String, asRoot: Bool) async throws -> [FsEntry]
    /// One mutation against the device's filesystem.
    func fileOperation(
        serial: String, _ operation: FileProtocol.Operation, asRoot: Bool
    ) async throws -> FeatureResult
    /// `stat` for one path; nil when the device could not stat it.
    func fileInfo(
        serial: String, path: String, asRoot: Bool
    ) async throws -> FileExplorerService.FileInfo?
    /// Pulls one device path to a host file path, answering where it landed.
    func pullFile(
        serial: String, path: String, to destination: String, asRoot: Bool
    ) async throws -> String
    /// Every crash the device has recorded, newest first.
    func crashes(serial: String) async throws -> [CrashReport]
    /// Empties the device's crash buffer.
    func clearCrashBuffer(serial: String) async throws
    /// Every Developer Options toggle and animation scale, as the device
    /// currently reports them. Best-effort like the service it wraps — a key
    /// the device refuses reads as its default rather than failing the panel.
    func developerSettings(serial: String) async -> DeviceSettingsProtocol.DevState
    /// Writes one Developer Options row.
    func writeDeveloperSetting(
        serial: String, _ write: DeviceSettingsProtocol.DevWrite
    ) async throws -> AdbResult
    /// The dev-time restriction toggles.
    func restrictions(serial: String) async -> RestrictionsState
    /// Writes one restriction, or remounts the system partition.
    func writeRestriction(
        serial: String, _ write: DeviceSettingsProtocol.RestrictionWrite
    ) async throws -> AdbResult
    /// The Wi-Fi screen's whole read: the connection, the saved networks (with
    /// their passwords when `su` allows it), and whether it did.
    func wifi(serial: String) async -> (WifiStatus, [WifiNetwork], Bool)
    /// Toggles the radio, or connects to a network.
    func writeWifi(
        serial: String, _ write: NetworkProtocol.WifiWrite
    ) async throws -> AdbResult
    /// The device's Private DNS mode and hostname.
    func privateDns(serial: String) async -> DnsStatus
    /// Sets the Private DNS mode. `hostname` is used only by `.hostname`.
    func writePrivateDns(
        serial: String, mode: DnsStatus.Mode, hostname: String
    ) async throws -> AdbResult
    /// Version, SDK levels, install dates and APK size for one package.
    func appInfo(serial: String, packageId: String) async throws -> AppInfo
    /// The package's runtime permissions and whether each is granted.
    func permissions(serial: String, packageId: String) async throws -> [PermissionEntry]
    /// Grants or revokes one runtime permission.
    func setPermission(
        serial: String, packageId: String, permission: String, grant: Bool
    ) async throws -> FeatureResult
    /// `dumpsys meminfo` for one package.
    func meminfo(serial: String, packageId: String) async throws -> MemInfo
    /// One directory inside a debuggable app's sandbox, via `run-as`.
    func sandboxList(
        serial: String, packageId: String, path: String
    ) async throws -> (entries: [FsEntry], debuggable: Bool)
    /// Pulls one file out of the sandbox to a host path.
    func sandboxPull(
        serial: String, packageId: String, path: String, to destination: String
    ) async throws -> String
    /// Pulls the package's APK — and its splits, if it has any.
    func pullApk(
        serial: String, packageId: String, to destination: String
    ) async throws -> [String]
    /// Every AVD on this machine, and whether the emulator binary is here at
    /// all. Best-effort: a missing emulator is a state the screen explains,
    /// not an error.
    func emulators() async -> ([Avd], Bool)
    /// Launches, cold-boots, wipes, relaunches or stops one AVD.
    func emulatorAction(
        _ action: EmulatorProtocol.Action, avd: String, serial: String
    ) async throws -> FeatureResult
    /// Installs one host-side package onto one device. Throws only when the
    /// file cannot be processed at all; an install adb *ran* and rejected
    /// comes back as a failed result carrying adb's own reason.
    func installPackage(path: String, serial: String) async throws -> FeatureResult
    /// Android 11+ pairing. `port` is the *pairing* port, which is not the
    /// connection port and changes every session.
    func pairWireless(host: String, port: String, code: String) async throws -> FeatureResult
    /// The connect endpoint a freshly paired device advertises over mDNS.
    /// Best-effort — nil covers "this adb has mDNS off" and "nothing matching
    /// turned up", both of which the sheet handles by asking for the port.
    func discoverConnectEndpoint(host: String) async -> WirelessEndpoint?
    func connectWireless(host: String, port: String) async throws -> FeatureResult
    /// `adb disconnect`. A nil target drops every wireless device.
    func disconnectWireless(target: String?) async throws -> FeatureResult
    /// `adb tcpip 5555` on a USB device, then connect to its Wi-Fi address.
    func enableTcpip(serial: String) async throws -> FeatureResult
    /// `adb reverse tcp:<port> tcp:<port>` on one device, or its removal.
    ///
    /// Narrow on purpose. What the Reactotron relay needs is this one tunnel,
    /// and a general "run any adb command" on the backend would be a far wider
    /// surface than any screen asks for.
    func reverseTcp(serial: String, port: Int, remove: Bool) async -> AdbResult
    /// One app's saved deep links. Best-effort: a store that will not load
    /// reads as no links rather than failing the screen.
    func deepLinks(packageId: String) async -> [DeepLink]
    /// Replaces one app's list. Throws only when the store cannot be written.
    func writeDeepLinks(packageId: String, links: [DeepLink]) async throws
    /// `am start -a android.intent.action.VIEW -d <url>` on one device.
    func launchDeepLink(serial: String, url: String) async throws -> FeatureResult
    /// Which of the APK tools this machine has.
    func apkToolchain() async -> ApkProtocol.Toolchain
    /// Reads what it can from an APK. Best-effort by construction: without
    /// aapt2 it still answers a name and a size, with `hasDetails` false.
    func inspectApk(path: String) async -> ApkReport
    /// Zipaligns and signs. Throws when a tool it needs is absent.
    func signApk(_ request: ApkProtocol.SignRequest) async throws -> ApkProtocol.SignResponse
    /// Builds a universal APK from a bundle. Throws when bundletool or Java is
    /// absent.
    func convertAab(_ request: ApkProtocol.ConvertRequest) async throws
        -> ApkProtocol.ConvertResponse
    /// Runs jadx or apktool and walks what it wrote. Throws when a tool it
    /// needs is absent, or when the decompiler produced nothing.
    func decompileApk(_ request: DecompileProtocol.Request) async throws
        -> DecompileProtocol.Tree
    /// One decompiled file's text, or nil when the path is not inside a
    /// decompile output directory — which is a refusal, not an empty file.
    func decompiledFile(_ request: DecompileProtocol.FileRequest) async
        -> DecompileProtocol.FileText?
    /// Searches one decompile's output. Nil for the same refusal.
    func searchDecompiled(_ request: DecompileProtocol.SearchRequest) async
        -> DecompileProtocol.Hits?
    /// Rebuilds an apktool tree back into an APK. Nil for the same refusal;
    /// throws when apktool or Java is absent, or the build fails.
    func rebuildDecompiled(_ request: DecompileProtocol.RebuildRequest) async throws
        -> DecompileProtocol.RebuildResponse?
    /// The saved custom commands. Best-effort: a store that will not load
    /// reads as no commands rather than failing the screen.
    func customCommands() async -> [CustomCommand]
    /// Replaces the whole list. Throws only when the store cannot be written.
    func writeCustomCommands(_ commands: [CustomCommand]) async throws
    /// Runs one saved command, or nil when no command has that id — which is a
    /// 404 rather than a failed run, because nothing was attempted.
    func runCustomCommand(
        id: String, serial: String, bundleId: String?
    ) async -> FeatureResult?
    /// Builds the bug-report zip into a host folder, answering where it landed.
    func createBugReport(
        serial: String, packageId: String?, destination: String
    ) async throws -> String
    /// Which external tools are installed, with an install hint for each that
    /// is not. Best-effort by construction — a tool that cannot be found is the
    /// answer, not an error.
    func detectTools() async -> [Tool: ToolStatus]
}

/// `DeviceMonitor` in production.
public struct LiveBackend: DaemonBackend {
    private let monitor: DeviceMonitor
    private let engine: FeatureEngine
    /// The app services are cheap value types over this, so they are built per
    /// call rather than held — there is no state to keep.
    private let client: AdbClient
    private let emulatorService: EmulatorService
    private let locator: ToolLocator
    /// The same on-disk stores the Mac app uses, under the shared support dir.
    private let deepLinkStore: JSONStore<DeepLinksMap>
    private let customCommandStore: JSONStore<[CustomCommand]>
    /// The APK tools, over the same managed-tool directory the feature engine
    /// uses — one download of jadx or bundletool serves both.
    private let apkToolchainValue: ApkToolchain
    /// Where jadx and apktool write, and the only tree the read/search/rebuild
    /// routes may touch. Its own directory rather than the tools one: this is
    /// throwaway output, regenerable from the APK.
    private let decompileCache: URL

    public init(
        monitor: DeviceMonitor, engine: FeatureEngine, client: AdbClient,
        emulators: EmulatorService, locator: ToolLocator,
        deepLinks: JSONStore<DeepLinksMap>,
        customCommands: JSONStore<[CustomCommand]>,
        toolsDirectory: URL
    ) {
        self.monitor = monitor
        self.engine = engine
        self.client = client
        emulatorService = emulators
        self.locator = locator
        deepLinkStore = deepLinks
        customCommandStore = customCommands
        apkToolchainValue = ApkToolchain(
            locator: locator, store: ManagedToolStore(rootDirectory: toolsDirectory))
        decompileCache = AppPaths.decompiledCacheDir
    }

    public func listDevices() async -> [Device] { await monitor.list(force: true) }

    public func runAction(
        featureID: String, serial: String, platform: DevicePlatform,
        params: [String: FeatureValue]
    ) async -> FeatureResult {
        await engine.run(
            featureID: featureID, serial: serial, platform: platform, params: params)
    }

    public func listApps(serial: String) async throws -> [AppListing] {
        try await AppsExplorerService(client: client).listAll(serial: serial)
    }

    public func foregroundPackage(serial: String) async throws -> String? {
        try await AppInspectionService(client: client).getForegroundPackage(serial: serial)
    }

    public func controlApp(
        serial: String, packageId: String, action: AppControlService.AppAction
    ) async throws -> FeatureResult {
        try await AppControlService(client: client)
            .control(serial: serial, packageId: packageId, action: action)
    }

    public func deviceProperties(serial: String) async throws -> [String: String] {
        try await DeviceProps.all(client: client, serial: serial)
    }

    public func rootStatus(serial: String) async -> RootStatus {
        await RootService(client: client).detect(serial: serial)
    }

    public func listFiles(serial: String, path: String, asRoot: Bool) async throws -> [FsEntry] {
        try await FileExplorerService(client: client).list(serial: serial, dir: path, asRoot: asRoot)
    }

    public func fileOperation(
        serial: String, _ operation: FileProtocol.Operation, asRoot: Bool
    ) async throws -> FeatureResult {
        let explorer = FileExplorerService(client: client)
        switch operation {
        case .makeDirectory(let path):
            return try await explorer.makeDirectory(serial: serial, path: path, asRoot: asRoot)
        case .delete(let path):
            return try await explorer.delete(serial: serial, path: path, asRoot: asRoot)
        case .copy(let source, let destination):
            return try await explorer.copy(
                serial: serial, from: source, toDir: destination, asRoot: asRoot)
        case .move(let source, let destination):
            return try await explorer.move(
                serial: serial, from: source, toDir: destination, asRoot: asRoot)
        }
    }

    public func fileInfo(
        serial: String, path: String, asRoot: Bool
    ) async throws -> FileExplorerService.FileInfo? {
        try await FileExplorerService(client: client).info(
            serial: serial, path: path, asRoot: asRoot)
    }

    public func pullFile(
        serial: String, path: String, to destination: String, asRoot: Bool
    ) async throws -> String {
        try await FileExplorerService(client: client).pull(
            serial: serial, path: path, to: URL(fileURLWithPath: destination), asRoot: asRoot
        ).path
    }

    public func crashes(serial: String) async throws -> [CrashReport] {
        try await CrashExtractor(client: client).crashes(serial: serial)
    }

    public func clearCrashBuffer(serial: String) async throws {
        try await CrashExtractor(client: client).clearCrashBuffer(serial: serial)
    }

    public func developerSettings(serial: String) async -> DeviceSettingsProtocol.DevState {
        let service = DeveloperSettingsService(client: client)
        return DeviceSettingsProtocol.DevState(
            toggles: await service.readToggles(serial: serial),
            scales: await service.readScales(serial: serial))
    }

    public func writeDeveloperSetting(
        serial: String, _ write: DeviceSettingsProtocol.DevWrite
    ) async throws -> AdbResult {
        let service = DeveloperSettingsService(client: client)
        switch write {
        case .toggle(let toggle, let on):
            return try await service.set(toggle, on: on, serial: serial)
        case .scale(let scale, let value):
            return try await service.setScale(scale, value: value, serial: serial)
        }
    }

    public func restrictions(serial: String) async -> RestrictionsState {
        await RestrictionsService(client: client).current(serial: serial)
    }

    public func writeRestriction(
        serial: String, _ write: DeviceSettingsProtocol.RestrictionWrite
    ) async throws -> AdbResult {
        let service = RestrictionsService(client: client)
        switch write {
        case .remountSystemReadWrite:
            return try await service.remountSystemReadWrite(serial: serial)
        case .toggle(let key, let on):
            switch key {
            case .adbInstallVerification:
                return try await service.setAdbInstallVerification(serial: serial, on)
            case .packageVerifier:
                return try await service.setPackageVerifier(serial: serial, on)
            case .stayAwake:
                return try await service.setStayAwake(serial: serial, on)
            case .hiddenApiEnforced:
                return try await service.setHiddenApiEnforced(serial: serial, on)
            case .selinuxEnforcing:
                return try await service.setSelinuxEnforcing(serial: serial, on)
            }
        }
    }

    /// The Mac's `WiFiView.load`, moved down a layer.
    ///
    /// The password merge is here rather than in the client because it is the
    /// same join on both platforms: `cmd wifi list-networks` names the saved
    /// networks and `WifiConfigStore.xml` holds their secrets, and a network
    /// that only appears in the store still belongs in the list.
    public func wifi(serial: String) async -> (WifiStatus, [WifiNetwork], Bool) {
        let service = WifiService(client: client)
        let status = await service.status(serial: serial)
        var networks = await service.savedNetworks(serial: serial)
        let rooted = await RootService(client: client).detect(serial: serial).hasRootShell
        guard rooted else { return (status, networks, false) }

        let credentials = await service.savedPasswords(serial: serial)
        var bySSID: [String: String] = [:]
        for credential in credentials where credential.password != nil {
            bySSID[credential.ssid] = credential.password
        }
        networks = networks.map { network in
            var network = network
            network.password = bySSID[network.ssid]
            return network
        }
        let known = Set(networks.map(\.ssid))
        for credential in credentials where !known.contains(credential.ssid) {
            networks.append(WifiNetwork(
                networkId: nil, ssid: credential.ssid, security: credential.security,
                password: credential.password))
        }
        return (status, networks, true)
    }

    public func writeWifi(
        serial: String, _ write: NetworkProtocol.WifiWrite
    ) async throws -> AdbResult {
        let service = WifiService(client: client)
        switch write {
        case .setEnabled(let on):
            return try await service.setEnabled(serial: serial, on)
        case .connect(let ssid, let security, let password):
            return try await service.connect(
                serial: serial, ssid: ssid, security: security, password: password)
        }
    }

    public func privateDns(serial: String) async -> DnsStatus {
        await DnsService(client: client).current(serial: serial)
    }

    public func writePrivateDns(
        serial: String, mode: DnsStatus.Mode, hostname: String
    ) async throws -> AdbResult {
        let service = DnsService(client: client)
        switch mode {
        case .off: return try await service.setOff(serial: serial)
        case .automatic: return try await service.setAutomatic(serial: serial)
        case .hostname: return try await service.setHostname(serial: serial, hostname)
        }
    }

    private var inspection: AppInspectionService { AppInspectionService(client: client) }

    public func appInfo(serial: String, packageId: String) async throws -> AppInfo {
        try await inspection.getAppInfo(serial: serial, packageId: packageId)
    }

    public func permissions(serial: String, packageId: String) async throws -> [PermissionEntry] {
        try await inspection.listPermissions(serial: serial, packageId: packageId)
    }

    public func setPermission(
        serial: String, packageId: String, permission: String, grant: Bool
    ) async throws -> FeatureResult {
        try await inspection.setPermission(
            serial: serial, packageId: packageId, permission: permission, grant: grant)
    }

    public func meminfo(serial: String, packageId: String) async throws -> MemInfo {
        try await inspection.getMemInfo(serial: serial, packageId: packageId)
    }

    public func sandboxList(
        serial: String, packageId: String, path: String
    ) async throws -> (entries: [FsEntry], debuggable: Bool) {
        try await inspection.sandboxList(serial: serial, packageId: packageId, dir: path)
    }

    public func sandboxPull(
        serial: String, packageId: String, path: String, to destination: String
    ) async throws -> String {
        try await inspection.sandboxPull(
            serial: serial, packageId: packageId, filePath: path,
            to: URL(fileURLWithPath: destination)
        ).path
    }

    public func pullApk(
        serial: String, packageId: String, to destination: String
    ) async throws -> [String] {
        try await inspection.pullApk(
            serial: serial, packageId: packageId, to: URL(fileURLWithPath: destination)
        ).map(\.path)
    }

    public func emulators() async -> ([Avd], Bool) {
        let service = emulatorService
        guard await service.emulatorInstalled() else { return ([], false) }
        return (await service.listAvds(devices: await monitor.list(force: false)), true)
    }

    public func emulatorAction(
        _ action: EmulatorProtocol.Action, avd: String, serial: String
    ) async throws -> FeatureResult {
        let service = emulatorService
        switch action {
        case .launch:
            return await service.launch(avd: avd)
        case .coldBoot:
            return await service.launch(
                avd: avd, options: EmulatorService.LaunchOptions(coldBoot: true))
        case .wipeData:
            return await service.wipeData(avd: avd)
        case .stop:
            return try await service.stop(serial: serial)
        case .relaunch:
            _ = try? await service.stop(serial: serial)
            await waitForShutdown(serial: serial)
            return await service.launch(avd: avd)
        }
    }

    /// Waits for a stopping emulator to actually go away.
    ///
    /// The Mac polls `EmulatorService.consolePID`, which shells out to
    /// `/usr/sbin/lsof` — a macOS path, so it would answer nil on Linux and
    /// Windows and the relaunch would fire while the console port was still
    /// held. Asking adb is portable *and* the better question: what matters is
    /// whether the emulator is still a device, and adb is the authority on
    /// that. Twenty seconds, as the Mac waits.
    public func installPackage(path: String, serial: String) async throws -> FeatureResult {
        try await AppBundleInstallService(
            client: client,
            toolchain: ApkToolchain(locator: locator, store: engine.managedTools)
        ).install(bundlePath: path, serial: serial)
    }

    /// One value type over the client and the monitor, built per call like the
    /// rest — the connect/pair verbs hold no state, they only invalidate the
    /// monitor's cache so a new device shows up without waiting for a poll.
    private var connection: ConnectionService {
        ConnectionService(client: client, monitor: monitor)
    }

    public func pairWireless(
        host: String, port: String, code: String
    ) async throws -> FeatureResult {
        try await connection.pair(host: host, port: port, code: code)
    }

    public func discoverConnectEndpoint(host: String) async -> WirelessEndpoint? {
        await connection.discoverConnectEndpoint(host: host)
    }

    public func connectWireless(host: String, port: String) async throws -> FeatureResult {
        try await connection.connect(host: host, port: port)
    }

    public func disconnectWireless(target: String?) async throws -> FeatureResult {
        try await connection.disconnect(target: target)
    }

    public func reverseTcp(serial: String, port: Int, remove: Bool) async -> AdbResult {
        let arguments =
            remove
            ? ["reverse", "--remove", "tcp:\(port)"]
            : ["reverse", "tcp:\(port)", "tcp:\(port)"]
        do {
            return try await client.run(on: serial, arguments)
        } catch {
            // Only `.adbNotFound` throws, and a Doctor that cannot find adb is a
            // better place to say so than a tunnel that failed for it.
            return AdbResult(stdout: "", stderr: "\(error)", exitCode: nil, timedOut: false)
        }
    }

    public func enableTcpip(serial: String) async throws -> FeatureResult {
        try await connection.enableTcpip(serial: serial)
    }

    public func deepLinks(packageId: String) async -> [DeepLink] {
        await deepLinkStore.load()[packageId] ?? []
    }

    public func writeDeepLinks(packageId: String, links: [DeepLink]) async throws {
        // One key of the map at a time, atomically — the Mac's own `persist`,
        // so two apps writing different apps' links cannot lose each other's.
        try await deepLinkStore.update { $0[packageId] = links }
    }

    public func launchDeepLink(serial: String, url: String) async throws -> FeatureResult {
        try await AppControlService(client: client).launchDeepLink(serial: serial, url: url)
    }

    public func apkToolchain() async -> ApkProtocol.Toolchain {
        let toolchain = apkToolchainValue
        async let aapt2 = toolchain.aapt2()
        async let apksigner = toolchain.apksignerJar()
        async let zipalign = toolchain.zipalign()
        async let java = toolchain.java()
        async let bundletool = toolchain.bundletool()
        return await ApkProtocol.Toolchain(
            aapt2: aapt2 != nil, apksigner: apksigner != nil, zipalign: zipalign != nil,
            java: java != nil, bundletool: bundletool != nil)
    }

    public func inspectApk(path: String) async -> ApkReport {
        await ApkInspectionService(client: client, toolchain: apkToolchainValue)
            .inspect(apkPath: path)
    }

    public func signApk(
        _ request: ApkProtocol.SignRequest
    ) async throws -> ApkProtocol.SignResponse {
        let result = try await ApkSigningService(toolchain: apkToolchainValue).sign(
            input: request.input, output: request.output,
            credentials: request.keystore.credentials)
        return ApkProtocol.SignResponse(
            ok: result.ok, message: result.message, output: result.ok ? request.output : nil)
    }

    public func convertAab(
        _ request: ApkProtocol.ConvertRequest
    ) async throws -> ApkProtocol.ConvertResponse {
        let converted = try await AabConvertService(toolchain: apkToolchainValue).convert(
            aabPath: request.input,
            outputDirectory: URL(fileURLWithPath: request.outputDirectory),
            credentials: request.keystore?.credentials)
        return ApkProtocol.ConvertResponse(
            path: converted.url.path, sizeBytes: converted.sizeBytes)
    }

    public func decompileApk(
        _ request: DecompileProtocol.Request
    ) async throws -> DecompileProtocol.Tree {
        let root = try await DecompileService(toolchain: apkToolchainValue).decompile(
            apkPath: request.path, mode: request.mode.service,
            into: decompileCache, reuseExisting: request.refresh != true)
        return DecompileProtocol.Tree(
            root: root.path, tree: DecompileProtocol.Node(DecompileService.tree(at: root)))
    }

    public func decompiledFile(
        _ request: DecompileProtocol.FileRequest
    ) async -> DecompileProtocol.FileText? {
        guard confinedToOutput(request.path, root: request.root) else { return nil }
        guard let data = FileManager.default.contents(atPath: request.path) else {
            return DecompileProtocol.FileText(text: "", truncated: false, byteCount: 0)
        }
        let capped = data.prefix(DecompileProtocol.maxFileBytes)
        // Lossy on purpose: smali and decoded resources are text, but a stray
        // byte in one is not a reason to show nothing.
        let text = String(decoding: capped, as: UTF8.self)
        return DecompileProtocol.FileText(
            text: text, truncated: data.count > capped.count, byteCount: data.count)
    }

    public func searchDecompiled(
        _ request: DecompileProtocol.SearchRequest
    ) async -> DecompileProtocol.Hits? {
        guard confinedToOutput(request.root, root: request.root) else { return nil }
        let hits = DecompileService.search(
            in: URL(fileURLWithPath: request.root), query: request.query,
            maxResults: DecompileProtocol.maxHits)
        return DecompileProtocol.Hits(
            hits: hits.map(DecompileProtocol.Hit.init),
            capped: hits.count >= DecompileProtocol.maxHits)
    }

    public func rebuildDecompiled(
        _ request: DecompileProtocol.RebuildRequest
    ) async throws -> DecompileProtocol.RebuildResponse? {
        guard confinedToOutput(request.sourceDir, root: request.root) else { return nil }
        try await DecompileService(toolchain: apkToolchainValue).rebuild(
            sourceDir: request.sourceDir, to: request.output)
        return DecompileProtocol.RebuildResponse(output: request.output)
    }

    /// Both halves of the confinement: the root really is one of ours, and the
    /// path really is inside it. Checking only the second would be circular —
    /// a client naming `/` as the root would pass it.
    private func confinedToOutput(_ path: String, root: String) -> Bool {
        DecompileProtocol.isOutputRoot(root, cache: decompileCache)
            && DecompileProtocol.confined(path, to: root)
    }

    public func customCommands() async -> [CustomCommand] {
        await customCommandStore.load()
    }

    public func writeCustomCommands(_ commands: [CustomCommand]) async throws {
        try await customCommandStore.save(commands)
    }

    public func runCustomCommand(
        id: String, serial: String, bundleId: String?
    ) async -> FeatureResult? {
        guard let command = await customCommandStore.load().first(where: { $0.id == id }) else {
            return nil
        }
        // `runsInTerminal` is deliberately ignored here. A terminal command is
        // typed into a shell the *client* owns, so the daemon running it
        // headlessly would be a different thing than the one that was asked
        // for — the desktop app opens its Terminal tab instead, and only sends
        // the silent ones here.
        return await CustomCommandService(client: client).run(
            command: command, bundleId: bundleId, serial: serial)
    }

    public func createBugReport(
        serial: String, packageId: String?, destination: String
    ) async throws -> String {
        try await BugReportService(client: client).create(
            serial: serial, packageId: packageId,
            into: URL(fileURLWithPath: destination)
        ).path
    }

    public func detectTools() async -> [Tool: ToolStatus] {
        await ToolDetectionService(locator: locator).detectAll()
    }

    private func waitForShutdown(serial: String) async {
        for _ in 0 ..< 20 {
            let devices = await monitor.list(force: true)
            if !devices.contains(where: { $0.serial == serial }) { return }
            try? await Task.sleep(for: .seconds(1))
        }
    }
}

/// Loopback HTTP for the request/response half of the protocol.
///
/// Streams will ride a WebSocket on this same listener (topic-multiplexed, with
/// the decided drop-oldest policy); this slice is the request path only.
public actor DaemonServer {
    public struct Bound: Sendable {
        public let port: Int
    }

    /// Named so the WebSocket upgrade can take it back out of the pipeline.
    fileprivate static let routesHandlerName = "droidectived.routes"


    private let backend: any DaemonBackend
    private let streamSource: (any StreamSource)?
    private let token: String
    private var group: MultiThreadedEventLoopGroup?
    private var channel: (any Channel)?
    /// Live client connections.
    ///
    /// `shutdownGracefully` waits for every channel to close, and a stream
    /// socket stays open until its client goes away — so without closing these
    /// first, stopping the daemon while anything is subscribed never returns.
    /// The UI kills the daemon on quit, so a stop that hangs is a stop that
    /// gets SIGKILLed with adb children still running.
    private let connections = ConnectionRegistry()

    public init(
        backend: any DaemonBackend, token: String, streamSource: (any StreamSource)? = nil
    ) {
        self.backend = backend
        self.streamSource = streamSource
        self.token = token
    }

    /// Binds 127.0.0.1 on `port` (0 → the OS picks) and starts serving.
    public func start(port: Int) async throws -> Bound {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.group = group
        let backend = self.backend
        let streamSource = self.streamSource
        let token = self.token
        // Captured by the handler so `Host` can be pinned to the live port,
        // which is only known after bind.
        let boundPort = NIOLockedValueBox(0)

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(.backlog, value: 32)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { [connections] channel in
                connections.add(channel)
                channel.closeFuture.whenComplete { _ in connections.remove(channel) }
                // The stream socket rides the same listener as the routes, so
                // there is one port, one token and one origin policy rather
                // than two things to keep in agreement.
                let upgrader = NIOWebSocketServerUpgrader(
                    shouldUpgrade: { channel, head in
                        // Auth on the *upgrade* request. Checking after the
                        // handshake would leave an authenticated-looking socket
                        // open to anything that can reach the port.
                        let port = boundPort.withLockedValue { $0 }
                        let refused = DaemonGuards.check(
                            authorization: head.headers.first(name: "Authorization"),
                            host: head.headers.first(name: "Host"),
                            origin: head.headers.first(name: "Origin"),
                            port: port, expectedToken: token)
                        guard refused == nil, head.uri == DaemonProtocol.streamPath,
                              streamSource != nil
                        else { return channel.eventLoop.makeSucceededFuture(nil) }
                        return channel.eventLoop.makeSucceededFuture(HTTPHeaders())
                    },
                    upgradePipelineHandler: { channel, _ in
                        guard let streamSource else {
                            return channel.eventLoop.makeSucceededFuture(())
                        }
                        // The route handler sits after the HTTP codec, which
                        // NIO removes on upgrade — but not handlers added
                        // behind it. Left in place it would be handed
                        // WebSocket frames and trap trying to read them as
                        // HTTP.
                        return channel.pipeline.removeHandler(name: Self.routesHandlerName)
                            .recover { _ in }
                            .flatMap { _ -> EventLoopFuture<Void> in
                                let session = StreamSession(
                                    sink: WebSocketSink(channel: channel), source: streamSource)
                                return channel.eventLoop.makeCompletedFuture {
                                    try channel.pipeline.syncOperations.addHandler(
                                        WebSocketHandler(session: session))
                                }
                            }
                    })

                return channel.pipeline.configureHTTPServerPipeline(
                    withServerUpgrade: (upgraders: [upgrader], completionHandler: { _ in })
                ).flatMapThrowing {
                    try channel.pipeline.syncOperations.addHandler(
                        RequestHandler(backend: backend, token: token, port: boundPort),
                        name: Self.routesHandlerName)
                }
            }

        // Loopback only. Nothing reaches this from another host, by construction
        // rather than by firewall.
        let channel = try await bootstrap.bind(host: "127.0.0.1", port: port).get()
        self.channel = channel
        let resolved = channel.localAddress?.port ?? port
        boundPort.withLockedValue { $0 = resolved }
        return Bound(port: resolved)
    }

    public func stop() async {
        // Stop accepting first, then hang up on everyone still connected, then
        // shut the loops down. Any other order either races new connections in
        // or waits forever on old ones.
        try? await channel?.close().get()
        channel = nil
        for connection in connections.drain() {
            try? await connection.close().get()
        }
        try? await group?.shutdownGracefully()
        group = nil
    }
}

/// Thread-safe set of open child channels. Identity-keyed, since `Channel` is
/// a reference type with no useful equality of its own.
private final class ConnectionRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var channels: [ObjectIdentifier: any Channel] = [:]

    func add(_ channel: any Channel) {
        lock.lock()
        channels[ObjectIdentifier(channel)] = channel
        lock.unlock()
    }

    func remove(_ channel: any Channel) {
        lock.lock()
        channels[ObjectIdentifier(channel)] = nil
        lock.unlock()
    }

    /// Everything currently open, clearing the registry.
    func drain() -> [any Channel] {
        lock.lock()
        defer {
            channels.removeAll()
            lock.unlock()
        }
        return Array(channels.values)
    }
}

/// One request at a time per connection: collect the head, ignore the body
/// (every route takes its arguments in the path for this slice), answer.
private final class RequestHandler: ChannelInboundHandler, RemovableChannelHandler,
    @unchecked Sendable
{
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let backend: any DaemonBackend
    private let token: String
    private let port: NIOLockedValueBox<Int>
    private var head: HTTPRequestHead?
    private var body = ByteBufferAllocator().buffer(capacity: 0)

    init(backend: any DaemonBackend, token: String, port: NIOLockedValueBox<Int>) {
        self.backend = backend
        self.token = token
        self.port = port
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            self.head = head
        case .body(var buffer):
            body.writeBuffer(&buffer)
        case .end:
            guard let head else { return }
            self.head = nil
            let body = self.body
            self.body = ByteBufferAllocator().buffer(capacity: 0)
            let loop = context.eventLoop
            let boxedContext = NIOLoopBound(context, eventLoop: loop)
            let port = self.port.withLockedValue { $0 }
            let backend = self.backend
            let token = self.token
            // The route is async; hop the answer back onto the event loop.
            Task { [self] in
                let (status, responseBody) = await Self.respond(
                    head: head, body: body, port: port, token: token, backend: backend)
                loop.execute {
                    self.write(context: boxedContext.value, status: status, body: responseBody)
                }
            }
        }
    }

    /// Pure-ish routing: guards, then the route. Split out so the socket tests
    /// and any future unit test exercise the same decision path.
    static func respond(
        head: HTTPRequestHead, body: ByteBuffer, port: Int, token: String,
        backend: any DaemonBackend
    ) async -> (HTTPResponseStatus, Data) {
        func encoded(_ body: some Encodable) -> Data { DaemonProtocol.encoded(body) }

        if let refusal = DaemonGuards.check(
            authorization: head.headers.first(name: "Authorization"),
            host: head.headers.first(name: "Host"),
            origin: head.headers.first(name: "Origin"),
            port: port, expectedToken: token
        ) {
            return (
                HTTPResponseStatus(statusCode: DaemonProtocol.status(for: refusal)),
                encoded(DaemonProtocol.errorBody(for: refusal))
            )
        }
        guard head.method == .POST else {
            return (.methodNotAllowed, encoded(DaemonProtocol.methodNotAllowed))
        }
        guard let route = DaemonProtocol.Route(rawValue: head.uri) else {
            return (.notFound, encoded(DaemonProtocol.notFound))
        }
        switch route {
        case .devicesList:
            let devices = await backend.listDevices()
            return (.ok, encoded(DaemonProtocol.DevicesResponse(devices: devices)))

        case .featuresList:
            return (.ok, encoded(ActionProtocol.features()))

        case .deviceProps:
            let raw = Data(body.readableBytesView)
            guard let request = try? JSONDecoder().decode(
                DaemonProtocol.DeviceRequest.self, from: raw)
            else { return (.badRequest, encoded(DaemonProtocol.badRequest)) }
            do {
                let properties = try await backend.deviceProperties(serial: request.serial)
                return (.ok, encoded(DaemonProtocol.DevicePropsResponse(properties: properties)))
            } catch {
                // adb's answer, not a daemon fault — the same 502 the app
                // list uses, carrying adb's own words.
                return (.badGateway, encoded(DaemonProtocol.ErrorBody(
                    code: "adb_failed", message: "Could not read the device properties.",
                    detail: "\(error)")))
            }

        case .deviceRoot:
            let raw = Data(body.readableBytesView)
            guard let request = try? JSONDecoder().decode(
                DaemonProtocol.DeviceRequest.self, from: raw)
            else { return (.badRequest, encoded(DaemonProtocol.badRequest)) }
            // Best-effort by construction: a probe the device refuses is a
            // negative signal, so there is no failure branch to map.
            let status = await backend.rootStatus(serial: request.serial)
            return (.ok, encoded(DaemonProtocol.RootStatusResponse(status)))

        // The filesystem half lives in `FileRoutes`, so this switch stays a
        // table of routes rather than a fifth of the protocol inline.
        case .filesList:
            return Self.answer(
                await FileRoutes.list(body: Data(body.readableBytesView), backend: backend))
        case .filesOp:
            return Self.answer(
                await FileRoutes.operation(body: Data(body.readableBytesView), backend: backend))
        case .filesInfo:
            return Self.answer(
                await FileRoutes.info(body: Data(body.readableBytesView), backend: backend))
        case .filesPull:
            return Self.answer(
                await FileRoutes.pull(body: Data(body.readableBytesView), backend: backend))

        case .crashesList:
            return Self.answer(
                await CrashRoutes.list(body: Data(body.readableBytesView), backend: backend))
        case .crashesClear:
            return Self.answer(
                await CrashRoutes.clear(body: Data(body.readableBytesView), backend: backend))

        case .devSettingsRead:
            return Self.answer(await DeviceSettingsRoutes.developerRead(
                body: Data(body.readableBytesView), backend: backend))
        case .devSettingsWrite:
            return Self.answer(await DeviceSettingsRoutes.developerWrite(
                body: Data(body.readableBytesView), backend: backend))
        case .restrictionsRead:
            return Self.answer(await DeviceSettingsRoutes.restrictionsRead(
                body: Data(body.readableBytesView), backend: backend))
        case .restrictionsWrite:
            return Self.answer(await DeviceSettingsRoutes.restrictionsWrite(
                body: Data(body.readableBytesView), backend: backend))

        case .wifiRead:
            return Self.answer(await NetworkRoutes.wifiRead(
                body: Data(body.readableBytesView), backend: backend))
        case .wifiWrite:
            return Self.answer(await NetworkRoutes.wifiWrite(
                body: Data(body.readableBytesView), backend: backend))
        case .dnsRead:
            return Self.answer(await NetworkRoutes.dnsRead(
                body: Data(body.readableBytesView), backend: backend))
        case .dnsWrite:
            return Self.answer(await NetworkRoutes.dnsWrite(
                body: Data(body.readableBytesView), backend: backend))

        case .appInfo:
            return Self.answer(await AppInspectionRoutes.info(
                body: Data(body.readableBytesView), backend: backend))
        case .appPermissions:
            return Self.answer(await AppInspectionRoutes.permissions(
                body: Data(body.readableBytesView), backend: backend))
        case .appSetPermission:
            return Self.answer(await AppInspectionRoutes.setPermission(
                body: Data(body.readableBytesView), backend: backend))
        case .appMeminfo:
            return Self.answer(await AppInspectionRoutes.meminfo(
                body: Data(body.readableBytesView), backend: backend))
        case .appSandboxList:
            return Self.answer(await AppInspectionRoutes.sandboxList(
                body: Data(body.readableBytesView), backend: backend))
        case .appSandboxPull:
            return Self.answer(await AppInspectionRoutes.sandboxPull(
                body: Data(body.readableBytesView), backend: backend))
        case .appPullApk:
            return Self.answer(await AppInspectionRoutes.pullApk(
                body: Data(body.readableBytesView), backend: backend))

        case .emulatorsList:
            return Self.answer(await EmulatorRoutes.list(backend: backend))
        case .emulatorsAction:
            return Self.answer(await EmulatorRoutes.action(
                body: Data(body.readableBytesView), backend: backend))

        case .installFormats:
            return Self.answer(InstallRoutes.formats())
        case .installRun:
            return Self.answer(await InstallRoutes.install(
                body: Data(body.readableBytesView), backend: backend))

        case .wirelessAction:
            return Self.answer(await ConnectionRoutes.action(
                body: Data(body.readableBytesView), backend: backend))

        case .deepLinksRead:
            return Self.answer(await DiagnosticsRoutes.linksRead(
                body: Data(body.readableBytesView), backend: backend))
        case .deepLinksWrite:
            return Self.answer(await DiagnosticsRoutes.linksWrite(
                body: Data(body.readableBytesView), backend: backend))
        case .deepLinksLaunch:
            return Self.answer(await DiagnosticsRoutes.linksLaunch(
                body: Data(body.readableBytesView), backend: backend))
        case .apkToolchain:
            return Self.answer(await ApkRoutes.toolchain(backend: backend))
        case .apkInspect:
            return Self.answer(await ApkRoutes.inspect(
                body: Data(body.readableBytesView), backend: backend))
        case .apkSign:
            return Self.answer(await ApkRoutes.sign(
                body: Data(body.readableBytesView), backend: backend))
        case .apkDecompile:
            return Self.answer(await DecompileRoutes.run(
                body: Data(body.readableBytesView), backend: backend))
        case .apkDecompileFile:
            return Self.answer(await DecompileRoutes.file(
                body: Data(body.readableBytesView), backend: backend))
        case .apkDecompileSearch:
            return Self.answer(await DecompileRoutes.search(
                body: Data(body.readableBytesView), backend: backend))
        case .apkRebuild:
            return Self.answer(await DecompileRoutes.rebuild(
                body: Data(body.readableBytesView), backend: backend))
        case .aabConvert:
            return Self.answer(await ApkRoutes.convert(
                body: Data(body.readableBytesView), backend: backend))
        case .customCommandsRead:
            return Self.answer(await CustomCommandRoutes.read(backend: backend))
        case .customCommandsWrite:
            return Self.answer(await CustomCommandRoutes.write(
                body: Data(body.readableBytesView), backend: backend))
        case .customCommandsRun:
            return Self.answer(await CustomCommandRoutes.run(
                body: Data(body.readableBytesView), backend: backend))
        case .bugReportCreate:
            return Self.answer(await DiagnosticsRoutes.bugReport(
                body: Data(body.readableBytesView), backend: backend))
        case .toolsDetect:
            return Self.answer(await DiagnosticsRoutes.tools(backend: backend))

        case .reactotronReverse:
            return Self.answer(await ReactotronRoutes.reverse(
                body: Data(body.readableBytesView), backend: backend))
        case .reactotronUnreverse:
            return Self.answer(await ReactotronRoutes.unreverse(
                body: Data(body.readableBytesView), backend: backend))

        case .actionsRun:
            let raw = Data(body.readableBytesView)
            guard let request = try? JSONDecoder().decode(
                ActionProtocol.RunRequest.self, from: raw)
            else { return (.badRequest, encoded(DaemonProtocol.badRequest)) }
            guard let platform = request.resolvedPlatform else {
                return (.badRequest, encoded(DaemonProtocol.unknownPlatform))
            }
            // Unknown ids are a 404 rather than a 500: asking for a feature
            // that does not exist is the client's mistake, not a daemon fault,
            // and `run` would otherwise answer with a generic failure that a
            // UI cannot distinguish from a device problem.
            guard FeatureEngine.implementedIDs.contains(request.featureId) else {
                return (.notFound, encoded(DaemonProtocol.unknownFeature))
            }
            let result = await backend.runAction(
                featureID: request.featureId, serial: request.serial,
                platform: platform, params: request.featureValues)
            // A failed action is a *successful* request: 200 with ok=false.
            // Mapping it to 5xx would conflate "the device said no" with "the
            // daemon broke", which is the distinction `AdbClient` exists to
            // preserve.
            return (.ok, encoded(ActionProtocol.RunResponse(result)))

        case .appsList:
            let raw = Data(body.readableBytesView)
            guard let request = try? JSONDecoder().decode(
                AppProtocol.ListRequest.self, from: raw)
            else { return (.badRequest, encoded(DaemonProtocol.badRequest)) }
            do {
                let apps = try await backend.listApps(serial: request.serial)
                return (.ok, encoded(AppProtocol.ListResponse(
                    apps: apps.map(AppProtocol.AppSummary.init))))
            } catch {
                // adb refused: the device went away, or is unauthorised. That
                // is the device's answer rather than a daemon fault, so it
                // goes out as a 502 carrying adb's own words.
                return (.badGateway, encoded(DaemonProtocol.ErrorBody(
                    code: "adb_failed", message: "Could not list apps.",
                    detail: "\(error)")))
            }

        case .appsForeground:
            let raw = Data(body.readableBytesView)
            guard let request = try? JSONDecoder().decode(
                AppProtocol.ListRequest.self, from: raw)
            else { return (.badRequest, encoded(DaemonProtocol.badRequest)) }
            do {
                let package = try await backend.foregroundPackage(serial: request.serial)
                return (.ok, encoded(AppProtocol.ForegroundResponse(packageId: package)))
            } catch {
                return (.badGateway, encoded(DaemonProtocol.ErrorBody(
                    code: "adb_failed", message: "Could not read the foreground app.",
                    detail: "\(error)")))
            }

        case .appsControl:
            let raw = Data(body.readableBytesView)
            guard let request = try? JSONDecoder().decode(
                AppProtocol.ControlRequest.self, from: raw)
            else { return (.badRequest, encoded(DaemonProtocol.badRequest)) }
            guard let action = request.resolvedAction else {
                return (.badRequest, encoded(AppProtocol.unknownAction))
            }
            do {
                let result = try await backend.controlApp(
                    serial: request.serial, packageId: request.packageId, action: action)
                return (.ok, encoded(ActionProtocol.RunResponse(result)))
            } catch {
                return (.badGateway, encoded(DaemonProtocol.ErrorBody(
                    code: "adb_failed", message: "The app action failed.",
                    detail: "\(error)")))
            }
        }
    }

    /// A `FileRoutes` answer as NIO wants it. Those handlers deal in a plain
    /// status code so they can be tested without a socket.
    private static func answer(_ answer: DaemonProtocol.Answer) -> (HTTPResponseStatus, Data) {
        (HTTPResponseStatus(statusCode: answer.status), answer.body)
    }

    private func write(context: ChannelHandlerContext, status: HTTPResponseStatus, body: Data) {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        headers.add(name: "Content-Length", value: String(body.count))
        // This handler closes the connection after every response, so say so.
        // Without it a client pools the socket, reuses one the server has
        // already dropped, and sees a lost connection instead of its answer —
        // intermittent by nature, which is the worst kind of bug to ship in a
        // tool people debug with.
        headers.add(name: "Connection", value: "close")
        // No CORS headers, deliberately: nothing browser-based should be
        // reaching this, and advertising otherwise would undo the Origin check.
        context.write(
            wrapOutboundOut(.head(HTTPResponseHead(version: .http1_1, status: status, headers: headers))),
            promise: nil)
        var buffer = context.channel.allocator.buffer(capacity: body.count)
        buffer.writeBytes(body)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        // Close through the channel, not the context: `Channel` is Sendable and
        // the completion closure is not on the event loop's isolation.
        let channel = context.channel
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            channel.close(promise: nil)
        }
    }
}
