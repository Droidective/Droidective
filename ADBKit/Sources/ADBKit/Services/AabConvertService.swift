import Foundation

/// Converts an Android App Bundle (`.aab`) into an installable universal APK
/// with the managed `bundletool`: `build-apks --mode=universal` produces a
/// `.apks` archive (a zip) whose single `universal.apk` entry is then extracted
/// and moved to the caller's output directory.
///
/// Everything runs as `java -jar …` against the toolchain-resolved runtime and
/// the downloaded bundletool. All paths are argument-vector elements — no shell.
/// With `credentials` bundletool signs the universal APK with that keystore;
/// without, it falls back to `~/.android/debug.keystore` when one exists, which
/// is what device installs need.
public struct AabConvertService: Sendable {
    public enum ConvertError: Error, LocalizedError, Equatable {
        case toolMissing(String)
        case buildFailed(String)
        case extractFailed(String)

        public var errorDescription: String? {
            switch self {
            case .toolMissing(let what): "\(what) isn't installed yet."
            case .buildFailed(let reason): reason.isEmpty ? "bundletool couldn't build APKs from this bundle." : reason
            case .extractFailed(let reason): reason.isEmpty ? "Couldn't extract universal.apk from the built archive." : reason
            }
        }
    }

    /// What the service is doing right now, for a live status line in the view.
    public enum Stage: Sendable, Equatable {
        case buildingApks
        case extracting
    }

    public struct ConvertedApk: Sendable, Equatable {
        public let url: URL
        public let sizeBytes: Int64

        public init(url: URL, sizeBytes: Int64) {
            self.url = url
            self.sizeBytes = sizeBytes
        }
    }

    let toolchain: ApkToolchain
    let runner: any ProcessRunning

    public init(toolchain: ApkToolchain, runner: any ProcessRunning = SystemProcessRunner()) {
        self.toolchain = toolchain
        self.runner = runner
    }

