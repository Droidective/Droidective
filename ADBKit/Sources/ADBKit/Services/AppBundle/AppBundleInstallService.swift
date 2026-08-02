import Foundation

/// Installs the split-bundle formats — `.apks`, `.xapk`, `.apkm` — that
/// `adb install` can't take directly, and passes a plain `.apk` straight
/// through to `AppInstallService`.
///
/// `.apks` archives carry bundletool's own device-targeting table (`toc.pb`),
/// so they go back to bundletool (`install-apks`), which reads it. `.xapk` and
/// `.apkm` are plain zips of already-split APKs: they're unpacked to a temp
/// directory, narrowed to the splits this device needs (`SplitApkSelector`), and
/// installed in one `adb install-multiple` transaction — all splits must land
/// together or the package manager rejects the set. Any OBB expansion files a
/// `.xapk` carries are pushed afterwards.
public struct AppBundleInstallService: Sendable {
    /// What the install is doing right now, for a live status line.
    public enum Stage: Sendable, Equatable {
        case unpacking
        case readingDevice
        /// Installing `count` APKs (1 for a plain APK, more for a split set).
        case installing(count: Int)
        case pushingExpansion(name: String, index: Int, total: Int)
    }

    public enum BundleError: Error, LocalizedError, Equatable {
        case unsupportedFormat(String)
        case unpackFailed(String)
        case noPackagesFound(String)
        case abiUnmatched(deviceABIs: [String])
        case toolMissing(String)

        public var errorDescription: String? {
            switch self {
            case .unsupportedFormat(let ext):
                "Droidective can't install \(ext.isEmpty ? "this file" : ".\(ext) files") — pick an APK, APKS, XAPK, or APKM."
            case .unpackFailed(let reason):
                reason.isEmpty ? "The archive couldn't be unpacked — it may be corrupt." : reason
            case .noPackagesFound(let format):
                "This \(format) doesn't contain any APKs."
            case .abiUnmatched(let abis):
                "The bundle has no native code for this device's CPU (\(abis.isEmpty ? "unknown" : abis.joined(separator: ", ")))."
            case .toolMissing(let what):
                "\(what) isn't installed yet — download it in Settings ▸ Tools."
            }
        }
    }

    let client: AdbClient
    let toolchain: ApkToolchain
    let runner: any ProcessRunning

    public init(client: AdbClient, toolchain: ApkToolchain, runner: any ProcessRunning = SystemProcessRunner()) {
        self.client = client
        self.toolchain = toolchain
        self.runner = runner
    }

    /// Install any supported package format onto one device. Throws only when
    /// the file can't be processed at all (unknown format, unpack failure, no
    /// matching ABI, missing bundletool); an install adb *ran* and rejected
    /// comes back as a failed `FeatureResult` carrying adb's own reason.
    public func install(
        bundlePath: String, serial: String, onStage: (@Sendable (Stage) -> Void)? = nil
    ) async throws -> FeatureResult {
        guard let format = AppPackageFormat.detect(fileName: bundlePath) else {
            throw BundleError.unsupportedFormat(URL(fileURLWithPath: bundlePath).pathExtension.lowercased())
        }
        switch format {
        case .apk:
            onStage?(.installing(count: 1))
            return try await AppInstallService(client: client).install(apkPath: bundlePath, serial: serial)
        case .apks:
            return try await installApks(bundlePath: bundlePath, serial: serial, onStage: onStage)
        case .xapk, .apkm:
            return try await installZipBundle(
                bundlePath: bundlePath, format: format, serial: serial, onStage: onStage)
        }
    }

    // MARK: - .apks (bundletool)

