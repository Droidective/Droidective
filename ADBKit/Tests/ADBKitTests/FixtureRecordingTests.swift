import Foundation
import Testing

@testable import ADBKit

/// Records a fixture from a live device. Not a test of anything — a generator.
///
/// Run it deliberately, review the resulting JSON diff, and commit it. From then
/// on `RecordedOutputParserTests` replays that output with no device attached, so
/// the parsers are exercised against what a device really said on a Linux CI host
/// that has never seen an emulator.
///
/// `RECORD_FIXTURES=1 MIRROR_SERIAL=emulator-5554 swift test --filter FixtureRecordingTests`
/// or `scripts/emulator-harness.sh --record`.
@Suite struct FixtureRecordingTests {
    private static var recordingEnabled: Bool {
        ProcessInfo.processInfo.environment["RECORD_FIXTURES"] == "1"
    }

    @Test(.enabled(if: recordingEnabled))
    func recordAndroidEmulatorFixture() async throws {
        let serial = ProcessInfo.processInfo.environment["MIRROR_SERIAL"] ?? "emulator-5554"

        // The locator keeps the plain runner: its host probing resolves absolute
        // paths under the developer's home directory, which has no business in a
        // committed fixture. Only adb invocations go through the recorder.
        let locator = ToolLocator()
        let recorder = RecordingProcessRunner(wrapping: SystemProcessRunner(), serial: serial)
        let client = AdbClient(locator: locator, runner: recorder, log: CommandLog())

        // Drive the real service methods wherever one exists, so the recorded
        // argument vectors are by construction the ones production sends. Writing
        // the argv by hand here defeats the point: an approximation records output
        // in a format the parser never actually receives. (Recording plain
        // `ps -A` instead of the `-o PID,NAME` form the streamer uses produced
        // exactly that — output the process-name parser correctly rejects.)
        //
        // Failures are tolerated per-call: a device that refuses one command
        // should still yield a fixture for the rest.
        _ = try? await client.run(["devices", "-l"])
        let props = try? await DeviceProps.all(client: client, serial: serial)
        _ = try? await AppsExplorerService(client: client).listAll(serial: serial)
        _ = try? await FileExplorerService(client: client).list(serial: serial, dir: "/")
        _ = try? await FileExplorerService(client: client).list(serial: serial, dir: "/sdcard")
        _ = await LogcatStreamer(client: client).processNames(serial: serial)

        // A logcat dump in the same `-v threadtime` format `LogcatLineParser`
        // parses live, so the fixture matches what the streamer really reads.
        _ = try? await client.run(
            on: serial, ["logcat", "-d", "-v", "threadtime", "-T", "60"],
            maxOutputBytes: 4 * 1024 * 1024)

        _ = try? await client.run(on: serial, ["shell", "dumpsys", "battery"])
        _ = try? await client.run(on: serial, ["shell", "cat", "/proc/meminfo"])
        _ = try? await client.run(on: serial, ["shell", "cat", "/proc/net/dev"])
        _ = try? await client.run(on: serial, ["shell", "wm", "size"])
        _ = try? await client.run(on: serial, ["shell", "settings", "get", "global", "http_proxy"])

        let fixture = recorder.fixture(
            deviceModel: props?["ro.product.model"],
            androidSdk: props?["ro.build.version.sdk"]
        )
        #expect(fixture.entries.count >= 10, "recorded only \(fixture.entries.count) entries")
        try fixture.write(named: ProcessFixture.androidEmulatorName)

        // Nothing sensitive may reach disk. Assert on the serialized bytes rather
        // than the in-memory model, because the file is what gets committed.
        let written = try String(
            contentsOf: ProcessFixture.url(named: ProcessFixture.androidEmulatorName),
            encoding: .utf8)
        #expect(!written.contains(NSHomeDirectory()))
        #expect(!written.contains(serial))
    }
}
