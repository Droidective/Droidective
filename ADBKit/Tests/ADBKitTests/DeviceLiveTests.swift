import Foundation
import Testing

@testable import ADBKit

/// Tier 3 of the verification harness: ADBKit's services against a real device.
///
/// The mock suite proves we send the right adb arguments; this proves the device
/// answers the way the parsers expect. Every assertion is deterministic — either
/// a property Android always defines, or a marker this suite plants itself — so a
/// pass means the path works, not that the device happened to be chatty.
///
/// Disabled by default. Run via `scripts/emulator-harness.sh`, which boots an
/// emulator and sets the gate, or by hand with
/// `DEVICE_LIVE_TEST=1 MIRROR_SERIAL=emulator-5554 swift test --filter DeviceLiveTests`.
@Suite struct DeviceLiveTests {
    private static var liveEnabled: Bool {
        ProcessInfo.processInfo.environment["DEVICE_LIVE_TEST"] == "1"
    }

    private static var serial: String {
        ProcessInfo.processInfo.environment["MIRROR_SERIAL"] ?? "emulator-5554"
    }

    private static var adb: AdbClient {
        AdbClient(locator: ToolLocator())
    }

    @Test(.enabled(if: liveEnabled))
    func deviceListParserSeesTheAttachedDevice() async throws {
        let result = try await Self.adb.run(["devices", "-l"])
        #expect(result.succeeded)

        let devices = DeviceListParser.parse(result.stdout)
        let mine = devices.first { $0.serial == Self.serial }
        #expect(mine != nil, "\(Self.serial) not in parsed device list: \(devices.map(\.serial))")
        #expect(mine?.isReady == true)
    }

    @Test(.enabled(if: liveEnabled))
    func getpropExposesCoreProperties() async throws {
        let props = try await DeviceProps.all(client: Self.adb, serial: Self.serial)
        // Every Android build defines these two; a parser that mis-splits the
        // `[key]: [value]` form would drop them.
        #expect(props["ro.build.version.sdk"]?.isEmpty == false)
        #expect(props["ro.product.model"]?.isEmpty == false)
    }

    @Test(.enabled(if: liveEnabled))
    func logcatDumpContainsAPlantedMarker() async throws {
        // A unique marker makes this deterministic: we are not hoping the device
        // logged something, we put the line there ourselves.
        let marker = "droidective-live-\(UUID().uuidString)"
        let planted = try await Self.adb.run(
            on: Self.serial, ["shell", "log", "-t", "DroidectiveLive", shellQuote(marker)])
        #expect(planted.succeeded)

        let dump = try await Self.adb.run(
            on: Self.serial, ["logcat", "-d", "-t", "400"], maxOutputBytes: 8 * 1024 * 1024)
        #expect(dump.succeeded)
        #expect(dump.stdout.contains(marker), "planted marker missing from logcat dump")

        // Split on .newlines, never "\n" — the CRLF trap this repo learned.
        let parsed = dump.stdout
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .map(LogcatLineParser.parse)
        let markerLine = parsed.first { $0.message.contains(marker) }
        #expect(markerLine != nil, "parser did not surface the marker line")
        #expect(markerLine?.tag == "DroidectiveLive")
        #expect(markerLine?.pid.isEmpty == false)
    }

    @Test(.enabled(if: liveEnabled))
    func logcatStreamDeliversLinesFromTheDevice() async throws {
        // Exercises the streaming reader (FileHandleLines on the port branch),
        // which the dump test above does not touch.
        let streamer = LogcatStreamer(client: Self.adb)
        let stream = try await streamer.start(
            serial: Self.serial, filters: LogcatFilters(tail: 200))

        // Stopping the streamer terminates the stream, so a silent device fails
        // this test instead of hanging it.
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(30))
            await streamer.stop()
        }

        var lineCount = 0
        for await batch in stream {
            lineCount += batch.count
            if lineCount > 0 { break }
        }
        watchdog.cancel()
        await streamer.stop()

        #expect(lineCount > 0, "logcat stream produced no lines")
    }

    @Test(.enabled(if: liveEnabled))
    func screenshotReturnsDecodablePngBytes() async throws {
        let service = ScreenCaptureService(client: Self.adb)
        let data = try await service.captureScreenshotData(serial: Self.serial)

        // The PNG signature — proves exec-out's binary path didn't text-mangle it,
        // which is exactly what a CRLF-translating read would do.
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        #expect(data.count > 1024, "screenshot suspiciously small: \(data.count) bytes")
        #expect(Array(data.prefix(8)) == signature, "not a PNG")
    }

    @Test(.enabled(if: liveEnabled))
    func appListingIncludesAStockSystemPackage() async throws {
        let service = AppsExplorerService(client: Self.adb)
        let apps = try await service.listAll(serial: Self.serial)

        #expect(apps.count > 10, "only \(apps.count) packages parsed")
        let settings = apps.first { $0.packageId == "com.android.settings" }
        #expect(settings != nil, "com.android.settings missing from the parsed list")
        #expect(settings?.isSystem == true)
    }

    @Test(.enabled(if: liveEnabled))
    func fileExplorerListsTheRootDirectory() async throws {
        let service = FileExplorerService(client: Self.adb)
        let entries = try await service.list(serial: Self.serial, dir: "/")

        let names = Set(entries.map(\.name))
        // Present on every Android image.
        #expect(names.contains("system"), "root listing missing 'system': \(names.sorted())")
        #expect(names.contains("data"), "root listing missing 'data': \(names.sorted())")
        #expect(entries.first { $0.name == "system" }?.isDir == true)
    }
}
