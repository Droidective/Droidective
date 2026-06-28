import Foundation

/// Deep-inspects an APK for the inspector view: identity, permissions, features
/// and the debuggable flag via `aapt2 dump badging`, and signing certificates
/// via `apksigner`. Every enrichment is best-effort — missing build-tools or a
/// missing JDK just leaves those fields empty, so the report always carries at
/// least the file name and size.
///
/// The host tools (aapt2, java) take the APK path as a single argument vector
/// element — no shell, so the path needs no quoting. Reading an installed app's
/// APK goes through `pm path` (device shell, so the package is `shellQuote`d)
/// then `adb pull` (sync protocol, no shell).
public struct ApkInspectionService: Sendable {
    let client: AdbClient
    let toolchain: ApkToolchain
    let runner: any ProcessRunning

    public init(client: AdbClient, toolchain: ApkToolchain, runner: any ProcessRunning = SystemProcessRunner()) {
        self.client = client
        self.toolchain = toolchain
        self.runner = runner
    }

    /// Inspect a local APK file.
    public func inspect(apkPath: String) async -> ApkReport {
        let attrs = try? FileManager.default.attributesOfItem(atPath: apkPath)
        let size = (attrs?[.size] as? Int) ?? 0
        var info = ApkInfo(fileName: URL(fileURLWithPath: apkPath).lastPathComponent, fileSizeBytes: size)
        var permissions: [String] = []
        var features: [String] = []
        var isDebuggable = false
        var schemes: [String] = []
        var signers: [ApkSigner] = []

        if let aapt2 = await toolchain.aapt2() {
            let output = await runner.run(
                executable: aapt2, arguments: ["dump", "badging", apkPath],
                timeout: .seconds(20), maxOutputBytes: 4 * 1024 * 1024)
            if output.exitCode == 0 {
                let fields = ApkBadging.parse(output.stdoutText)
                info.label = fields.label
                info.packageName = fields.packageName
                info.versionName = fields.versionName
                info.versionCode = fields.versionCode
                info.minSdk = fields.minSdk
                info.targetSdk = fields.targetSdk
                permissions = fields.permissions
                features = fields.features
                isDebuggable = fields.isDebuggable
            }
        }

        if let java = await toolchain.java(), let jar = await toolchain.apksignerJar() {
            // apksigner exits non-zero when verification fails but still prints
            // the certificate details, so parse stdout regardless of exit code.
            let output = await runner.run(
                executable: java, arguments: ["-jar", jar, "verify", "-v", "--print-certs", apkPath],
                timeout: .seconds(30), maxOutputBytes: 4 * 1024 * 1024)
            let signature = ApkSignature.parse(output.stdoutText)
            schemes = signature.schemes
            signers = signature.signers
        }

        return ApkReport(
            info: info, permissions: permissions, features: features,
            isDebuggable: isDebuggable, signatureSchemes: schemes, signers: signers)
    }

    /// On-device APK paths for an installed package (`base.apk` plus any split
    /// APKs), via `pm path`.
    public func apkPaths(package: String, serial: String) async throws(AdbError) -> [String] {
        let result = try await client.run(on: serial, ["shell", "pm", "path", shellQuote(package)])
        return Self.parsePmPath(result.stdout)
    }

    /// Pull an on-device APK to a local file (sync protocol — no shell).
    public func pullApk(remotePath: String, to localPath: String, serial: String) async throws(AdbError) -> Bool {
        let result = try await client.run(on: serial, ["pull", remotePath, localPath], timeout: .seconds(120))
        return result.succeeded
    }

    /// `pm path com.x` prints one `package:/path/to.apk` line per APK (split
    /// builds list several). Pull every path to reconstruct the full app.
    static func parsePmPath(_ output: String) -> [String] {
        output.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("package:") else { return nil }
            let path = String(trimmed.dropFirst("package:".count))
            return path.isEmpty ? nil : path
        }
    }
}
