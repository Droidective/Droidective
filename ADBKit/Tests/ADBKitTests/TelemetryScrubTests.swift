import Foundation
import Testing

@testable import ADBKit

/// The privacy promise, moved out of call-site discipline and into the pipe.
/// Every case here is something a call site could plausibly pass by accident.
@Suite struct TelemetryScrubTests {
    // MARK: - What must never leave

    @Test(arguments: [
        "/Users/someone/Downloads/app.apk",
        "~/Library/Application Support/Droidective",
        "./relative/path",
        "C:\\Users\\someone\\app.apk",
        "https://api.example.com/v1/orders?token=abc",
        "http://localhost:8081/symbolicate",
        "someone@example.com",
        "10.0.1.42",
        "192.168.1.1",
        "fe80::1",
        "com.example.myapp",
        "org.mozilla.firefox",
        "emulator-5554:5555",
        "SELECT * FROM users",
        "user typed: why is this broken?!",
        "adb shell pm clear com.foo",
        "%2Fsecret%2Fpath",
        "\"quoted content\"",
        "café",
        "日本語のテキスト",
    ])
    func unsafeValuesAreRejected(_ value: String) {
        #expect(!TelemetryScrub.isSafe(value), "\(value) must not leave the machine")
    }

    @Test func proseIsRejectedByLength() {
        #expect(!TelemetryScrub.isSafe(String(repeating: "a", count: 513)))
        #expect(TelemetryScrub.isSafe(String(repeating: "a", count: 512)))
    }

    /// The rule that catches a command line, which clears every other check —
    /// alphanumeric words, a two-component package id, no path separators.
    @Test func anythingWithWhitespaceIsContent() {
        #expect(!TelemetryScrub.isSafe("adb shell pm clear com.foo"))
        #expect(!TelemetryScrub.isSafe("two words"))
        #expect(!TelemetryScrub.isSafe("tab\tseparated"))
        #expect(!TelemetryScrub.isSafe("line\nbreak"))
    }

    @Test func anEmptyStringIsNotAValue() {
        #expect(!TelemetryScrub.isSafe(""))
    }

    // MARK: - What must still get through

    @Test(arguments: [
        "reactotron",
        "js-console",
        "apk-open",
        "none",
        "unset",
        "3.12.1",
        "26.2.0",
        "arm64",
        "cpu",
        "memory",
        "instantAction",
        "react-native",
        "1024",
        // `open_features`: the longest legitimate value there is.
        "api-client,apps,crash-catcher,custom-commands,home,install-app,mirror-wall,reactotron,scrcpy,terminal",
    ])
    func labelsAndVersionsPassThrough(_ value: String) {
        #expect(TelemetryScrub.isSafe(value), "\(value) is a legitimate label")
    }

    /// The line between a version and a package id is whether the components
    /// are numbers. Getting this wrong either leaks bundle ids or silently
    /// blanks the app-version column on every event.
    @Test func versionsSurviveTheReverseDNSCheck() {
        #expect(!TelemetryScrub.looksLikeReverseDNS("26.2.0"))
        #expect(!TelemetryScrub.looksLikeReverseDNS("3.12.1"))
        #expect(TelemetryScrub.looksLikeReverseDNS("com.example.app"))
        #expect(TelemetryScrub.looksLikeReverseDNS("a.b.c"))
        #expect(!TelemetryScrub.looksLikeReverseDNS("js-console"), "two components is not reverse DNS")
    }

    @Test func aThreePartVersionIsNotAnIPAddress() {
        #expect(!TelemetryScrub.looksLikeIPv4("26.2.0"))
        #expect(TelemetryScrub.looksLikeIPv4("10.0.1.42"))
        #expect(!TelemetryScrub.looksLikeIPv4("1.2.3.4567"), "a group over three digits is not an octet")
    }

    // MARK: - Scrubbing a bag

    @Test func numbersAndBooleansAreAlwaysFine() {
        let (cleaned, redacted) = TelemetryScrub.scrub([
            "memory_mb": 1_636, "cpu_avg": 12.5, "is_change": true, "rows": UInt64(900),
        ])
        #expect(redacted == 0)
        #expect(cleaned["memory_mb"] as? Int == 1_636)
        #expect(cleaned["is_change"] as? Bool == true)
    }

    /// A rejected value leaves a visible marker, not a missing key. A hole
    /// gets asked about; an absence looks like the event was never sent.
    @Test func aRejectedValueIsMarkedRatherThanDropped() {
        let (cleaned, redacted) = TelemetryScrub.scrub([
            "feature": "reactotron",
            "path": "/Users/someone/secret.apk",
        ])
        #expect(redacted == 1)
        #expect(cleaned["feature"] as? String == "reactotron")
        #expect(cleaned["path"] as? String == TelemetryScrub.redactedMarker)
        #expect(cleaned.keys.count == 2, "the key survives so the leak is visible")
    }

    @Test func aListIsScrubbedElementByElement() {
        let (cleaned, redacted) = TelemetryScrub.scrub([
            "open_features": ["home", "/Users/someone/x", "scrcpy"],
        ])
        #expect(redacted == 1)
        #expect(cleaned["open_features"] as? [String] == ["home", TelemetryScrub.redactedMarker, "scrcpy"])
    }

    /// A stringified object is exactly how content would escape, so anything
    /// that is not a number, a bool, a string or a list of strings is refused
    /// on sight rather than described.
    @Test func anUnexpectedTypeIsRefusedRatherThanDescribed() {
        let (cleaned, redacted) = TelemetryScrub.scrub([
            "payload": ["nested": "value"],
            "when": Date(),
        ])
        #expect(redacted == 2)
        #expect(cleaned["payload"] as? String == TelemetryScrub.redactedMarker)
        #expect(cleaned["when"] as? String == TelemetryScrub.redactedMarker)
    }

    /// Keys cross the same wire as values. Nothing derives one from user input
    /// today, and this is what keeps that true.
    @Test func anUnsafeKeyIsRedactedToo() {
        let (cleaned, _) = TelemetryScrub.scrub(["/Users/someone/file": 1])
        #expect(cleaned[TelemetryScrub.redactedMarker] as? Int == 1)
        #expect(cleaned["/Users/someone/file"] == nil)
    }

    @Test func anEmptyBagScrubsToAnEmptyBag() {
        let (cleaned, redacted) = TelemetryScrub.scrub([:])
        #expect(cleaned.isEmpty)
        #expect(redacted == 0)
    }
}
