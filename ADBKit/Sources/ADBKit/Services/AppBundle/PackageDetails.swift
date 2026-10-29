import Foundation

/// What the install screens say about an app package: which app it is, what it
/// needs, and what is inside it.
///
/// A plain APK is read directly. A split bundle is read through its base APK —
/// extracted on its own rather than unpacking the archive, because an `.xapk`
/// can carry a gigabyte of expansion files — plus the manifest the container
/// ships. Every field is best-effort: without the SDK build-tools an APK is
/// just its name and size, and a bundle falls back to its manifest.
public struct PackageDetails: Sendable, Equatable {
    public var format: AppPackageFormat
    public var fileName: String
    public var fileSizeBytes: Int
    /// The APK's report; for a bundle, its base APK's. Nil when a bundle's base
    /// couldn't be found or extracted.
    public var report: ApkReport?
    /// The `.xapk`/`.apkm` container's own metadata, when it carries any.
    public var manifest: AppBundleManifest?
    /// APKs inside a bundle; zero for a plain APK.
    public var apkCount = 0
    /// OBB expansion files inside a bundle.
    public var expansionCount = 0
    /// The ABIs the package has native code for, in the platform's spelling
    /// (`arm64-v8a`): badging's `native-code` plus a bundle's ABI splits.
    public var abis: [String] = []

    public init(format: AppPackageFormat, fileName: String, fileSizeBytes: Int) {
        self.format = format
        self.fileName = fileName
        self.fileSizeBytes = fileSizeBytes
    }

    /// Why an install asked to open the app couldn't: nothing could read the
    /// package's name, which only aapt2 can for a plain APK.
    public static let unreadableNameForOpening =
        "Couldn't open it — reading its package name needs the SDK build-tools."

    public var label: String? { report?.info.label ?? manifest?.appName }
    public var packageName: String? { report?.info.packageName ?? manifest?.packageName }
    public var versionName: String? { report?.info.versionName ?? manifest?.versionName }
    public var versionCode: String? { report?.info.versionCode ?? manifest?.versionCode }

    /// Whether aapt2 read the APK, which is what every SDK, permission,
    /// native-code and launcher fact depends on.
    public var hasBadging: Bool { report?.info.hasDetails ?? false }

    /// "2.1.0  (42)", or nil when neither half is known.
    public var versionSummary: String? {
        guard versionName != nil || versionCode != nil else { return nil }
        return InstallPlan.versionLabel(name: versionName, code: versionCode)
    }

    /// "Android 7.0 (API 24) or later".
    public var requiresSummary: String? {
        report?.info.minSdk.map { "\(AndroidRelease.describe(apiLevel: $0)) or later" }
    }

    /// "Android 15 (API 35)".
    public var targetsSummary: String? {
        report?.info.targetSdk.map { AndroidRelease.describe(apiLevel: $0) }
    }

    /// The activity "open" starts, by its class name — or that there is none,
    /// which is why opening the app after installing it would fail. Nil when
    /// aapt2 didn't read the package, since then nobody knows.
    public var launcherSummary: String? {
        guard hasBadging else { return nil }
        guard let activity = report?.launchableActivity else { return "No launcher activity — nothing to open" }
        return activity.split(separator: ".").last.map(String.init) ?? activity
    }

    /// Whether aapt2 read the package and found nothing to launch.
    public var hasNoLauncher: Bool { hasBadging && report?.launchableActivity == nil }

    /// "6 APKs, 1 expansion file" for a bundle; nil for a plain APK, which is
    /// the one thing it holds, or a bundle whose listing couldn't be read.
    public var contentsSummary: String? {
        guard format != .apk, apkCount > 0 else { return nil }
        var parts = [Self.count(apkCount, "APK")]
        if expansionCount > 0 { parts.append(Self.count(expansionCount, "expansion file")) }
        return parts.joined(separator: ", ")
    }

    /// The ABIs, or that there are none — said only when aapt2 read the APK,
    /// since an unread one has unknown native code rather than none.
    public var nativeCodeSummary: String? {
        if !abis.isEmpty { return abis.joined(separator: ", ") }
        return hasBadging ? "None — runs on any CPU" : nil
    }

    /// Why the SDK, permission and native-code facts are missing, or nil when
    /// they aren't. `hasAapt2` separates "install the build-tools" from a
    /// package aapt2 could not read.
    public func missingNote(hasAapt2: Bool) -> String? {
        guard !hasBadging else { return nil }
        if !hasAapt2 {
            return "The SDK levels, permissions and native code need the Android SDK build-tools (aapt2)."
        }
        if format != .apk, report == nil {
            return "Couldn't find the app's base APK inside this \(format.displayName)."
        }
        return "aapt2 couldn't read this package — it may be damaged."
    }

    /// "Android Debug · v1, v2, v3 schemes": the first signer's common name and
    /// the schemes it verified under. Nil when apksigner didn't run or found no
    /// signer.
    public var signerSummary: String? {
        guard let signer = report?.signers.first else { return nil }
        let name = signer.commonName ?? "Unknown signer"
        let schemes = report?.signatureSchemes ?? []
        guard !schemes.isEmpty else { return name }
        return "\(name) · \(schemes.joined(separator: ", ")) scheme\(schemes.count == 1 ? "" : "s")"
    }

    /// The permissions as a list shows them: the platform's own without their
    /// `android.permission.` prefix, anything else in full.
    public var permissionNames: [String] {
        let prefix = "android.permission."
        return (report?.permissions ?? []).map {
            $0.hasPrefix(prefix) ? String($0.dropFirst(prefix.count)) : $0
        }
    }

