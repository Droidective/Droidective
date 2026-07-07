import AVFoundation
import Foundation
import Testing
@testable import ADBKit

/// The live-mirror "record" scenario: a display session and a separate recording
/// session run at the same time (two scrcpy connections), as the mirror now does.
/// Run with `MIRROR_LIVE_TEST=1 swift test --filter MirrorPlusRecordLiveTests`.
// Serialized: each test opens its own scrcpy session(s); running them in
// parallel puts several concurrent connections on one device and the emulator
// starves, failing to bring up video.
@Suite(.serialized) struct MirrorPlusRecordLiveTests {
    private static var liveEnabled: Bool {
        ProcessInfo.processInfo.environment["MIRROR_LIVE_TEST"] == "1"
    }

    /// An installed scrcpy (Homebrew), else the app's bundled server passed via
    /// `SCRCPY_SERVER_JAR` (+ optional `SCRCPY_VERSION`), so these live tests run
    /// in the self-contained repo without `brew install scrcpy`.
    private static func resolveServer(locator: ToolLocator) async -> ScrcpyServerInfo? {
        if let info = await ScrcpyServerLocator.resolve(locator: locator) { return info }
        let env = ProcessInfo.processInfo.environment
        guard let jar = env["SCRCPY_SERVER_JAR"] else { return nil }
        return ScrcpyServerInfo(jarPath: jar, version: env["SCRCPY_VERSION"] ?? "4.0")
    }

    @Test(.enabled(if: liveEnabled))
    func recordSessionCoexistsWithDisplaySession() async throws {
        let serial = ProcessInfo.processInfo.environment["MIRROR_SERIAL"] ?? "emulator-5554"
        let locator = ToolLocator()
        let adb = AdbClient(locator: locator)
        guard let server = await Self.resolveServer(locator: locator) else {
            Issue.record("scrcpy not installed and no SCRCPY_SERVER_JAR set"); return
        }

        // Display session (like the live mirror): video + audio + control.
        let displayParams = ScrcpyServerParams(
            scid: UInt32.random(in: 1 ... 0x7fff_ffff), audio: true, control: true, maxSize: 800)
        let displayConfig = MirrorTransport.Configuration(
            serial: serial, params: displayParams,
            serverVersion: server.version, localJarPath: server.jarPath)
        let display = MirrorSession(adb: adb, config: displayConfig)
        let displayStream = await display.start()
        let drain = Task { do { for try await _ in displayStream {} } catch {} }
        for _ in 0 ..< 60 {
            if await display.currentDimensions() != nil { break }
            try? await Task.sleep(for: .milliseconds(100))
        }

        // Now record via a SECOND session while the display session keeps streaming.
        let recorder = ScreenRecorder(client: adb, server: server)
        try await recorder.start(
            serial: serial, options: ScreenRecordOptions(maxSize: 800, captureAudio: true))
        try await Task.sleep(for: .seconds(3))
        let url = try await recorder.stop()
        defer { try? FileManager.default.removeItem(at: url) }

        // Display session should still be alive after recording.
        let displayAlive = await display.currentDimensions() != nil
        drain.cancel()
        await display.stop()

        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let hasVideo = try await !asset.loadTracks(withMediaType: .video).isEmpty

        #expect(displayAlive)
        #expect(duration > 0)
        #expect(hasVideo)
    }

    /// The recording session decodes every frame for snapshots, so a live preview
    /// frame is available straight from the recorder — no second connection.
    @Test(.enabled(if: liveEnabled))
    func previewFrameIsAvailableWhileRecording() async throws {
        let serial = ProcessInfo.processInfo.environment["MIRROR_SERIAL"] ?? "emulator-5554"
        let locator = ToolLocator()
        let adb = AdbClient(locator: locator)
        guard let server = await Self.resolveServer(locator: locator) else {
            Issue.record("scrcpy not installed and no SCRCPY_SERVER_JAR set"); return
        }

        let recorder = ScreenRecorder(client: adb, server: server)
        try await recorder.start(serial: serial, options: ScreenRecordOptions(maxSize: 800))

        var frame: MirrorSession.Snapshot?
        for _ in 0 ..< 60 {
            if let f = await recorder.previewFrame() { frame = f; break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        let url = try await recorder.stop()
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(frame != nil)
        #expect((frame?.width ?? 0) > 0)
    }
}
