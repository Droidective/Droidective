import Foundation
import Testing
@testable import ADBKit

@Suite struct AabConvertServiceTests {
    // MARK: argument builders

    @Test func buildApksTargetsUniversalModeAndOverwrites() {
        #expect(AabConvertService.buildApksArguments(jar: "/t/bundletool.jar", aab: "/in/My App.aab", output: "/w/bundle.apks")
            == ["-jar", "/t/bundletool.jar", "build-apks", "--bundle=/in/My App.aab",
                "--output=/w/bundle.apks", "--mode=universal", "--overwrite"])
    }

    @Test func buildApksAppendsKeystoreArgumentsWithFilePasswords() {
        let args = AabConvertService.buildApksArguments(
            jar: "/t/bt.jar", aab: "/in/a.aab", output: "/w/b.apks",
            keystore: "/keys/release.jks", storePassFile: "/tmp/sp",
            keyAlias: "release", keyPassFile: "/tmp/kp")
        #expect(args.suffix(4) == [
            "--ks=/keys/release.jks", "--ks-pass=file:/tmp/sp",
            "--ks-key-alias=release", "--key-pass=file:/tmp/kp",
        ])
        // No keystore → no signing flags at all (bundletool's debug default).
        let plain = AabConvertService.buildApksArguments(jar: "j", aab: "a", output: "o")
        #expect(!plain.contains { $0.hasPrefix("--ks") })
        // A blank alias is omitted, not passed as an empty value.
        let noAlias = AabConvertService.buildApksArguments(
            jar: "j", aab: "a", output: "o", keystore: "k", storePassFile: "sp", keyAlias: "")
        #expect(!noAlias.contains { $0.hasPrefix("--ks-key-alias") })
    }

    @Test func convertWithKeystoreNeverPutsThePasswordOnTheCommandLine() async throws {
        let runner = FileProducingRunner()
        let (service, cleanup) = try await Self.makeService(runner: runner, bundletoolInstalled: true, javaSeeded: true)
        defer { cleanup() }
        let outDir = FileManager.default.temporaryDirectory.appendingPathComponent("aab-sign-out-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outDir) }

        let secret = "sup3r-s3cret"
        let keySecret = "k3y-s3cret"
        _ = try await service.convert(
            aabPath: "/in/a.aab", outputDirectory: outDir,
            credentials: KeystoreCredentials(
                keystorePath: "/keys/r.jks", storePassword: secret, keyAlias: "r",
                keyPassword: keySecret))

        let build = try #require(runner.invocations.first)
        #expect(!build.arguments.contains { $0.contains(secret) || $0.contains(keySecret) })
        #expect(build.arguments.contains("--ks=/keys/r.jks"))
        // Both referenced temp files held their secret 0600 during the run
        // and are deleted afterwards.
        for prefix in ["--ks-pass=file:", "--key-pass=file:"] {
            let passArg = try #require(build.arguments.first { $0.hasPrefix(prefix) })
            #expect(!FileManager.default.fileExists(atPath: String(passArg.dropFirst(prefix.count))))
        }
    }

    @Test func extractPullsOnlyUniversalApkFlattened() {
        // Windows extracts with the system bsdtar (which reads zips) rather
        // than unzip, so the vector differs by host — see `HostArchive`.
        #if os(Windows)
        let expected = ["-xf", "/w/bundle.apks", "-C", "/w", "universal.apk"]
        #else
        let expected = ["-q", "-o", "-j", "/w/bundle.apks", "universal.apk", "-d", "/w"]
        #endif
        #expect(
            AabConvertService.extractArguments(apks: "/w/bundle.apks", destination: "/w")
                == expected)
    }

    // MARK: failure summary

    @Test func failureSummaryPrefersBundletoolErrorLineOverStackTrace() {
        let stderr = """
        Exception in thread "main" com.android.tools.build.bundletool.model.exceptions.InvalidBundleException
            at com.android.tools.build.bundletool.BundleToolMain.main(BundleToolMain.java:80)
        [BT:1.18.3] Error: The App Bundle is invalid: missing BundleConfig.pb.
        """
        #expect(AabConvertService.failureSummary(stderr: stderr, stdout: "noise")
            == "[BT:1.18.3] Error: The App Bundle is invalid: missing BundleConfig.pb.")
    }

    @Test func failureSummaryFallsBackToLastLineThenStdout() {
        #expect(AabConvertService.failureSummary(stderr: "warning\nsomething broke\n\n", stdout: "")
            == "something broke")
        #expect(AabConvertService.failureSummary(stderr: "  \n", stdout: "cannot find zip entry") == "cannot find zip entry")
        #expect(AabConvertService.failureSummary(stderr: "", stdout: "") == "")
    }

    // MARK: destination naming

    @Test func availableDestinationNeverClobbersAnExistingConvert() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("aab-dest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let first = AabConvertService.availableDestination(in: dir, baseName: "app-universal")
        #expect(first.lastPathComponent == "app-universal.apk")
        _ = FileManager.default.createFile(atPath: first.path, contents: Data())
        let second = AabConvertService.availableDestination(in: dir, baseName: "app-universal")
        #expect(second.lastPathComponent == "app-universal-2.apk")
    }

    // MARK: behaviour

    @Test func convertRunsBundletoolThenExtractsUniversalApk() async throws {
        let runner = FileProducingRunner()
        let (service, cleanup) = try await Self.makeService(runner: runner, bundletoolInstalled: true, javaSeeded: true)
        defer { cleanup() }
        let outDir = FileManager.default.temporaryDirectory.appendingPathComponent("aab-out-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outDir) }

        let converted = try await service.convert(aabPath: "/in/My App.aab", outputDirectory: outDir)

        #expect(converted.url.lastPathComponent == "My App-universal.apk")
        #expect(FileManager.default.fileExists(atPath: converted.url.path))
        #expect(converted.sizeBytes > 0)
        // First invocation: java -jar <store's bundletool> build-apks.
        let build = runner.invocations.first
        #expect(build?.executable == "/fake/java")
        #expect(build?.arguments.first == "-jar")
        #expect(build?.arguments[1].hasSuffix("bundletool-all-1.18.3.jar") == true)
        #expect(build?.arguments[2] == "build-apks")
        #expect(build?.arguments.contains("--bundle=/in/My App.aab") == true)
        #expect(build?.arguments.contains("--mode=universal") == true)
        // Second: the host unzip pulling exactly universal.apk.
        let extract = runner.invocations.last
        #expect(extract?.executable == HostArchive.unzipExecutable)
        #expect(extract?.arguments.contains("universal.apk") == true)
    }

    @Test func convertSurfacesBundletoolsErrorLineOnFailure() async throws {
        let runner = MockProcessRunner()
        runner.script(
            argsPrefix: ["-jar"], stderr: "stack frame one\n[BT:1.18.3] Error: bad bundle.", exitCode: 1)
        let (service, cleanup) = try await Self.makeService(runner: runner, bundletoolInstalled: true, javaSeeded: true)
        defer { cleanup() }

        await #expect(throws: AabConvertService.ConvertError.buildFailed("[BT:1.18.3] Error: bad bundle.")) {
            _ = try await service.convert(
                aabPath: "/in/a.aab",
                outputDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("never-\(UUID().uuidString)"))
        }
    }

    @Test func convertSurfacesExtractFailureWhenUniversalApkIsMissing() async throws {
        // unzip exiting 0 without producing universal.apk (a split-only or
        // unexpected archive) must throw, not report a bogus success.
        let runner = FileProducingRunner()
        runner.producesUniversalApk = false
        let (service, cleanup) = try await Self.makeService(runner: runner, bundletoolInstalled: true, javaSeeded: true)
        defer { cleanup() }

        await #expect(throws: AabConvertService.ConvertError.extractFailed("")) {
            _ = try await service.convert(
                aabPath: "/in/a.aab",
                outputDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("never-\(UUID().uuidString)"))
        }
    }

    @Test func convertReportsATimedOutBundletoolAsSuch() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-jar"], exitCode: nil, timedOut: true)
        let (service, cleanup) = try await Self.makeService(runner: runner, bundletoolInstalled: true, javaSeeded: true)
        defer { cleanup() }

        await #expect(throws: AabConvertService.ConvertError.buildFailed("bundletool timed out after 10 minutes.")) {
            _ = try await service.convert(
                aabPath: "/in/a.aab",
                outputDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("never-\(UUID().uuidString)"))
        }
    }

    @Test func convertThrowsToolMissingBeforeRunningAnything() async throws {
        let runner = MockProcessRunner()
        let (noJava, cleanup1) = try await Self.makeService(runner: runner, bundletoolInstalled: true, javaSeeded: false)
        defer { cleanup1() }
        await #expect(throws: AabConvertService.ConvertError.toolMissing("Java")) {
            _ = try await noJava.convert(aabPath: "/a.aab", outputDirectory: FileManager.default.temporaryDirectory)
        }

        let (noBundletool, cleanup2) = try await Self.makeService(runner: runner, bundletoolInstalled: false, javaSeeded: true)
        defer { cleanup2() }
        await #expect(throws: AabConvertService.ConvertError.toolMissing("bundletool")) {
            _ = try await noBundletool.convert(aabPath: "/a.aab", outputDirectory: FileManager.default.temporaryDirectory)
        }
        #expect(runner.invocations.isEmpty)
    }

    // MARK: helpers

    /// A service over a store whose bundletool is (optionally) pre-installed on
    /// disk in the store's real layout, plus a seeded java. Returns a cleanup
    /// closure removing the store root.
    private static func makeService(
        runner: any ProcessRunning, bundletoolInstalled: Bool, javaSeeded: Bool
    ) async throws -> (AabConvertService, () -> Void) {
        let locator = ToolLocator(runner: runner, environment: [:])
        await locator.seedJava(javaSeeded ? "/fake/java" : nil)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("aab-store-\(UUID().uuidString)")
        if bundletoolInstalled {
            let versionDir = root.appendingPathComponent("bundletool/1.18.3")
            try FileManager.default.createDirectory(at: versionDir, withIntermediateDirectories: true)
            try Data("fake jar".utf8).write(to: versionDir.appendingPathComponent("bundletool-all-1.18.3.jar"))
            try Data("1.18.3".utf8).write(to: root.appendingPathComponent("bundletool/current.txt"))
        }
        let store = ManagedToolStore(rootDirectory: root)
        let service = AabConvertService(toolchain: ApkToolchain(locator: locator, store: store), runner: runner)
        return (service, { try? FileManager.default.removeItem(at: root) })
    }
}

