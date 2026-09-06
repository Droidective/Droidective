import Testing
@testable import ADBKit

@Suite struct MediaScanTests {
    @Test func modernDevicesGetTheProviderCall() {
        #expect(MediaScan.command(sdk: 34, path: "/sdcard/Download/shot.png") == [
            "shell", "content", "call",
            "--uri", "content://media/external/file",
            "--method", "scan_file",
            "--arg", "'/sdcard/Download/shot.png'",
        ])
    }

    @Test func preAndroid10DevicesGetTheBroadcast() {
        #expect(MediaScan.command(sdk: 28, path: "/sdcard/Download/shot.png") == [
            "shell", "am", "broadcast",
            "-a", "android.intent.action.MEDIA_SCANNER_SCAN_FILE",
            "-d", "'file:///sdcard/Download/shot.png'",
        ])
    }

    @Test func android10IsTheFirstProviderCallRelease() {
        #expect(MediaScan.command(sdk: 29, path: "/x")[1] == "content")
        #expect(MediaScan.command(sdk: 28, path: "/x")[1] == "am")
    }

    @Test func anUnknownSdkTakesTheModernRoute() {
        #expect(MediaScan.command(sdk: nil, path: "/x")[1] == "content")
    }

    @Test func aHostileFileNameIsQuotedForTheDeviceShell() {
        // The name came from Finder. Unquoted, the `;` ends the command and
        // whatever follows runs on the device — this is the shellQuote
        // boundary, and it has to hold on both routes.
        let nasty = "/sdcard/Download/x'; touch /sdcard/pwned; echo '.png"
        let modern = MediaScan.command(sdk: 34, path: nasty)
        #expect(modern.last == shellQuote(nasty))
        #expect(modern.last?.hasPrefix("'") == true)
        #expect(modern.last?.contains("pwned") == true)
        // The embedded quote is escaped, so the payload never leaves the
        // single-quoted string.
        #expect(modern.last?.contains("'\\''") == true)
        let legacy = MediaScan.command(sdk: 24, path: nasty)
        #expect(legacy.last == shellQuote("file://" + nasty))
    }
}
