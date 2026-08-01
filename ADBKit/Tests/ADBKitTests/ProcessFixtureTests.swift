import Foundation
import Testing

@testable import ADBKit

/// Tests for the fixture recorder itself. It writes files that get committed, so
/// a redaction bug would leak a Wi-Fi password or a device identifier into git —
/// worth testing more carefully than the thing it records.
@Suite struct ProcessFixtureTests {
    // MARK: - Redaction

    @Test func scrubsIPv4AddressesMacsAndTheDeviceSerial() {
        let raw = """
            inet 192.168.1.42/24 brd 192.168.1.255
            link/ether a4:83:e7:1b:2c:3d brd ff:ff:ff:ff:ff:ff
            device emulator-5554 is ready
            """
        let scrubbed = FixtureRedaction.scrub(raw, serial: "emulator-5554")

        #expect(!scrubbed.contains("192.168.1.42"))
        #expect(!scrubbed.contains("192.168.1.255"))
        #expect(!scrubbed.contains("a4:83:e7:1b:2c:3d"))
        #expect(!scrubbed.contains("emulator-5554"))
        #expect(scrubbed.contains("<ipv4>"))
        #expect(scrubbed.contains("<mac>"))
        #expect(scrubbed.contains("<serial>"))
    }

    @Test func scrubbingLeavesNonSensitiveTextIntact() {
        let raw = "package:com.android.settings\nversionName=15"
        #expect(FixtureRedaction.scrub(raw, serial: "emulator-5554") == raw)
    }

    @Test func scrubbingToleratesANilOrEmptySerial() {
        #expect(FixtureRedaction.scrub("plain text", serial: nil) == "plain text")
        #expect(FixtureRedaction.scrub("plain text", serial: "") == "plain text")
    }

    @Test func scrubsTheRecordingHostsHomeDirectory() {
        // Fixtures are committed, so a developer's username must not ride along —
        // and an absolute host path would break the suite on a Linux CI host.
        let raw = "resolved adb at \(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb"
        let scrubbed = FixtureRedaction.scrub(raw, serial: nil)

        #expect(!scrubbed.contains(NSHomeDirectory()))
        #expect(scrubbed.contains("<home>"))
        #expect(scrubbed.contains("platform-tools/adb"), "the useful part should survive")
    }

    @Test func recordsTheExecutableAsABasenameNotAHostPath() async {
        let mock = MockProcessRunner()
        mock.script(argsPrefix: ["devices"], stdout: "ok\n")
        let recorder = RecordingProcessRunner(wrapping: mock, serial: nil)

        _ = await recorder.run(
            executable: "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb",
            arguments: ["devices"], timeout: .seconds(5), maxOutputBytes: 1024)

        #expect(recorder.recorded[0].executable == "adb")
    }

