import Foundation

public enum Tool: String, Sendable, CaseIterable {
    case adb
    case scrcpy
    case brew
    case ffmpeg
    case emulator
}

public enum AdbError: Error, LocalizedError, Sendable {
    case adbNotFound

    public var errorDescription: String? {
        switch self {
        case .adbNotFound:
            return "adb not found. Install Android platform-tools to continue."
        }
    }
}

/// Resolves absolute paths to external CLI tools (adb, scrcpy, brew, ffmpeg).
///
/// A GUI app launched from Finder inherits a minimal PATH that usually
/// excludes Homebrew and the Android SDK, so we never call a bare `adb`. We
/// probe well-known install locations and, as a fallback, ask the user's
/// login shell (which loads their full PATH) to resolve it. Results are
/// cached until `clearCache()` (e.g. after a tool install).
public actor ToolLocator {
    private var cache: [Tool: String?] = [:]
    /// Caches for tools resolved outside the `Tool` enum — the SDK build-tools
    /// directory (aapt2/apksigner/zipalign live there) and the JDK's `java`
    /// (needed to run the Java-based APK tools). Kept out of the Doctor's tool
    /// report; they're implementation detail. Outer optional = resolved-yet,
    /// inner = found-or-not.
    private var buildToolsDirCache: String??
    private var javaCache: String??
    private let runner: any ProcessRunning
    private let environment: [String: String]
    private let fileManager = FileManager.default

    public init(
        runner: any ProcessRunning = SystemProcessRunner(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.runner = runner
        self.environment = environment
    }

    public func resolve(_ tool: Tool) async -> String? {
        if let cached = cache[tool] { return cached }

        var resolved: String? = nil
        for candidate in candidatePaths(for: tool) where fileManager.isExecutableFile(atPath: candidate) {
            resolved = candidate
            break
        }
        if resolved == nil {
            resolved = await resolveViaLoginShell(tool)
        }
        // Negative results are cached too — Settings → Tools → "Re-detect"
        // and the brew-install flow call clearCache() to heal.
        cache[tool] = resolved
        return resolved
    }

    public func clearCache() {
        cache.removeAll()
        buildToolsDirCache = nil
        javaCache = nil
    }

    /// Newest SDK build-tools directory (e.g. …/build-tools/34.0.0), or nil when
    /// none are installed. aapt2 / apksigner / zipalign all ship here (not via
    /// Homebrew). Cached; cleared by `clearCache`.
    public func buildToolsDir() async -> String? {
        if let cached = buildToolsDirCache { return cached }
        var resolved: String?
        for root in sdkRoots {
            let buildTools = "\(root)/build-tools"
            guard let versions = try? fileManager.contentsOfDirectory(atPath: buildTools) else { continue }
            let newest = versions
                .sorted { $0.localizedStandardCompare($1) == .orderedDescending }
                .first { fileManager.fileExists(atPath: "\(buildTools)/\($0)") }
            if let newest {
                resolved = "\(buildTools)/\(newest)"
                break
            }
        }
        buildToolsDirCache = .some(resolved)
        return resolved
    }

    /// Resolve `aapt2` from the newest build-tools. Used to read a local APK's
    /// badging (package, version, SDK, permissions) without installing it.
    public func aapt2Path() async -> String? {
        await buildToolBinary("aapt2")
    }

    /// Resolve `zipalign` from the newest build-tools — page-aligns an APK
    /// before signing.
    public func zipalignPath() async -> String? {
        await buildToolBinary("zipalign")
    }

    /// Path to `apksigner.jar` in the newest build-tools' `lib/`. apksigner ships
    /// as a thin wrapper over this jar; we invoke `java -jar …` directly so we
    /// don't depend on the wrapper finding a JDK on the app's minimal PATH.
    public func apksignerJarPath() async -> String? {
        guard let dir = await buildToolsDir() else { return nil }
        let jar = "\(dir)/lib/apksigner.jar"
        return fileManager.fileExists(atPath: jar) ? jar : nil
    }

    private func buildToolBinary(_ name: String) async -> String? {
        guard let dir = await buildToolsDir() else { return nil }
        let path = "\(dir)/\(name)"
        return fileManager.isExecutableFile(atPath: path) ? path : nil
    }

    /// Resolve a `java` launcher for the Java-based APK tools (apksigner, jadx,
    /// apktool). Probes JAVA_HOME and Android Studio's bundled JBR, then macOS's
    /// `java_home` helper, then the login shell. Cached; cleared by `clearCache`.
    public func javaPath() async -> String? {
        if let cached = javaCache { return cached }
        let candidates = [
            environment["JAVA_HOME"].map { "\($0)/bin/java" },
            "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/java",
        ].compactMap(\.self)
        var resolved = candidates.first { fileManager.isExecutableFile(atPath: $0) }
        if resolved == nil { resolved = await resolveJavaHome() }
        if resolved == nil { resolved = await resolveViaLoginShellCommand("java") }
        javaCache = .some(resolved)
        return resolved
    }

    /// Ask macOS's `/usr/libexec/java_home` for the default JDK, then point at
    /// its `bin/java`. Exits non-zero when no JDK is installed.
    private func resolveJavaHome() async -> String? {
        let output = await runner.run(
            executable: "/usr/libexec/java_home", arguments: [],
            timeout: .seconds(8), maxOutputBytes: 64 * 1024)
        guard output.exitCode == 0 else { return nil }
        let home = output.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !home.isEmpty else { return nil }
        let java = "\(home)/bin/java"
        return fileManager.isExecutableFile(atPath: java) ? java : nil
    }

    /// Pre-populate the cache with a known path (tests, or a user-pinned
    /// tool location).
    public func seed(_ tool: Tool, path: String?) {
        cache[tool] = path
    }

    /// Pre-populate the build-tools directory and `java` launcher (tests).
    public func seedBuildToolsDir(_ path: String?) {
        buildToolsDirCache = .some(path)
    }

    public func seedJava(_ path: String?) {
        javaCache = .some(path)
    }

    /// Resolve adb or throw a typed error the UI maps to an install prompt.
    public func adbPath() async throws(AdbError) -> String {
        guard let path = await resolve(.adb) else { throw .adbNotFound }
        return path
    }

    /// SDK roots to probe, from the environment then the default install path.
    private var sdkRoots: [String] {
        let home = fileManager.homeDirectoryForCurrentUser.path
        return [
            environment["ANDROID_HOME"],
            environment["ANDROID_SDK_ROOT"],
            "\(home)/Library/Android/sdk",
        ].compactMap(\.self)
    }

    private func candidatePaths(for tool: Tool) -> [String] {
        let brewPrefixes = ["/opt/homebrew/bin", "/usr/local/bin"]

        switch tool {
        case .adb:
            return sdkRoots.map { "\($0)/platform-tools/adb" }
                + brewPrefixes.map { "\($0)/adb" }
        case .emulator:
            // The emulator launcher only ships with the SDK, not Homebrew.
            return sdkRoots.map { "\($0)/emulator/emulator" }
        case .scrcpy, .brew, .ffmpeg:
            return brewPrefixes.map { "\($0)/\(tool.rawValue)" }
        }
    }

    private func resolveViaLoginShell(_ tool: Tool) async -> String? {
        await resolveViaLoginShellCommand(tool.rawValue)
    }

    /// Ask the user's login shell (which loads their full PATH) to resolve a
    /// command by name — the fallback for Homebrew/SDK tools off the app's PATH.
    private func resolveViaLoginShellCommand(_ name: String) async -> String? {
        let output = await runner.run(
            executable: "/bin/zsh",
            arguments: ["-lc", "command -v \(name)"],
            timeout: .seconds(8),
            maxOutputBytes: 1024 * 1024
        )
        guard output.exitCode == 0 else { return nil }
        let resolved = output.stdoutText
            .split(whereSeparator: \.isNewline)
            .last
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let resolved, fileManager.isExecutableFile(atPath: resolved) else { return nil }
        return resolved
    }
}
