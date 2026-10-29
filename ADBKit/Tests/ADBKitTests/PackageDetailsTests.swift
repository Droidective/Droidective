import Foundation
import Testing

@testable import ADBKit

@Suite struct PackageDetailsTests {
    // MARK: which APK in a bundle names the app

    @Test func eachProducersBaseApkIsFound() {
        // APKMirror
        #expect(PackageDetails.baseEntry(
            in: ["info.json", "split_config.arm64_v8a.apk", "base.apk"], packageName: nil) == "base.apk")
        // bundletool, split mode
        #expect(PackageDetails.baseEntry(
            in: ["toc.pb", "splits/base-arm64_v8a.apk", "splits/base-master.apk",
                 "standalones/standalone-x86.apk"],
            packageName: nil) == "splits/base-master.apk")
        // bundletool, universal mode
        #expect(PackageDetails.baseEntry(in: ["toc.pb", "universal.apk"], packageName: nil) == "universal.apk")
        // APKPure names the base after the package, which only the manifest says.
        #expect(PackageDetails.baseEntry(
            in: ["manifest.json", "config.arm64_v8a.apk", "com.example.apk"],
            packageName: "com.example") == "com.example.apk")
    }

    @Test func withoutANamedBaseTheFirstNonConfigApkStandsIn() {
        #expect(PackageDetails.baseEntry(
            in: ["toc.pb", "standalones/standalone-arm64_v8a_hdpi.apk"], packageName: nil)
            == "standalones/standalone-arm64_v8a_hdpi.apk")
        #expect(PackageDetails.baseEntry(
            in: ["config.xxhdpi.apk", "app.apk"], packageName: nil) == "app.apk")
        #expect(PackageDetails.baseEntry(in: ["manifest.json", "icon.png"], packageName: nil) == nil)
    }

    @Test func anEntryThatIsNotAPlainPathIsNeverChosen() {
        // A traversal would be read from outside the scratch directory, and a
        // wildcard would make the extractor match something else.
        #expect(PackageDetails.baseEntry(in: ["../base.apk"], packageName: nil) == nil)
        #expect(PackageDetails.baseEntry(in: ["/abs/base.apk"], packageName: nil) == nil)
        #expect(PackageDetails.baseEntry(in: ["b[a]se.apk", "*.apk"], packageName: nil) == nil)
    }

    @Test func splitABIsUseThePlatformsSpelling() {
        #expect(PackageDetails.splitABIs(in: [
            "base.apk", "split_config.arm64_v8a.apk", "split_config.armeabi_v7a.apk",
            "config.x86_64.apk", "splits/base-x86_64.apk", "config.xxhdpi.apk", "config.en.apk",
        ]) == ["arm64-v8a", "armeabi-v7a", "x86_64"])
        #expect(PackageDetails.splitABIs(in: ["base.apk", "config.arm64_v8a.obb"]).isEmpty)
    }

    @Test func identityFallsBackToTheContainersManifest() {
        var details = PackageDetails(format: .xapk, fileName: "x.xapk", fileSizeBytes: 1)
        details.manifest = AppBundleManifest(
            packageName: "com.m", appName: "From Manifest", versionName: "2.0", versionCode: "20")
        #expect(details.packageName == "com.m")
        #expect(details.label == "From Manifest")
        #expect(!details.hasBadging)

        details.report = ApkReport(info: ApkInfo(
            fileName: "base.apk", fileSizeBytes: 1, label: "From APK", packageName: "com.a",
            versionName: "2.1", versionCode: "21"))
        #expect(details.packageName == "com.a")
        #expect(details.label == "From APK")
        #expect(details.versionName == "2.1")
        #expect(details.versionCode == "21")
        #expect(details.hasBadging)
    }

    // MARK: what the card says

    @Test func versionAndSdkLinesReadAsTheCardShowsThem() {
        var details = PackageDetails(format: .apk, fileName: "a.apk", fileSizeBytes: 1)
        #expect(details.versionSummary == nil)
        #expect(details.requiresSummary == nil)
        details.report = ApkReport(info: ApkInfo(
            fileName: "a.apk", fileSizeBytes: 1, packageName: "com.a",
            versionName: "3.1.0", versionCode: "18", minSdk: "17", targetSdk: "35"))
        #expect(details.versionSummary == "3.1.0  (18)")
        #expect(details.requiresSummary == "Android 4.2 (API 17) or later")
        #expect(details.targetsSummary == "Android 15 (API 35)")
    }

    @Test func theLauncherLineNamesTheActivityOrItsAbsence() {
        var details = PackageDetails(format: .apk, fileName: "a.apk", fileSizeBytes: 1)
        // Unread: unknown, not absent.
        #expect(details.launcherSummary == nil)
        #expect(!details.hasNoLauncher)
        details.report = ApkReport(
            info: ApkInfo(fileName: "a.apk", fileSizeBytes: 1, packageName: "com.a"),
            launchableActivity: "io.appium.android.apis.ApiDemos")
        #expect(details.launcherSummary == "ApiDemos")
        #expect(!details.hasNoLauncher)
        details.report?.launchableActivity = nil
        #expect(details.launcherSummary == "No launcher activity — nothing to open")
        #expect(details.hasNoLauncher)
    }

    @Test func contentsCountsABundlesApksAndExpansions() {
        var bundle = PackageDetails(format: .xapk, fileName: "a.xapk", fileSizeBytes: 1)
        #expect(bundle.contentsSummary == nil)  // a listing that couldn't be read
        bundle.apkCount = 1
        #expect(bundle.contentsSummary == "1 APK")
        bundle.apkCount = 6
        bundle.expansionCount = 1
        #expect(bundle.contentsSummary == "6 APKs, 1 expansion file")
        bundle.expansionCount = 2
        #expect(bundle.contentsSummary == "6 APKs, 2 expansion files")

        var apk = PackageDetails(format: .apk, fileName: "a.apk", fileSizeBytes: 1)
        apk.apkCount = 3
        #expect(apk.contentsSummary == nil)
    }

    @Test func noNativeCodeIsSaidOnlyWhenAapt2ReadThePackage() {
        var details = PackageDetails(format: .apk, fileName: "a.apk", fileSizeBytes: 1)
        #expect(details.nativeCodeSummary == nil)
        details.report = ApkReport(info: ApkInfo(fileName: "a.apk", fileSizeBytes: 1, packageName: "com.a"))
        #expect(details.nativeCodeSummary == "None — runs on any CPU")
        details.abis = ["arm64-v8a", "x86_64"]
        #expect(details.nativeCodeSummary == "arm64-v8a, x86_64")
    }

    @Test func theMissingNoteSaysWhichThingIsMissing() {
        var apk = PackageDetails(format: .apk, fileName: "a.apk", fileSizeBytes: 1)
        apk.report = ApkReport(info: ApkInfo(fileName: "a.apk", fileSizeBytes: 1))
        #expect(apk.missingNote(hasAapt2: false)?.contains("build-tools (aapt2)") == true)
        #expect(apk.missingNote(hasAapt2: true) == "aapt2 couldn't read this package — it may be damaged.")

        let bundle = PackageDetails(format: .apkm, fileName: "a.apkm", fileSizeBytes: 1)
        #expect(bundle.missingNote(hasAapt2: true) == "Couldn't find the app's base APK inside this APKM.")

        apk.report?.info.packageName = "com.a"
        #expect(apk.missingNote(hasAapt2: false) == nil)
    }

    @Test func theSignerLineNamesTheKeyAndItsSchemes() {
        var details = PackageDetails(format: .apk, fileName: "a.apk", fileSizeBytes: 1)
        #expect(details.signerSummary == nil)
        details.report = ApkReport(
            info: ApkInfo(fileName: "a.apk", fileSizeBytes: 1),
            signatureSchemes: ["v2"],
            signers: [ApkSigner(subjectDN: "C=US, O=Android, CN=Android Debug")])
        #expect(details.signerSummary == "Android Debug · v2 scheme")
        details.report?.signatureSchemes = ["v1", "v2", "v3"]
        #expect(details.signerSummary == "Android Debug · v1, v2, v3 schemes")
        details.report?.signatureSchemes = []
        #expect(details.signerSummary == "Android Debug")
    }

    @Test func platformPermissionsLoseTheirPrefixAndOthersKeepTheirs() {
        var details = PackageDetails(format: .apk, fileName: "a.apk", fileSizeBytes: 1)
        details.report = ApkReport(
            info: ApkInfo(fileName: "a.apk", fileSizeBytes: 1),
            permissions: ["android.permission.CAMERA", "com.google.android.c2dm.permission.RECEIVE"])
        #expect(details.permissionNames == ["CAMERA", "com.google.android.c2dm.permission.RECEIVE"])
    }

    // MARK: archive commands

    @Test func listingDropsDirectoriesAndCarriageReturns() {
        #expect(HostArchive.parseListing("base.apk\r\nsplits/\r\nsplits/base-master.apk\r\n\r\n")
            == ["base.apk", "splits/base-master.apk"])
        #expect(HostArchive.parseListing("").isEmpty)
    }

    @Test func archiveArgumentsNameTheArchiveAndTheOneEntry() {
        #if os(Windows)
        #expect(HostArchive.listArguments(archive: #"C:\in\a.xapk"#) == ["-tf", #"C:\in\a.xapk"#])
        #expect(HostArchive.extractArguments(archive: "a.xapk", entry: "base.apk", into: "D")
            == ["-xf", "a.xapk", "-C", "D", "base.apk"])
        #else
        #expect(HostArchive.listArguments(archive: "/in/My App.xapk") == ["-Z1", "/in/My App.xapk"])
        #expect(HostArchive.extractArguments(archive: "/in/a.xapk", entry: "splits/base-master.apk", into: "/w")
            == ["-qq", "-o", "/in/a.xapk", "splits/base-master.apk", "-d", "/w"])
        #endif
    }

    // MARK: API levels

    @Test func apiLevelsReadAsReleases() {
        #expect(AndroidRelease.describe(apiLevel: "24") == "Android 7.0 (API 24)")
        #expect(AndroidRelease.describe(apiLevel: "35") == "Android 15 (API 35)")
        #expect(AndroidRelease.describe(apiLevel: "32") == "Android 12L (API 32)")
        #expect(AndroidRelease.describe(apiLevel: "37") == "Android 17 (API 37)")
        #expect(AndroidRelease.describe(apiLevel: "36.1") == "Android 16 (API 36.1)")
        // Past the table: the level, not a guess at a name.
        #expect(AndroidRelease.describe(apiLevel: "99") == "API 99")
        // A preview SDK reports its codename.
        #expect(AndroidRelease.describe(apiLevel: "Baklava") == "Baklava")
    }

    // MARK: reading a package

    @Test func aPlainApkIsReadDirectly() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.cleanup() }
        fixture.runner.badging["app.apk"] = """
        package: name='com.x' versionCode='3' versionName='1.3'
        native-code: 'arm64-v8a'
        """
        let apk = try fixture.file("app.apk", bytes: 4096)

        let details = try #require(await fixture.service.details(packagePath: apk, readsSigning: false))

        #expect(details.format == .apk)
        #expect(details.fileSizeBytes == 4096)
        #expect(details.packageName == "com.x")
        #expect(details.abis == ["arm64-v8a"])
        #expect(details.apkCount == 0)
        // An APK is never listed or unpacked.
        #expect(!fixture.runner.invocations.contains { $0.executable == HostArchive.unzipExecutable })
    }

    @Test func anXapkIsReadThroughItsManifestAndBaseApkAlone() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.cleanup() }
        fixture.runner.listing = """
        manifest.json
        com.example.apk
        config.arm64_v8a.apk
        config.xxhdpi.apk
        Android/obb/com.example/main.7.com.example.obb
        """
        fixture.runner.entries = [
            "manifest.json": #"{"package_name":"com.example","name":"Example","version_code":"7"}"#,
            "com.example.apk": "apk",
        ]
        fixture.runner.badging["com.example.apk"] = """
        package: name='com.example' versionCode='7' versionName='7.0'
        application-label:'Example App'
        """
        let xapk = try fixture.file("Example.xapk", bytes: 10)

        let details = try #require(await fixture.service.details(packagePath: xapk, readsSigning: false))

        #expect(details.manifest?.packageName == "com.example")
        #expect(details.label == "Example App")
        #expect(details.versionName == "7.0")
        #expect(details.apkCount == 3)
        #expect(details.expansionCount == 1)
        #expect(details.abis == ["arm64-v8a"])
        // Two entries extracted, never the whole archive (and so never the OBB).
        let extracted = fixture.runner.invocations
            .filter { $0.executable == HostArchive.unzipExecutable }
            .compactMap(\.extractedEntry)
        #expect(extracted == ["manifest.json", "com.example.apk"])
        // The scratch directory is gone afterwards.
        #expect(fixture.runner.extractionDirectories.allSatisfy {
            !FileManager.default.fileExists(atPath: $0)
        })
    }

    @Test func anApksIsReadThroughBundletoolsBaseSplit() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.cleanup() }
        fixture.runner.listing = "toc.pb\nsplits/\nsplits/base-master.apk\nsplits/base-x86_64.apk\n"
        fixture.runner.entries = ["splits/base-master.apk": "apk"]
        fixture.runner.badging["base-master.apk"] = """
        package: name='com.b' versionCode='1' versionName='1.0'
        """
        let apks = try fixture.file("b.apks", bytes: 10)

        let details = try #require(await fixture.service.details(packagePath: apks, readsSigning: false))

        #expect(details.packageName == "com.b")
        #expect(details.manifest == nil)
        #expect(details.apkCount == 2)
        #expect(details.abis == ["x86_64"])
    }

    @Test func anUnreadableArchiveIsStillItsNameAndSize() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.cleanup() }
        fixture.runner.listingExitCode = 9
        let apkm = try fixture.file("broken.apkm", bytes: 77)

        let details = try #require(await fixture.service.details(packagePath: apkm))

        #expect(details.fileName == "broken.apkm")
        #expect(details.fileSizeBytes == 77)
        #expect(details.report == nil)
        #expect(details.packageName == nil)
        #expect(fixture.runner.invocations.compactMap(\.extractedEntry).isEmpty)
    }

    @Test func aBundleWhoseBaseFailsToExtractKeepsWhatTheListingSaid() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.cleanup() }
        fixture.runner.listing = "base.apk\nsplit_config.arm64_v8a.apk\n"
        let apkm = try fixture.file("a.apkm", bytes: 1)

        let details = try #require(await fixture.service.details(packagePath: apkm))

        #expect(details.report == nil)
        #expect(details.apkCount == 2)
        #expect(details.abis == ["arm64-v8a"])
    }

    @Test func aFileThatIsNotAPackageHasNoDetails() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.cleanup() }
        #expect(await fixture.service.details(packagePath: "/in/app.aab") == nil)
    }
}