    /// Hand the archive back to bundletool, which reads its `toc.pb` and picks
    /// the splits for the connected device itself — reimplementing that matching
    /// would only be a worse copy of it.
    private func installApks(
        bundlePath: String, serial: String, onStage: (@Sendable (Stage) -> Void)?
    ) async throws -> FeatureResult {
        guard let java = await toolchain.java() else { throw BundleError.toolMissing("Java") }
        guard let bundletool = await toolchain.bundletool() else { throw BundleError.toolMissing("bundletool") }
        let adb = try await client.locator.adbPath()

        onStage?(.installing(count: 1))
        let result = await runner.run(
            executable: java,
            arguments: Self.installApksArguments(jar: bundletool, apks: bundlePath, adb: adb, serial: serial),
            timeout: .seconds(900), maxOutputBytes: 8 << 20)
        guard result.exitCode == 0 else {
            let summary = AabConvertService.failureSummary(stderr: result.stderrText, stdout: result.stdoutText)
            return FeatureResult(
                ok: false,
                message: result.timedOut ? "The install timed out after 15 minutes." : Self.friendlyBundletoolReason(summary),
                copyText: [result.stdoutText, result.stderrText].filter { !$0.isEmpty }.joined(separator: "\n"))
        }
        return FeatureResult(ok: true, message: "Installed")
    }

    /// bundletool's `install-apks`. `--adb` pins the same adb the app uses (its
    /// own lookup would find a different one on PATH, or none in a GUI app's
    /// minimal environment) and `--device-id` scopes it to the target.
    static func installApksArguments(jar: String, apks: String, adb: String, serial: String) -> [String] {
        ["-jar", jar, "install-apks", "--apks=\(apks)", "--adb=\(adb)", "--device-id=\(serial)"]
    }

    /// bundletool wraps adb's own failure text, so surface the package manager's
    /// reason when there is one and fall back to bundletool's line otherwise.
    static func friendlyBundletoolReason(_ summary: String) -> String {
        if let range = summary.range(of: "INSTALL_FAILED_[A-Z0-9_]+", options: .regularExpression) {
            return AppInstallService.friendlyReason(String(summary[range]))
        }
        return summary.isEmpty ? "bundletool couldn't install this archive." : summary
    }

    // MARK: - .xapk / .apkm (unpack, select, install-multiple)