    @Test func deniesCommandsWhoseWholeOutputIsSecret() {
        // Wi-Fi credential stores: the payload is the secret, so scrubbing a
        // pattern out of it is not enough.
        #expect(FixtureRedaction.isDenied(arguments: [
            "-s", "S1", "shell", "su", "-c", "'cat /data/misc/wifi/WifiConfigStore.xml'",
        ]))
        #expect(FixtureRedaction.isDenied(arguments: ["shell", "cat", "wpa_supplicant.conf"]))
        // Any root command — contents unknowable.
        #expect(FixtureRedaction.isDenied(arguments: ["-s", "S1", "shell", "su", "-c", "'id'"]))
    }

    @Test func allowsOrdinaryCommands() {
        #expect(!FixtureRedaction.isDenied(arguments: ["devices", "-l"]))
        #expect(!FixtureRedaction.isDenied(arguments: ["-s", "S1", "shell", "getprop"]))
        // `su` without `-c` is not the denied shape.
        #expect(!FixtureRedaction.isDenied(arguments: ["-s", "S1", "shell", "su"]))
    }

    // MARK: - Recording

    @Test func recordsPassedThroughInvocationsWithScrubbedOutput() async {
        let mock = MockProcessRunner()
        mock.script(argsPrefix: ["devices"], stdout: "emulator-5554\tdevice 10.0.0.5\n")
        let recorder = RecordingProcessRunner(wrapping: mock, serial: "emulator-5554")

        let output = await recorder.run(
            executable: "/fake/adb", arguments: ["devices", "-l"],
            timeout: .seconds(5), maxOutputBytes: 1024)

        // The caller still gets the real, unscrubbed output.
        #expect(output.stdoutText.contains("emulator-5554"))
        // What lands on disk does not.
        let entries = recorder.recorded
        #expect(entries.count == 1)
        #expect(entries[0].arguments == ["devices", "-l"])
        #expect(entries[0].stdout?.contains("<serial>") == true)
        #expect(entries[0].stdout?.contains("10.0.0.5") == false)
        #expect(entries[0].exitCode == 0)
    }

    @Test func recordsNothingForADeniedCommandButStillReturnsItsOutput() async {
        let mock = MockProcessRunner()
        mock.script(argsPrefix: ["-s"], stdout: "<WifiConfigStore><password>hunter2</password>")
        let recorder = RecordingProcessRunner(wrapping: mock, serial: "S1")

        let output = await recorder.run(
            executable: "/fake/adb",
            arguments: ["-s", "S1", "shell", "su", "-c", "'cat WifiConfigStore.xml'"],
            timeout: .seconds(5), maxOutputBytes: 1024)

        #expect(output.stdoutText.contains("hunter2"), "caller must still get real output")
        #expect(recorder.recorded.isEmpty, "denied command must not be recorded")
    }

    @Test func recordsBinaryOutputAsMetadataOnly() async {
        // A PNG signature plus invalid UTF-8 — a screenshot, in miniature.
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0xFF, 0xFE, 0xFD])
        let stub = FixedOutputRunner(
            ProcessOutput(stdout: png, stderr: Data(), exitCode: 0, timedOut: false))
        let recorder = RecordingProcessRunner(wrapping: stub, serial: nil)

        _ = await recorder.run(
            executable: "/fake/adb", arguments: ["exec-out", "screencap", "-p"],
            timeout: .seconds(5), maxOutputBytes: 1024)

        let entry = recorder.recorded[0]
        #expect(entry.stdout == nil)
        #expect(entry.omittedReason?.contains("binary") == true)
    }

    @Test func recordsOversizedOutputAsMetadataOnly() async {
        let big = Data(String(repeating: "a", count: RecordingProcessRunner.maxRecordedBytes + 1).utf8)
        let stub = FixedOutputRunner(
            ProcessOutput(stdout: big, stderr: Data(), exitCode: 0, timedOut: false))
        let recorder = RecordingProcessRunner(wrapping: stub, serial: nil)

        _ = await recorder.run(
            executable: "/fake/adb", arguments: ["bugreport"],
            timeout: .seconds(5), maxOutputBytes: 100 * 1024 * 1024)

        #expect(recorder.recorded[0].stdout == nil)
        #expect(recorder.recorded[0].omittedReason?.contains("over cap") == true)
    }

    // MARK: - Replay

    @Test func replaysAnExactArgumentVector() async {
        let fixture = ProcessFixture(entries: [
            .init(
                executable: "/fake/adb", arguments: ["devices", "-l"],
                stdout: "List of devices attached\n<serial>\tdevice\n", stderr: "",
                exitCode: 0, timedOut: false, omittedReason: nil)
        ])
        let runner = FixtureProcessRunner(fixture)

        let output = await runner.run(
            executable: "/fake/adb", arguments: ["devices", "-l"],
            timeout: .seconds(5), maxOutputBytes: 1024)

        #expect(output.stdoutText.contains("<serial>"))
        #expect(output.exitCode == 0)
        #expect(runner.unmatchedInvocations.isEmpty)
    }

    @Test func prefersTheLongestMatchingPrefix() async {
        let fixture = ProcessFixture(entries: [
            .init(
                executable: "a", arguments: ["shell"], stdout: "generic", stderr: "",
                exitCode: 0, timedOut: false, omittedReason: nil),
            .init(
                executable: "a", arguments: ["shell", "getprop"], stdout: "specific", stderr: "",
                exitCode: 0, timedOut: false, omittedReason: nil),
        ])
        let runner = FixtureProcessRunner(fixture)

        let output = await runner.run(
            executable: "a", arguments: ["shell", "getprop", "ro.product.model"],
            timeout: .seconds(5), maxOutputBytes: 1024)

        #expect(output.stdoutText == "specific")
    }

    @Test func aFixtureRecordedOnOneDeviceReplaysForAnother() async {
        // The reason arguments are normalized: adb targets a device with
        // `-s <serial>`, so a raw recording would bake in emulator-5554 and then
        // silently fail to match on a host where the emulator took another port.
        let mock = MockProcessRunner()
        mock.script(argsPrefix: ["-s"], stdout: "[ro.product.model]: [Pixel]\n")
        let recorder = RecordingProcessRunner(wrapping: mock, serial: "emulator-5554")
        _ = await recorder.run(
            executable: "/fake/adb", arguments: ["-s", "emulator-5554", "shell", "getprop"],
            timeout: .seconds(5), maxOutputBytes: 1024)

        #expect(recorder.recorded[0].arguments == ["-s", "<serial>", "shell", "getprop"])

        // Replay from a caller on a completely different device.
        let replay = FixtureProcessRunner(recorder.fixture())
        let output = await replay.run(
            executable: "/fake/adb", arguments: ["-s", "emulator-5556", "shell", "getprop"],
            timeout: .seconds(5), maxOutputBytes: 1024)

        #expect(output.stdoutText.contains("Pixel"))
        #expect(replay.unmatchedInvocations.isEmpty, "fixture should be device-independent")
    }

    @Test func normalizationHandlesRepeatedAndTrailingFlags() {
        #expect(
            FixtureRedaction.normalizeArguments(["-s", "abc", "shell", "-s", "def"])
                == ["-s", "<serial>", "shell", "-s", "<serial>"])
        // A trailing `-s` with no value must not index past the end.
        #expect(FixtureRedaction.normalizeArguments(["shell", "-s"]) == ["shell", "-s"])
        #expect(FixtureRedaction.normalizeArguments([]) == [])
        // Serials appearing outside `-s` are scrubbed when known.
        #expect(
            FixtureRedaction.normalizeArguments(["connect", "1.2.3.4:5555"], serial: "1.2.3.4:5555")
                == ["connect", "<serial>"])
    }

    @Test func anUnmatchedInvocationFailsLoudlyInsteadOfReturningEmpty() async {
        let runner = FixtureProcessRunner(ProcessFixture(entries: []))

        let output = await runner.run(
            executable: "a", arguments: ["shell", "whoami"],
            timeout: .seconds(5), maxOutputBytes: 1024)

        // A silent empty stdout is how a parser test passes for the wrong reason.
        #expect(output.exitCode != 0)
        #expect(output.stderrText.contains("no fixture entry"))
        #expect(runner.unmatchedInvocations == [["shell", "whoami"]])
    }

    // MARK: - Round trip

    @Test func survivesAJsonRoundTripThroughDisk() async throws {
        let name = "roundtrip-\(UUID().uuidString)"
        let original = ProcessFixture(
            deviceModel: "sdk_gphone64_arm64", androidSdk: "35",
            entries: [
                .init(
                    executable: "/fake/adb", arguments: ["shell", "getprop"],
                    // CRLF and a trailing newline: exactly the shapes a
                    // hand-written literal tends to omit.
                    stdout: "[ro.product.model]: [Pixel]\r\n[ro.build.version.sdk]: [35]\n",
                    stderr: "", exitCode: 0, timedOut: false, omittedReason: nil)
            ])

        try original.write(named: name)
        defer { try? FileManager.default.removeItem(at: ProcessFixture.url(named: name)) }

        let reloaded = try ProcessFixture.load(named: name)
        #expect(reloaded.deviceModel == "sdk_gphone64_arm64")
        #expect(reloaded.androidSdk == "35")
        #expect(reloaded.entries.count == 1)
        #expect(reloaded.entries[0].stdout == original.entries[0].stdout)

        // And the reloaded fixture still drives a parser.
        let props = DeviceProps.parse(reloaded.entries[0].output.stdoutText)
        #expect(props["ro.product.model"] == "Pixel")
        #expect(props["ro.build.version.sdk"] == "35")
    }
}

/// Returns one canned output for any invocation — for exercising the recorder's
/// binary and size handling without a scripted prefix match.
private final class FixedOutputRunner: ProcessRunning, @unchecked Sendable {
    private let output: ProcessOutput
    init(_ output: ProcessOutput) { self.output = output }
    func run(
        executable: String, arguments: [String], timeout: Duration, maxOutputBytes: Int
    ) async -> ProcessOutput { output }
}