/// A service over a fake archive tool and aapt2, with a scratch directory for
/// the package files themselves.
private struct Fixture {
    let service: PackageDetailsService
    let runner: ArchiveRunner
    let directory: URL

    static func make() async throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("package-details-test-\(UUID().uuidString)", isDirectory: true)
        let buildTools = directory.appendingPathComponent("build-tools/36.0.0")
        try FileManager.default.createDirectory(at: buildTools, withIntermediateDirectories: true)
        let aapt2 = buildTools.appendingPathComponent(ToolLocator.executableName("aapt2"))
        try createExecutableStub(at: aapt2)

        let runner = ArchiveRunner(aapt2: aapt2.path)
        let locator = ToolLocator(runner: runner, environment: [:])
        await locator.seed(.adb, path: "/fake/adb")
        await locator.seedBuildToolsDir(buildTools.path)
        await locator.seedJava(nil)
        let client = AdbClient(locator: locator, runner: runner, log: CommandLog())
        let toolchain = ApkToolchain(locator: locator, store: ManagedToolStore(
            rootDirectory: directory.appendingPathComponent("store")))
        let inspection = ApkInspectionService(client: client, toolchain: toolchain, runner: runner)
        return Fixture(
            service: PackageDetailsService(inspection: inspection, runner: runner),
            runner: runner, directory: directory)
    }

    func file(_ name: String, bytes: Int) throws -> String {
        let url = directory.appendingPathComponent(name)
        try Data(count: bytes).write(to: url)
        return url.path
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Answers the archive tool's list and single-entry extract the way the real
/// one would, and aapt2's badging per APK file name.
private final class ArchiveRunner: ProcessRunning, @unchecked Sendable {
    struct Invocation {
        let executable: String
        let arguments: [String]

        /// The entry a single-entry extract named, or nil for any other call.
        var extractedEntry: String? {
            #if os(Windows)
            guard arguments.first == "-xf", arguments.count == 5 else { return nil }
            return arguments[4]
            #else
            guard arguments.first == "-qq", let flag = arguments.firstIndex(of: "-d") else { return nil }
            return arguments[flag - 1]
            #endif
        }

        var destination: String? {
            guard let flag = arguments.firstIndex(where: { $0 == "-d" || $0 == "-C" }),
                  arguments.count > flag + 1 else { return nil }
            return arguments[flag + 1]
        }
    }

    let aapt2: String
    var listing = ""
    var listingExitCode: Int32 = 0
    /// Entry → contents, written when that entry is extracted.
    var entries: [String: String] = [:]
    /// APK file name → badging output.
    var badging: [String: String] = [:]

    private let lock = NSLock()
    private var recorded: [Invocation] = []

    init(aapt2: String) {
        self.aapt2 = aapt2
    }

    var invocations: [Invocation] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    var extractionDirectories: [String] {
        invocations.filter { $0.extractedEntry != nil }.compactMap(\.destination)
    }

    func run(executable: String, arguments: [String], timeout: Duration, maxOutputBytes: Int) async -> ProcessOutput {
        let invocation = Invocation(executable: executable, arguments: arguments)
        record(invocation)

        if executable == aapt2, let path = arguments.last {
            let name = URL(fileURLWithPath: path).lastPathComponent
            return badging[name].map { output(stdout: $0) } ?? output(exitCode: 1)
        }
        guard executable == HostArchive.unzipExecutable else { return output(exitCode: 1) }
        if let entry = invocation.extractedEntry, let destination = invocation.destination {
            guard let contents = entries[entry] else { return output(exitCode: 11) }
            let file = URL(fileURLWithPath: destination).appendingPathComponent(entry)
            try? FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(contents.utf8).write(to: file)
            return output()
        }
        return output(stdout: listing, exitCode: listingExitCode)
    }

    private func record(_ invocation: Invocation) {
        lock.lock()
        recorded.append(invocation)
        lock.unlock()
    }

    private func output(stdout: String = "", exitCode: Int32 = 0) -> ProcessOutput {
        ProcessOutput(stdout: Data(stdout.utf8), stderr: Data(), exitCode: exitCode, timedOut: false)
    }
}