    private static func count(_ value: Int, _ noun: String) -> String {
        "\(value) \(noun)\(value == 1 ? "" : "s")"
    }

    /// The APK in a bundle that identifies the app. Every producer names it
    /// differently: APKMirror `base.apk`, bundletool `splits/base-master.apk`
    /// (or `universal.apk` in universal mode, `standalones/…` for pre-L
    /// devices), and APKPure after the package itself.
    static func baseEntry(in entries: [String], packageName: String?) -> String? {
        let apks = entries.filter {
            $0.lowercased().hasSuffix(".apk") && HostArchive.isPlainEntryName($0)
        }
        func named(_ name: String) -> String? {
            apks.first { ($0 as NSString).lastPathComponent.lowercased() == name.lowercased() }
        }
        if let hit = named("base.apk") ?? named("base-master.apk") ?? named("universal.apk") {
            return hit
        }
        if let packageName, let hit = named(packageName + ".apk") { return hit }
        if let hit = apks.first(where: { $0.hasPrefix("standalones/") }) { return hit }
        return apks.first { SplitApkSelector.qualifier(ofFile: $0) == .base }
    }

    /// The ABIs a bundle's split names carry, spelled the way Android and
    /// aapt2 spell them: a split says `arm64_v8a` where the platform says
    /// `arm64-v8a`, but `x86_64` is the platform's own name.
    static func splitABIs(in entries: [String]) -> [String] {
        var abis: [String] = []
        for entry in entries where entry.lowercased().hasSuffix(".apk") {
            guard case .abi(let token) = SplitApkSelector.qualifier(ofFile: entry) else { continue }
            let abi = platformABINames[token] ?? token
            if !abis.contains(abi) { abis.append(abi) }
        }
        return abis
    }

    private static let platformABINames = [
        "armeabi_v7a": "armeabi-v7a",
        "arm64_v8a": "arm64-v8a",
    ]
}

/// Reads `PackageDetails` for any installable format.
public struct PackageDetailsService: Sendable {
    let inspection: ApkInspectionService
    let runner: any ProcessRunning

    public init(inspection: ApkInspectionService, runner: any ProcessRunning = SystemProcessRunner()) {
        self.inspection = inspection
        self.runner = runner
    }

    /// The package's details, or nil for a file that isn't an installable
    /// format. `readsSigning: false` skips apksigner for a caller that only
    /// needs the app's identity.
    public func details(packagePath: String, readsSigning: Bool = true) async -> PackageDetails? {
        guard let format = AppPackageFormat.detect(fileName: packagePath) else { return nil }
        let attributes = try? FileManager.default.attributesOfItem(atPath: packagePath)
        var details = PackageDetails(
            format: format,
            fileName: URL(fileURLWithPath: packagePath).lastPathComponent,
            fileSizeBytes: (attributes?[.size] as? Int) ?? 0)
        switch format {
        case .apk:
            let report = await inspection.inspect(apkPath: packagePath, readsSigning: readsSigning)
            details.report = report
            details.abis = report.nativeCode
        case .apks, .xapk, .apkm:
            await readBundle(&details, path: packagePath, readsSigning: readsSigning)
        }
        return details
    }

    private func readBundle(_ details: inout PackageDetails, path: String, readsSigning: Bool) async {
        let listing = await runner.run(
            executable: HostArchive.unzipExecutable,
            arguments: HostArchive.listArguments(archive: path),
            timeout: .seconds(30), maxOutputBytes: 4 << 20)
        guard listing.exitCode == 0, !listing.timedOut else { return }
        let entries = HostArchive.parseListing(listing.stdoutText)
        details.apkCount = entries.filter { $0.lowercased().hasSuffix(".apk") }.count
        details.expansionCount = entries.filter { $0.lowercased().hasSuffix(".obb") }.count
        details.abis = PackageDetails.splitABIs(in: entries)

        let fm = FileManager.default
        let work = fm.temporaryDirectory
            .appendingPathComponent("package-details-\(UUID().uuidString)", isDirectory: true)
        guard (try? fm.createDirectory(at: work, withIntermediateDirectories: true)) != nil else { return }
        defer { try? fm.removeItem(at: work) }

        if let name = AppBundleManifest.manifestFileName(for: details.format), entries.contains(name),
           let file = await extract(name, from: path, into: work),
           let data = try? Data(contentsOf: file) {
            details.manifest = AppBundleManifest.parse(data, format: details.format)
        }
        guard let base = PackageDetails.baseEntry(in: entries, packageName: details.manifest?.packageName),
              let apk = await extract(base, from: path, into: work)
        else { return }
        let report = await inspection.inspect(apkPath: apk.path, readsSigning: readsSigning)
        details.report = report
        for abi in report.nativeCode where !details.abis.contains(abi) {
            details.abis.append(abi)
        }
    }

    /// Extract one entry; the file it landed at, or nil when it didn't.
    private func extract(_ entry: String, from archive: String, into dir: URL) async -> URL? {
        guard HostArchive.isPlainEntryName(entry) else { return nil }
        let result = await runner.run(
            executable: HostArchive.unzipExecutable,
            arguments: HostArchive.extractArguments(archive: archive, entry: entry, into: dir.path),
            timeout: .seconds(120), maxOutputBytes: 1 << 20)
        let file = dir.appendingPathComponent(entry)
        guard result.exitCode == 0, FileManager.default.fileExists(atPath: file.path) else { return nil }
        return file
    }
}