    private func installZipBundle(
        bundlePath: String, format: AppPackageFormat, serial: String, onStage: (@Sendable (Stage) -> Void)?
    ) async throws -> FeatureResult {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("bundle-install-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        onStage?(.unpacking)
        let unpack = await runner.run(
            executable: HostArchive.unzipExecutable,
            arguments: HostArchive.unzipArguments(archive: bundlePath, into: work.path),
            timeout: .seconds(600), maxOutputBytes: 1 << 20)
        // unzip exits 1 for recoverable warnings (skipped entries) having still
        // written the archive, so the extracted contents — not the code — decide.
        guard unpack.exitCode == 0 || unpack.exitCode == 1, !unpack.timedOut else {
            throw BundleError.unpackFailed(
                AabConvertService.failureSummary(stderr: unpack.stderrText, stdout: unpack.stdoutText))
        }

        let manifest = readManifest(in: work, format: format)
        let apks = try discoverAPKs(in: work, manifest: manifest, format: format)

        onStage?(.readingDevice)
        let spec = DeviceSpec.parse(props: try await DeviceProps.all(client: client, serial: serial))
        let selection = SplitApkSelector.select(files: apks.map(\.path), spec: spec)
        guard !selection.abiUnmatched else { throw BundleError.abiUnmatched(deviceABIs: spec.abis) }
        // Selection only ever narrows; an empty result means every APK was an
        // unmatched config split, so fall back to installing what we unpacked.
        let chosen = selection.files.isEmpty ? apks.map(\.path) : selection.files

        onStage?(.installing(count: chosen.count))
        let install = try await client.run(
            on: serial, Self.installArguments(apks: chosen), timeout: .seconds(900))
        let result = AppInstallService.parse(install)
        guard result.ok else { return result }

        return await pushExpansions(
            expansions(in: work, manifest: manifest), serial: serial, onStage: onStage)
    }

    /// `install-multiple` for a split set (all splits must arrive in one
    /// transaction), plain `install` for a single APK. `-r` reinstalls over an
    /// existing copy, keeping its data.
    static func installArguments(apks: [String]) -> [String] {
        apks.count == 1 ? ["install", "-r", apks[0]] : ["install-multiple", "-r"] + apks
    }

    private func readManifest(in root: URL, format: AppPackageFormat) -> AppBundleManifest? {
        guard let name = AppBundleManifest.manifestFileName(for: format),
              let data = try? Data(contentsOf: root.appendingPathComponent(name))
        else { return nil }
        return AppBundleManifest.parse(data, format: format)
    }

    /// The APKs to consider, preferring the manifest's list (authoritative, and
    /// it excludes anything the container ships that isn't part of the app) and
    /// falling back to every `.apk` in the unpacked tree.
    private func discoverAPKs(
        in root: URL, manifest: AppBundleManifest?, format: AppPackageFormat
    ) throws -> [URL] {
        let fm = FileManager.default
        let listed = (manifest?.splitFiles ?? [])
            .map { root.appendingPathComponent($0) }
            .filter { fm.fileExists(atPath: $0.path) }
        let apks = listed.isEmpty ? Self.scan(root, extension: "apk") : listed
        guard !apks.isEmpty else { throw BundleError.noPackagesFound(format.displayName) }
        return apks
    }

    /// Expansion files to push: the manifest's list, or — for a container
    /// without one — every `.obb` under the conventional `Android/obb` path.
    private func expansions(in root: URL, manifest: AppBundleManifest?) -> [(local: URL, remote: String)] {
        let listed = (manifest?.expansions ?? []).compactMap { expansion -> (local: URL, remote: String)? in
            let local = root.appendingPathComponent(expansion.file)
            guard FileManager.default.fileExists(atPath: local.path) else { return nil }
            return (local, Self.remoteExpansionPath(expansion.installPath))
        }
        guard listed.isEmpty else { return listed }
        return Self.scan(root, extension: "obb").compactMap { url in
            guard let relative = Self.relativePath(of: url, under: root),
                  let safe = AppBundleManifest.safeRelativePath(relative)
            else { return nil }
            return (url, Self.remoteExpansionPath(safe))
        }
    }

    /// `url`'s path relative to `root`, or nil when it isn't inside it. Compared
    /// by path *component* after resolving symlinks: the temp directory the
    /// unpack lands in is reached through one on macOS (`/var` → `/private/var`),
    /// so trimming a prefix by character count would leave a stray fragment in
    /// the middle of the device path.
    static func relativePath(of url: URL, under root: URL) -> String? {
        let rootParts = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let parts = url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        guard parts.count > rootParts.count, Array(parts.prefix(rootParts.count)) == rootParts else { return nil }
        return parts.dropFirst(rootParts.count).joined(separator: "/")
    }

    /// Push each expansion next to the installed app. `adb push` moves bytes
    /// over the sync protocol (no device shell, so no quoting), but the parent
    /// directory has to exist first and *that* goes through `sh` — hence the
    /// quoted `mkdir`.
    private func pushExpansions(
        _ expansions: [(local: URL, remote: String)], serial: String, onStage: (@Sendable (Stage) -> Void)?
    ) async -> FeatureResult {
        guard !expansions.isEmpty else { return FeatureResult(ok: true, message: "Installed") }
        for (index, expansion) in expansions.enumerated() {
            onStage?(.pushingExpansion(
                name: expansion.local.lastPathComponent, index: index + 1, total: expansions.count))
            let parent = (expansion.remote as NSString).deletingLastPathComponent
            _ = try? await client.run(on: serial, ["shell", "mkdir", "-p", shellQuote(parent)])
            let push = try? await client.run(
                on: serial, ["push", expansion.local.path, expansion.remote], timeout: .seconds(1800))
            guard let push, push.succeeded else {
                // The app is installed; only its data files are missing, and
                // saying so beats a bare "failed" the user can't act on.
                return FeatureResult(
                    ok: false,
                    message: "Installed, but couldn't copy \(expansion.local.lastPathComponent) to the device.",
                    copyText: push?.stderr)
            }
        }
        let count = expansions.count
        return FeatureResult(ok: true, message: "Installed with \(count) expansion file\(count == 1 ? "" : "s")")
    }

    /// Where an expansion lands on the device. Containers store the path
    /// relative to external storage (`Android/obb/<package>/…`).
    static func remoteExpansionPath(_ installPath: String) -> String {
        "/sdcard/" + installPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Every file with `extension` under `root`, sorted so a bundle always
    /// installs its splits in the same order.
    private static func scan(_ root: URL, extension pathExtension: String) -> [URL] {
        let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        let matches = (enumerator?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension.lowercased() == pathExtension }
        return matches.sorted { $0.path < $1.path }
    }
}
