import Foundation

/// Screen recording via scrcpy. scrcpy records the video (and audio) stream on
/// the Mac side, so it has none of `adb shell screenrecord`'s limits: no ~3-min
/// cap, audio by default (Android 11+), and it survives device rotation. We
/// spawn scrcpy headless (`--no-playback`, no mirror window) writing to a temp
/// MP4, then SIGTERM it to stop — scrcpy finalizes the container (writes the
/// moov atom) on SIGTERM. It ignores SIGINT when run headless, so `terminate()`
/// is required, not `interrupt()`; SIGKILL would leave the file unfinalized. The
/// finished temp file is handed to the editor; nothing lands in the capture
/// folder until the user exports.
public actor ScreenRecorder {
    public enum RecordingError: Error, LocalizedError {
        case alreadyRecording
        case notRecording
        case scrcpyNotFound
        case adbNotFound
        case startFailed(String)

        public var errorDescription: String? {
            switch self {
            case .alreadyRecording: return "A recording is already in progress."
            case .notRecording: return "No active recording."
            case .scrcpyNotFound:
                return "scrcpy isn't installed. Run `brew install scrcpy`, then try again."
            case .adbNotFound: return "adb not found — scrcpy needs it to connect."
            case .startFailed(let reason): return reason
            }
        }
    }

    private let client: AdbClient
    private var child: Process?
    private var localPath: URL?

    public init(client: AdbClient) {
        self.client = client
    }

    public var isRecording: Bool { child != nil }

    public func start(serial: String, options: ScreenRecordOptions = ScreenRecordOptions()) async throws {
        guard child == nil else { throw RecordingError.alreadyRecording }
        guard let scrcpyPath = await client.locator.resolve(.scrcpy) else {
            throw RecordingError.scrcpyNotFound
        }
        guard let adbPath = await client.locator.resolve(.adb) else {
            throw RecordingError.adbNotFound
        }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("droidective-recording-\(ScreenCaptureService.stamp()).mp4")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: scrcpyPath)
        process.arguments = ["-s", serial] + options.args(recordingPath: temp.path)
        process.environment = ScreenTools.scrcpyEnvironment(
            base: ProcessInfo.processInfo.environment,
            scrcpyPath: scrcpyPath,
            adbPath: adbPath
        )
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw RecordingError.startFailed("Couldn't launch scrcpy: \(error.localizedDescription)")
        }
        child = process
        localPath = temp
    }

    /// Stop recording: SIGTERM scrcpy so it finalizes the MP4, wait for it to
    /// exit, and return the finished file. scrcpy shuts down on the next frame
    /// it receives, so a static screen (no frames) can delay the flush by tens
    /// of seconds; we wait up to ~40s before SIGKILL as a last resort (which
    /// would leave the file unfinalized).
    public func stop() async throws -> URL {
        guard let child, let localPath else { throw RecordingError.notRecording }
        self.child = nil
        self.localPath = nil

        child.terminate()
        for _ in 0..<400 where child.isRunning {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        return localPath
    }

    /// Abort and discard (view dismissed / app quit). SIGTERM stops scrcpy, then
    /// removes the temp file.
    public func abort() {
        child?.terminate()
        let temp = localPath
        child = nil
        localPath = nil
        if let temp { try? FileManager.default.removeItem(at: temp) }
    }
}
