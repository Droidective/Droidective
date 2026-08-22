import Foundation

/// Assembles a lightweight bug-report zip: screenshot + recent logcat +
/// device info + (optional) app version. Built in a temp dir, zipped with the
/// host's own archiver (`HostArchive`), dropped in ~/Downloads/Droidective —
/// or wherever the caller says.
public struct BugReportService: Sendable {
    static let infoKeys = [
        "ro.product.brand",
        "ro.product.model",
        "ro.product.cpu.abi",
        "ro.build.version.release",
        "ro.build.version.sdk",
        "ro.build.display.id",
        "ro.serialno",
    ]

    let client: AdbClient

    public init(client: AdbClient) {
        self.client = client
    }

    /// Builds the report and answers where it landed.
    ///
    /// `into` is nil for the app's own capture folder, which is what the Mac
    /// passes. The daemon supplies a folder instead, because *its* client has
    /// already decided where downloaded things go and two answers to that
    /// question is one too many.
    public func create(serial: String, packageId: String?, into folder: URL? = nil) async throws -> URL {
        let id = ScreenCaptureService.stamp()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("bugreport-\(id)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let screenshot = try? await client.runBinary(on: serial, ["exec-out", "screencap", "-p"])
        if let screenshot, screenshot.exitCode == 0, !screenshot.stdout.isEmpty {
            try? screenshot.stdout.write(to: tmp.appendingPathComponent("screenshot.png"))
        }

        let log = try await client.run(
            on: serial, ["logcat", "-d", "-t", "2000"], maxOutputBytes: 20 * 1024 * 1024
        )
        try Data(log.stdout.utf8).write(to: tmp.appendingPathComponent("logcat.txt"))

        let props = try await DeviceProps.all(client: client, serial: serial)
        let info = Self.infoKeys.map { "\($0): \(props[$0] ?? "—")" }.joined(separator: "\n")
        try Data(info.utf8).write(to: tmp.appendingPathComponent("device-info.txt"))

        if let packageId, !packageId.isEmpty {
            let dump = try await client.run(on: serial, ["shell", "dumpsys", "package", shellQuote(packageId)])
            let name = dump.stdout.firstMatch(of: /versionName=(\S+)/).map { String($0.1) } ?? "?"
            let code = dump.stdout.firstMatch(of: /versionCode=(\d+)/).map { String($0.1) } ?? "?"
            try Data("versionName=\(name)\nversionCode=\(code)".utf8)
                .write(to: tmp.appendingPathComponent("app-info.txt"))
        }

        let outDir = try folder ?? ScreenCaptureService.ensureCaptureDir()
        if folder != nil {
            try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        }
        let zipPath = outDir.appendingPathComponent("bug-report_\(id).zip")
        let runner = SystemProcessRunner()
        let zip = await runner.run(
            executable: HostArchive.zipExecutable,
            arguments: HostArchive.zipArguments(archive: zipPath.path, from: tmp.path),
            timeout: .seconds(60),
            maxOutputBytes: 10 * 1024 * 1024
        )
        guard zip.exitCode == 0 else {
            // Naming the archiver matters off macOS: `zip` is a package a Linux
            // host may simply not have installed, and "couldn't create the zip"
            // on its own sends someone looking at the device instead.
            throw AppInspectionService.PullError.failed(
                "Couldn't create the zip with \(HostArchive.zipExecutable): \(zip.stderrText)")
        }
        return zipPath
    }
}
