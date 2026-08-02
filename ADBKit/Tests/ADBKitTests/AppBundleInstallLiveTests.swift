import Foundation
import Testing

@testable import ADBKit

/// Tier 3: the split-bundle installer against a real device.
///
/// The mock suite proves the argument vectors; this proves a container built
/// the way APKPure builds one actually unpacks, selects, installs, and lands
/// its expansion file on a device. The fixture is assembled at run time from an
/// app already on the device — an unsplit third-party package, reinstalled with
/// `-r` so the device is left exactly as it was found (only the planted OBB is
/// swept).
///
/// Disabled by default. Run with
/// `DEVICE_LIVE_TEST=1 MIRROR_SERIAL=emulator-5554 swift test --filter AppBundleInstallLiveTests`.
@Suite struct AppBundleInstallLiveTests {
    private static var liveEnabled: Bool {
        ProcessInfo.processInfo.environment["DEVICE_LIVE_TEST"] == "1"
    }

    private static var serial: String {
        ProcessInfo.processInfo.environment["MIRROR_SERIAL"] ?? "emulator-5554"
    }

    private static var adb: AdbClient { AdbClient(locator: ToolLocator()) }

    @Test(.enabled(if: liveEnabled))
    func theDeviceSpecReadsRealProperties() async throws {
        let spec = DeviceSpec.parse(props: try await DeviceProps.all(client: Self.adb, serial: Self.serial))
        // Every Android build defines an ABI list and a density; a rename
        // upstream would silently degrade selection to "install everything".
        #expect(!spec.abis.isEmpty, "no ABIs parsed — ro.product.cpu.abilist may have moved")
        #expect(spec.densityDpi > 0, "no density parsed — ro.sf.lcd_density may have moved")
        #expect(!spec.languages.isEmpty, "no locale parsed — persist.sys.locale may have moved")
        // The device's ABIs must be spellings the selector recognises, or every
        // real ABI split would look unmatched.
        let normalized = spec.abis.map { $0.replacingOccurrences(of: "-", with: "_") }
        #expect(normalized.contains { SplitApkSelector.knownABIs.contains($0) },
                "none of \(spec.abis) is a known ABI qualifier")
    }

    @Test(.enabled(if: liveEnabled))
    func aXapkContainerInstallsAndItsExpansionFileLands() async throws {
        let fixture = try await Self.makeXapkFromAnInstalledApp()
        defer { try? FileManager.default.removeItem(at: fixture.workDir) }

        let service = AppBundleInstallService(
            client: Self.adb, toolchain: ApkToolchain(locator: ToolLocator(), store: Self.toolStore))
        let result = try await service.install(bundlePath: fixture.xapk.path, serial: Self.serial)

        #expect(result.ok, "install failed: \(result.message)")
        // The planted expansion file is on the device at the manifest's path.
        let remote = "/sdcard/Android/obb/\(fixture.packageName)/main.1.\(fixture.packageName).obb"
        let listed = try await Self.adb.run(on: Self.serial, ["shell", "ls", shellQuote(remote)])
        #expect(listed.stdout.contains(remote), "expansion not on device: \(listed.stdout)\(listed.stderr)")
        // Sweep only what this test planted — the app itself was already there.
        _ = try? await Self.adb.run(on: Self.serial, ["shell", "rm", "-f", shellQuote(remote)])

        // And the app is still installed and runnable after the reinstall.
        let path = try await Self.adb.run(on: Self.serial, ["shell", "pm", "path", fixture.packageName])
        #expect(path.stdout.contains("package:"))
    }

    // MARK: helpers

    private static var toolStore: ManagedToolStore {
        ManagedToolStore(rootDirectory: AppPathsForTests.toolsDirectory)
    }

    private struct Fixture {
        let workDir: URL
        let xapk: URL
        let packageName: String
    }

    /// Build an APKPure-shaped `.xapk` around an unsplit third-party app that's
    /// already on the device: pull its APK, add a `manifest.json` and a small
    /// OBB, and zip the three together.
    private static func makeXapkFromAnInstalledApp() async throws -> Fixture {
        let packageName = try await unsplitThirdPartyPackage()
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("xapk-live-\(UUID().uuidString)", isDirectory: true)
        let staging = work.appendingPathComponent("staging/Android/obb/\(packageName)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let stagingRoot = work.appendingPathComponent("staging", isDirectory: true)

        let remoteAPK = try await apkPath(of: packageName)
        let localAPK = stagingRoot.appendingPathComponent("\(packageName).apk")
        let pull = try await adb.run(
            on: serial, ["pull", remoteAPK, localAPK.path], timeout: .seconds(180))
        try #require(FileManager.default.fileExists(atPath: localAPK.path), "pull failed: \(pull.stderr)")

        let obbName = "main.1.\(packageName).obb"
        try Data("live-test expansion payload".utf8).write(to: staging.appendingPathComponent(obbName))
        let obbRelative = "Android/obb/\(packageName)/\(obbName)"
        let manifest = """
        {"xapk_version": 2, "package_name": "\(packageName)", "name": "Live Fixture",
         "version_code": 1, "version_name": "1.0",
         "split_apks": [{"file": "\(packageName).apk", "id": "base"}],
         "expansions": [{"file": "\(obbRelative)", "install_location": "EXTERNAL_STORAGE",
                         "install_path": "\(obbRelative)"}]}
        """
        try Data(manifest.utf8).write(to: stagingRoot.appendingPathComponent("manifest.json"))

        // ditto without --keepParent puts the staging directory's *contents* at
        // the archive root, which is the layout an XAPK has.
        let xapk = work.appendingPathComponent("fixture.xapk")
        let zip = await SystemProcessRunner().run(
            executable: "/usr/bin/ditto",
            arguments: ["-c", "-k", "--sequesterRsrc", stagingRoot.path, xapk.path],
            timeout: .seconds(300), maxOutputBytes: 1 << 20)
        try #require(zip.exitCode == 0, "ditto failed: \(zip.stderrText)")
        return Fixture(workDir: work, xapk: xapk, packageName: packageName)
    }

    /// A third-party package installed as a single APK. Split-installed apps are
    /// skipped: reinstalling only their base would fail with MISSING_SPLIT and
    /// prove nothing about this code.
    private static func unsplitThirdPartyPackage() async throws -> String {
        let listed = try await adb.run(on: serial, ["shell", "pm", "list", "packages", "-3"])
        let packages = listed.stdout
            .components(separatedBy: .newlines)
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("package:") else { return nil }
                return String(trimmed.dropFirst("package:".count))
            }
        for package in packages where try await apkCount(of: package) == 1 {
            return package
        }
        throw LiveFixtureError.noUnsplitThirdPartyApp(candidates: packages.count)
    }

    private static func apkCount(of package: String) async throws -> Int {
        let paths = try await adb.run(on: serial, ["shell", "pm", "path", package])
        return paths.stdout
            .components(separatedBy: .newlines)
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("package:") }
            .count
    }

    private static func apkPath(of package: String) async throws -> String {
        let paths = try await adb.run(on: serial, ["shell", "pm", "path", package])
        let first = paths.stdout
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("package:") }
        guard let first else { throw LiveFixtureError.noApkPath(package) }
        return String(first.dropFirst("package:".count))
    }

    enum LiveFixtureError: Error, CustomStringConvertible {
        case noUnsplitThirdPartyApp(candidates: Int)
        case noApkPath(String)

        var description: String {
            switch self {
            case .noUnsplitThirdPartyApp(let candidates):
                "No unsplit third-party app on the device to build a fixture from (\(candidates) checked). "
                    + "Install any single-APK app and rerun."
            case .noApkPath(let package): "pm path returned nothing for \(package)."
            }
        }
    }
}

/// The managed-tool store the live suite reads bundletool from — the same
/// Application Support location the app uses.
private enum AppPathsForTests {
    static var toolsDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Droidective/tools", isDirectory: true)
    }
}