    /// Convert `aabPath` into `<bundle name>-universal.apk` inside
    /// `outputDirectory` (created if missing; an existing file gets a numbered
    /// sibling instead of being clobbered). Intermediate output lives in a
    /// throwaway temp dir that is removed on every exit path.
    ///
    /// With `credentials`, bundletool signs the universal APK with that
    /// keystore — passwords ride 0600 temp files (`--ks-pass=file:`), never
    /// argv. Without, bundletool falls back to `~/.android/debug.keystore`
    /// when one exists.
    public func convert(
        aabPath: String, outputDirectory: URL, credentials: KeystoreCredentials? = nil,
        onStage: (@Sendable (Stage) -> Void)? = nil
    ) async throws -> ConvertedApk {
        guard let java = await toolchain.java() else { throw ConvertError.toolMissing("Java") }
        guard let bundletool = await toolchain.bundletool() else { throw ConvertError.toolMissing("bundletool") }

        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("aab-convert-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        var storePassFile: String?
        var keyPassFile: String?
        // Registered before the writes: if the second secret's write throws,
        // the first is already on disk and must still be swept.
        defer {
            for file in [storePassFile, keyPassFile].compactMap(\.self) {
                try? fm.removeItem(atPath: file)
            }
        }
        if let credentials {
            storePassFile = try writeSecret(credentials.storePassword)
            if let keyPassword = credentials.keyPassword, !keyPassword.isEmpty {
                keyPassFile = try writeSecret(keyPassword)
            }
        }

        onStage?(.buildingApks)
        let apksPath = work.appendingPathComponent("bundle.apks").path
        let build = await runner.run(
            executable: java,
            arguments: Self.buildApksArguments(
                jar: bundletool, aab: aabPath, output: apksPath,
                keystore: credentials?.keystorePath, storePassFile: storePassFile,
                keyAlias: credentials?.keyAlias, keyPassFile: keyPassFile),
            timeout: .seconds(600), maxOutputBytes: 8 << 20)
        guard build.exitCode == 0, fm.fileExists(atPath: apksPath) else {
            if build.timedOut { throw ConvertError.buildFailed("bundletool timed out after 10 minutes.") }
            throw ConvertError.buildFailed(Self.failureSummary(stderr: build.stderrText, stdout: build.stdoutText))
        }

        onStage?(.extracting)
        let extract = await runner.run(
            executable: HostArchive.unzipExecutable,
            arguments: Self.extractArguments(apks: apksPath, destination: work.path),
            timeout: .seconds(120), maxOutputBytes: 1 << 20)
        let universal = work.appendingPathComponent("universal.apk")
        guard extract.exitCode == 0, fm.fileExists(atPath: universal.path) else {
            throw ConvertError.extractFailed(Self.failureSummary(stderr: extract.stderrText, stdout: extract.stdoutText))
        }

        let name = URL(fileURLWithPath: aabPath).deletingPathExtension().lastPathComponent
        try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let destination = Self.availableDestination(in: outputDirectory, baseName: "\(name)-universal")
        try fm.moveItem(at: universal, to: destination)
        let size = ((try? fm.attributesOfItem(atPath: destination.path))?[.size] as? NSNumber)?.int64Value ?? 0
        return ConvertedApk(url: destination, sizeBytes: size)
    }

    // MARK: - Pure argument builders

    /// Password arguments reference 0600 temp files (`file:`), never the
    /// secret itself — argv is visible in the process list.
    static func buildApksArguments(
        jar: String, aab: String, output: String,
        keystore: String? = nil, storePassFile: String? = nil,
        keyAlias: String? = nil, keyPassFile: String? = nil
    ) -> [String] {
        var arguments = ["-jar", jar, "build-apks", "--bundle=\(aab)", "--output=\(output)", "--mode=universal", "--overwrite"]
        if let keystore {
            arguments.append("--ks=\(keystore)")
            if let storePassFile { arguments.append("--ks-pass=file:\(storePassFile)") }
            if let keyAlias, !keyAlias.isEmpty { arguments.append("--ks-key-alias=\(keyAlias)") }
            if let keyPassFile { arguments.append("--key-pass=file:\(keyPassFile)") }
        }
        return arguments
    }

    /// Write a secret to a temp file created with 0600 permissions and return
    /// its path. The per-user temp dir (0700) covers any instant between
    /// creation and the attribute landing. Callers delete it.
    private func writeSecret(_ secret: String) throws -> String {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("aab-sign-\(UUID().uuidString)")
        guard FileManager.default.createFile(
            atPath: path.path, contents: Data(secret.utf8),
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw ConvertError.buildFailed("Couldn't write the keystore password file.")
        }
        return path.path
    }

    static func extractArguments(apks: String, destination: String) -> [String] {
        #if os(Windows)
        // The system bsdtar reads zips; universal.apk sits at the archive root.
        ["-xf", apks, "-C", destination, "universal.apk"]
        #else
        ["-q", "-o", "-j", apks, "universal.apk", "-d", destination]
        #endif
    }

    /// The most useful line out of a failed run: bundletool prefixes its real
    /// diagnosis with "Error:" (often after a long Java stack trace), so prefer
    /// that line; otherwise fall back to the last non-empty line of stderr, then
    /// stdout.
    static func failureSummary(stderr: String, stdout: String) -> String {
        for text in [stderr, stdout] {
            let lines = text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if let error = lines.first(where: { $0.contains("Error:") }) { return error }
            if let last = lines.last { return last }
        }
        return ""
    }

    /// `<dir>/<baseName>.apk`, or the first `<baseName>-N.apk` that doesn't
    /// exist yet — converting the same bundle twice must not overwrite a file
    /// the user may already be using.
    static func availableDestination(in directory: URL, baseName: String) -> URL {
        let first = directory.appendingPathComponent("\(baseName).apk")
        guard FileManager.default.fileExists(atPath: first.path) else { return first }
        for index in 2...999 {
            let candidate = directory.appendingPathComponent("\(baseName)-\(index).apk")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return directory.appendingPathComponent("\(baseName)-\(UUID().uuidString.prefix(8)).apk")
    }
}
