import Foundation
import Testing

@testable import ADBKit

/// Drives the parsers with output a real device actually produced.
///
/// The rest of the suite feeds parsers hand-written strings, which encode what we
/// *think* a device says. This replays a committed recording (see
/// `FixtureRecordingTests` to regenerate it), so the padding, column widths,
/// blank lines, and stray formatting of genuine `getprop` / `ls -la` / `logcat`
/// output are exercised. No device is attached, so it runs in CI and on Linux.
///
/// A missing or empty fixture fails the suite rather than skipping: a fixture
/// that silently stops being read is the failure mode this whole tier exists to
/// prevent.
@Suite struct RecordedOutputParserTests {
    private static func loadFixture() throws -> ProcessFixture {
        try ProcessFixture.load(named: ProcessFixture.androidEmulatorName)
    }

    /// Recorded stdout for the first entry whose argument vector ends with the
    /// given tail, so lookups don't depend on the `-s <serial>` prefix.
    private static func stdout(endingWith tail: [String]) throws -> String {
        let recording = try loadFixture()
        let entry = recording.entries.first { Array($0.arguments.suffix(tail.count)) == tail }
        let found = try #require(entry, "no fixture entry ending with \(tail)")
        return try #require(found.stdout, "entry \(tail) has no captured stdout")
    }

    @Test func theFixtureIsPresentAndPopulated() throws {
        let recording = try Self.loadFixture()
        #expect(recording.entries.count >= 10, "only \(recording.entries.count) entries recorded")
        #expect(recording.deviceModel?.isEmpty == false)
        #expect(recording.androidSdk?.isEmpty == false)
        // The recording must stay scrubbed even if someone re-records by hand.
        let joined = recording.entries.compactMap(\.stdout).joined()
        #expect(!joined.contains(NSHomeDirectory()))
    }

    @Test func parsesRealAdbDevicesOutput() throws {
        let devices = DeviceListParser.parse(try Self.stdout(endingWith: ["devices", "-l"]))
        #expect(devices.count == 1, "parsed \(devices.count) devices from the recording")
        let device = try #require(devices.first)
        #expect(device.isReady)
        // Serials were normalized at record time; the parser must still accept it.
        #expect(!device.serial.isEmpty)
        #expect(device.model?.isEmpty == false, "model should come from the -l long form")
    }

    @Test func parsesRealGetpropOutput() throws {
        // ~31 KB of genuine properties, including values with brackets and spaces.
        let props = DeviceProps.parse(try Self.stdout(endingWith: ["shell", "getprop"]))

        #expect(props.count > 200, "only \(props.count) properties parsed")
        #expect(props["ro.build.version.sdk"] == "35")
        #expect(props["ro.product.model"]?.isEmpty == false)
        // No key or value should retain the [bracket] wrapper.
        #expect(!props.keys.contains { $0.hasPrefix("[") || $0.hasSuffix("]") })
        #expect(!props.values.contains { $0.hasPrefix("[") && $0.hasSuffix("]") })
    }

    @Test func parsesRealLsOutputForRootAndSdcard() throws {
        let root = AppInspectionService.parseLsOutput(try Self.stdout(endingWith: ["ls", "-la", "'//'"]))
        let names = Set(root.map(\.name))
        #expect(names.contains("system"))
        #expect(names.contains("data"))
        // `ls -la` opens with a "total N" line that must not become an entry.
        #expect(!names.contains("total"))
        #expect(!names.contains("."), "the . and .. entries should be dropped")
        #expect(!names.contains(".."))
        #expect(root.first { $0.name == "system" }?.isDir == true)

        let sdcard = AppInspectionService.parseLsOutput(
            try Self.stdout(endingWith: ["ls", "-la", "'/sdcard/'"]))
        #expect(!sdcard.isEmpty)
        #expect(sdcard.allSatisfy { !$0.perms.isEmpty }, "every entry should carry permissions")
    }

    @Test func parsesRealLogcatLines() throws {
        let raw = try Self.stdout(endingWith: ["logcat", "-d", "-v", "threadtime", "-T", "60"])
        let lines = raw
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .map(LogcatLineParser.parse)

        #expect(lines.count > 10, "only \(lines.count) logcat lines in the recording")
        // logcat's first line is the "--------- beginning of main" banner, which
        // has no threadtime fields — the parser must not choke on it.
        let structured = lines.filter { !$0.pid.isEmpty }
        #expect(!structured.isEmpty, "no line parsed into threadtime fields")
        #expect(structured.allSatisfy { !$0.level.isEmpty })
        #expect(structured.contains { !$0.tag.isEmpty })
        #expect(structured.allSatisfy { !$0.tid.isEmpty }, "threadtime format carries a tid")
    }

    @Test func parsesRealPsOutputIntoProcessNames() throws {
        let names = LogcatLineParser.parseProcessNames(try Self.stdout(endingWith: ["shell", "ps", "-A", "-o", "PID,NAME"]))

        #expect(names.count > 20, "only \(names.count) processes parsed")
        // Every key is a pid, every value a non-empty name.
        #expect(names.keys.allSatisfy { Int($0) != nil })
        #expect(names.values.allSatisfy { !$0.isEmpty })
        #expect(names.values.contains { $0.contains("system_server") || $0.contains("zygote") })
    }

    @Test func parsesRealMeminfoAndBattery() throws {
        let mem = DeviceOverview.parseMeminfo(try Self.stdout(endingWith: ["cat", "/proc/meminfo"]))
        let total = try #require(mem.total, "MemTotal not parsed")
        let available = try #require(mem.available, "MemAvailable not parsed")
        #expect(total > 0)
        #expect(available > 0)
        #expect(available <= total)

        let battery = DeviceOverview.parseBattery(try Self.stdout(endingWith: ["dumpsys", "battery"]))
        let level = try #require(battery.level, "battery level not parsed")
        #expect((0...100).contains(level))
    }

    // MARK: - Whole-service replay

    @Test func replayingTheFixtureDrivesServicesEndToEnd() async throws {
        // Not just the parsers: the service builds the argument vector, the
        // fixture answers it, and the result comes back parsed — the full path,
        // with no device.
        let runner = FixtureProcessRunner(try Self.loadFixture())
        let locator = ToolLocator(runner: runner, environment: [:])
        await locator.seed(.adb, path: "/fake/adb")
        let client = AdbClient(locator: locator, runner: runner, log: CommandLog())

        let entries = try await FileExplorerService(client: client)
            .list(serial: "emulator-9999", dir: "/")
        #expect(entries.contains { $0.name == "system" })

        let props = try await DeviceProps.all(client: client, serial: "emulator-9999")
        #expect(props["ro.build.version.sdk"] == "35")

        // A serial that never existed at record time still resolves, which is the
        // point of normalizing `-s <serial>`.
        #expect(runner.unmatchedInvocations.isEmpty,
                "unmatched: \(runner.unmatchedInvocations)")
    }
}
