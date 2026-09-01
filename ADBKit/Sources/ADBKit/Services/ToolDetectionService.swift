import Foundation

public struct ToolStatus: Sendable, Equatable {
    public let installed: Bool
    public let path: String?
    public let version: String?
    public let installHint: String

    /// Public so a caller outside ADBKit can script a report — the daemon's
    /// route tests stand up a toolchain rather than requiring one on the host.
    public init(installed: Bool, path: String?, version: String?, installHint: String) {
        self.installed = installed
        self.path = path
        self.version = version
        self.installHint = installHint
    }
}

/// Detects whether the external tools are installed, with an install hint
/// per missing one (shown by the Doctor and the device bar).
public struct ToolDetectionService: Sendable {
    /// adb's hint is per-machine (`InstallHints`), so it is not in this table —
    /// the answer on Ubuntu is an apt command and on a Mac it is Android Studio,
    /// and one sentence cannot be both.
    static let installHints: [Tool: String] = [
        .scrcpy: "Install scrcpy from github.com/Genymobile/scrcpy (optional — the app bundles its own mirror server).",
        .ffmpeg: "Install ffmpeg from ffmpeg.org (optional — the app bundles its own for video export).",
        .emulator: "Bundled with the Android SDK — install it via Android Studio → SDK Manager.",
    ]

    /// The flag each tool prints its version with.
    static let versionArgs: [Tool: [String]] = [
        .adb: ["version"],
        .scrcpy: ["--version"],
        .emulator: ["-version"],
        .ffmpeg: ["-version"],
    ]

    let locator: ToolLocator
    let runner: any ProcessRunning

    public init(locator: ToolLocator, runner: any ProcessRunning = SystemProcessRunner()) {
        self.locator = locator
        self.runner = runner
    }

    /// Detect adb — the only external tool the app gates on (scrcpy and ffmpeg
    /// are bundled). The Doctor uses `detectAll` for the full report.
    public func detectAdb() async -> ToolStatus {
        await detectOne(.adb, versionArgs: ["version"])
    }

    /// Detect every external tool the app can use, for the setup Doctor.
    public func detectAll() async -> [Tool: ToolStatus] {
        await withTaskGroup(of: (Tool, ToolStatus).self) { group in
            for tool in Tool.allCases {
                group.addTask {
                    (tool, await detectOne(tool, versionArgs: Self.versionArgs[tool] ?? ["--version"]))
                }
            }
            var report: [Tool: ToolStatus] = [:]
            for await (tool, status) in group {
                report[tool] = status
            }
            return report
        }
    }

    func detectOne(_ tool: Tool, versionArgs: [String]) async -> ToolStatus {
        let hint = tool == .adb
            ? InstallHints.adb(osRelease: InstallHints.hostOSRelease())
            : (Self.installHints[tool] ?? "")
        guard let path = await locator.resolve(tool) else {
            return ToolStatus(installed: false, path: nil, version: nil, installHint: hint)
        }
        let output = await runner.run(
            executable: path, arguments: versionArgs, timeout: .seconds(8), maxOutputBytes: 1024 * 1024
        )
        let text = output.stdoutText.isEmpty ? output.stderrText : output.stdoutText
        let version = text.split(whereSeparator: \.isNewline).first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return ToolStatus(installed: true, path: path, version: version, installHint: hint)
    }

}
