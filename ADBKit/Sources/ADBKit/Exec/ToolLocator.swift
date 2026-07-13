import Foundation

public enum Tool: String, Sendable, CaseIterable {
    case adb
    case scrcpy
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

/// Resolves absolute paths to external CLI tools (adb, scrcpy, ffmpeg).
///
/// A GUI app launched from Finder inherits a minimal PATH that usually
/// excludes package-manager prefixes and the Android SDK, so we never call a
/// bare `adb`. We probe well-known install locations and, as a fallback, ask
/// the user's login shell (which loads their full PATH) to resolve it. Found
/// paths are cached until `clearCache()` (e.g. after a tool install); "not
/// found" expires after `notFoundTTL` so installing a tool mid-session is
/// noticed.
public actor ToolLocator {
    /// One finished lookup. `expiresAt` is set only on negative results;
    /// found and seeded paths never expire on their own.
    private struct CachedLookup {
        let path: String?
        let expiresAt: Date?
    }

    /// How long "not found" is trusted before re-probing. Long enough that the
    /// 2 s device poll doesn't spawn a login shell on every tick, short enough
    /// that a tool installed mid-session shows up without a manual Re-detect.
    static let notFoundTTL: TimeInterval = 30

    private var cache: [Tool: CachedLookup] = [:]
    /// Caches for tools resolved outside the `Tool` enum — the SDK build-tools
    /// directory (aapt2/apksigner/zipalign live there) and the JDK's `java`
    /// (needed to run the Java-based APK tools). Kept out of the Doctor's tool
    /// report; they're implementation detail. Outer optional = resolved-yet,
    /// inner = found-or-not.
    private var buildToolsDirCache: String??
    private var javaCache: String??
    private let runner: any ProcessRunning
    private let environment: [String: String]
    private let now: @Sendable () -> Date
    private let isExecutableFile: @Sendable (String) -> Bool
    private let fileManager = FileManager.default

    public init(
        runner: any ProcessRunning = SystemProcessRunner(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        now: @escaping @Sendable () -> Date = { Date() },
        isExecutableFile: @escaping @Sendable (String) -> Bool = {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    ) {
        self.runner = runner
        self.environment = environment
        self.now = now
        self.isExecutableFile = isExecutableFile
    }

    public func resolve(_ tool: Tool) async -> String? {
        if let cached = cache[tool] {
            if let expiresAt = cached.expiresAt, now() >= expiresAt {
                cache[tool] = nil
            } else {
                return cached.path
            }
        }

        var resolved: String? = nil
        for candidate in candidatePaths(for: tool) where isExecutableFile(candidate) {
            resolved = candidate
            break
        }
        if resolved == nil {
            resolved = await resolveViaLoginShell(tool)
        }
        // "Not found" is cached with a TTL; Settings → Tools → "Re-detect"
        // still calls clearCache() to heal at once.
        cache[tool] = CachedLookup(
            path: resolved,
            expiresAt: resolved == nil ? now().addingTimeInterval(Self.notFoundTTL) : nil
        )
        return resolved
    }

    public func clearCache() {
        cache.removeAll()
        buildToolsDirCache = nil
        javaCache = nil
    }

    /// Newest SDK build-tools directory (e.g. …/build-tools/34.0.0), or nil when
    /// none are installed. aapt2 / apksigner / zipalign all ship here (SDK
    /// only). Cached; cleared by `clearCache`.
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
        return isExecutableFile(path) ? path : nil
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
        var resolved = candidates.first { isExecutableFile($0) }
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
        return isExecutableFile(java) ? java : nil
    }

    /// Pre-populate the cache with a known path (tests, or a user-pinned
    /// tool location). Seeded entries never expire — not even seeded nils.
    public func seed(_ tool: Tool, path: String?) {
        cache[tool] = CachedLookup(path: path, expiresAt: nil)
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
        // The standard third-party install prefixes on macOS (Apple Silicon
        // then Intel) — wherever the user's package manager put the binary.
        let installPrefixes = ["/opt/homebrew/bin", "/usr/local/bin"]

        switch tool {
        case .adb:
            return sdkRoots.map { "\($0)/platform-tools/adb" }
                + installPrefixes.map { "\($0)/adb" }
        case .emulator:
            // The emulator launcher only ships with the SDK.
            return sdkRoots.map { "\($0)/emulator/emulator" }
        case .scrcpy, .ffmpeg:
            return installPrefixes.map { "\($0)/\(tool.rawValue)" }
        }
    }

    private func resolveViaLoginShell(_ tool: Tool) async -> String? {
        await resolveViaLoginShellCommand(tool.rawValue)
    }

    /// Ask the user's login shell (which loads their full PATH) to resolve a
    /// command by name — the fallback for tools installed off the app's PATH.
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
        guard let resolved, isExecutableFile(resolved) else { return nil }
        return resolved
    }
}