/// A runner that behaves like bundletool + unzip on the filesystem: writes the
/// `--output=` archive for `build-apks` and drops `universal.apk` into the
/// `-d` destination for unzip — so `convert`'s file-existence checks pass.
private final class FileProducingRunner: ProcessRunning, @unchecked Sendable {
    struct Invocation { let executable: String; let arguments: [String] }

    /// Off: unzip "succeeds" without writing universal.apk (a split-only or
    /// unexpected archive), for the extract-failure branch.
    var producesUniversalApk = true

    private let lock = NSLock()
    private var recorded: [Invocation] = []

    var invocations: [Invocation] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func run(executable: String, arguments: [String], timeout: Duration, maxOutputBytes: Int) async -> ProcessOutput {
        recordAndProduce(executable: executable, arguments: arguments)
        return ProcessOutput(stdout: Data(), stderr: Data(), exitCode: 0, timedOut: false)
    }

    private func recordAndProduce(executable: String, arguments: [String]) {
        lock.lock()
        recorded.append(Invocation(executable: executable, arguments: arguments))
        lock.unlock()
        if let output = arguments.first(where: { $0.hasPrefix("--output=") }) {
            write(Data("apks".utf8), to: String(output.dropFirst("--output=".count)))
        }
        if producesUniversalApk, executable == HostArchive.unzipExecutable,
           let flag = arguments.firstIndex(where: { $0 == "-d" || $0 == "-C" }),
           arguments.count > flag + 1 {
            let dest = URL(fileURLWithPath: arguments[flag + 1]).appendingPathComponent("universal.apk")
            write(Data("universal".utf8), to: dest.path)
        }
    }

    /// Write one of the files a real tool would have produced, and **say so if
    /// that fails**.
    ///
    /// It failed once on Windows CI, and because the result was discarded the
    /// only symptom was `extractFailed("")` from the service two lines later —
    /// an empty message about the wrong step, which says nothing about a
    /// fixture that could not write its own file. `createFile` also returns a
    /// must-use `Bool` off Darwin, so discarding it is the trap `SecretFile`
    /// and the mirror log both had to be fixed for.
    ///
    /// Retried because the failure is transient: Windows CI briefly refuses a
    /// just-created path, which is the same behaviour `FileRetry` exists for.
    private func write(_ contents: Data, to path: String) {
        for attempt in 1...5 {
            if FileManager.default.createFile(atPath: path, contents: contents) { return }
            Thread.sleep(forTimeInterval: 0.05 * Double(attempt))
        }
        Issue.record("the fixture could not write \(path)")
    }
}
