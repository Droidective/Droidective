import Foundation
import Testing
@testable import ADBKit

@Suite struct ApkInspectionServiceTests {
    /// A toolchain wrapping the (seeded) test locator; its managed store points
    /// at an empty temp dir, so only the locator's seeded tools resolve.
    private func toolchain(_ client: AdbClient) -> ApkToolchain {
        ApkToolchain(locator: client.locator, store: ManagedToolStore(
            rootDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("tc-\(UUID().uuidString)")))
    }

    // MARK: pm path parsing

    @Test func parsePmPathExtractsEveryApk() {
        let output = """
        package:/data/app/~~ab==/com.x-1/base.apk
        package:/data/app/~~ab==/com.x-1/split_config.arm64_v8a.apk
        """
        #expect(ApkInspectionService.parsePmPath(output) == [
            "/data/app/~~ab==/com.x-1/base.apk",
            "/data/app/~~ab==/com.x-1/split_config.arm64_v8a.apk",
        ])
    }

    @Test func parsePmPathIgnoresNoiseEmptyAndCrlf() {
        #expect(ApkInspectionService.parsePmPath("").isEmpty)
        #expect(ApkInspectionService.parsePmPath("error: no such package\n").isEmpty)
        // CRLF from some shells must not leave a trailing '\r' on the path.
        #expect(ApkInspectionService.parsePmPath("package:/a/base.apk\r\n") == ["/a/base.apk"])
    }

    // MARK: installed-app pull (device shell quoting is the security boundary)

    @Test func apkPathsQuotesPackageForDeviceShell() async throws {
        let runner = MockProcessRunner()
        let client = await makeTestClient(runner: runner)
        runner.script(
            argsPrefix: ["-s", "S1", "shell", "pm", "path"],
            stdout: "package:/data/app/com.x-1/base.apk\n")
        let paths = try await ApkInspectionService(client: client, toolchain: toolchain(client))
            .apkPaths(package: "com.x", serial: "S1")
        #expect(paths == ["/data/app/com.x-1/base.apk"])
        // The package reaches `adb shell` so it must be single-quoted.
        #expect(runner.invocations.last?.arguments == ["-s", "S1", "shell", "pm", "path", "'com.x'"])
    }

    // MARK: deep inspection (host tools — argv, no shell)

    @Test func inspectRunsAapt2AndApksignerWithExactArgs() async throws {
        let runner = MockProcessRunner()
        let client = await makeTestClient(runner: runner)
        let tools = try Self.makeBuildTools()
        await client.locator.seedBuildToolsDir(tools.buildToolsDir)
        await client.locator.seedJava(tools.java)
        runner.script(
            argsPrefix: ["dump", "badging"],
            stdout: """
            package: name='com.x' versionCode='7' versionName='1.2'
            sdkVersion:'24'
            targetSdkVersion:'34'
            application-debuggable
            uses-permission: name='android.permission.INTERNET'
            """)
        runner.script(
            argsPrefix: ["-jar"],
            stdout: """
            Verified using v2 scheme (APK Signature Scheme v2): true
            Signer #1 certificate DN: CN=Test
            Signer #1 certificate SHA-256 digest: deadbeef
            """)

        let report = await ApkInspectionService(client: client, toolchain: toolchain(client), runner: runner)
            .inspect(apkPath: "/tmp/app.apk")

        #expect(report.info.packageName == "com.x")
        #expect(report.info.versionName == "1.2")
        #expect(report.permissions == ["android.permission.INTERNET"])
        #expect(report.isDebuggable)
        #expect(report.signatureSchemes == ["v2"])
        #expect(report.signers.first?.subjectDN == "CN=Test")
        #expect(report.signers.first?.sha256 == "deadbeef")

        #expect(runner.invocations.contains {
            $0.executable == tools.aapt2 && $0.arguments == ["dump", "badging", "/tmp/app.apk"]
        })
        #expect(runner.invocations.contains {
            $0.executable == tools.java
                && $0.arguments == ["-jar", tools.apksignerJar, "verify", "-v", "--print-certs", "/tmp/app.apk"]
        })
    }

    @Test func inspectDegradesToFileNameAndSizeWithoutBuildToolsOrJdk() async {
        let runner = MockProcessRunner()
        let client = await makeTestClient(runner: runner)
        await client.locator.seedBuildToolsDir(nil)
        await client.locator.seedJava(nil)

        let report = await ApkInspectionService(client: client, toolchain: toolchain(client), runner: runner)
            .inspect(apkPath: "/tmp/missing.apk")

        #expect(report.info.fileName == "missing.apk")
        #expect(report.info.packageName == nil)
        #expect(report.permissions.isEmpty)
        #expect(report.signers.isEmpty)
        // No build-tools / JDK resolved → no host tools were spawned.
        #expect(!runner.invocations.contains { $0.arguments.contains("badging") })
    }

    /// A temp build-tools directory with executable stubs for aapt2 / java and an
    /// apksigner.jar — enough for ToolLocator to resolve them (MockProcessRunner
    /// intercepts the actual execution, so the stubs' contents don't matter).
    private static func makeBuildTools() throws -> (buildToolsDir: String, aapt2: String, apksignerJar: String, java: String) {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("apk-inspect-\(UUID().uuidString)")
        let buildTools = base.appendingPathComponent("build-tools/34.0.0")
        try fm.createDirectory(at: buildTools.appendingPathComponent("lib"), withIntermediateDirectories: true)
        let exec: [FileAttributeKey: Any] = [.posixPermissions: 0o755]
        let aapt2 = buildTools.appendingPathComponent("aapt2")
        fm.createFile(atPath: aapt2.path, contents: Data("#!/bin/sh\n".utf8), attributes: exec)
        let jar = buildTools.appendingPathComponent("lib/apksigner.jar")
        fm.createFile(atPath: jar.path, contents: Data())
        let java = base.appendingPathComponent("java")
        fm.createFile(atPath: java.path, contents: Data("#!/bin/sh\n".utf8), attributes: exec)
        return (buildTools.path, aapt2.path, jar.path, java.path)
    }
}
