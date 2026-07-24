import Foundation
import Testing
@testable import ADBKit

/// Asserts each implemented runner issues exactly the adb arguments the
/// reference implementation does — the regression net for ported features.
@Suite struct FeatureEngineTests {
    private func makeEngine(_ runner: MockProcessRunner) async -> FeatureEngine {
        let client = await makeTestClient(runner: runner)
        return FeatureEngine(
            client: client, locator: client.locator, monitor: DeviceMonitor(client: client),
            overridesStore: makeTempOverridesStore(),
            toolsDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("tools-\(UUID().uuidString)")
        )
    }

    @Test func devMenuSendsKeyevent82() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s"], stdout: "")
        let engine = await makeEngine(runner)

        let result = await engine.run(featureID: "open-dev-menu", serial: "S1", params: [:])
        #expect(result.ok)
        #expect(runner.invocations.last?.arguments == ["-s", "S1", "shell", "input", "keyevent", "82"])
    }

    @Test func reloadJsSendsDoubleKeyevent46() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s"], stdout: "")
        let engine = await makeEngine(runner)

        let result = await engine.run(featureID: "reload-js", serial: "S1", params: [:])
        #expect(result.ok)
        #expect(runner.invocations.last?.arguments == ["-s", "S1", "shell", "input", "keyevent", "46", "46"])
    }

    @Test func monkeyQuotesThePackage() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s"], stdout: "Events injected: 10")
        let engine = await makeEngine(runner)

        let result = await engine.run(
            featureID: "monkey", serial: "S1",
            params: ["packageId": .string("com.demo;rm"), "count": .number(10)]
        )
        #expect(result.ok)
        #expect(runner.invocations.last?.arguments == [
            "-s", "S1", "shell", "monkey", "-p", "'com.demo;rm'", "-v", "10",
        ])
    }

    @Test func monkeyTimeoutReportsDeliveredEventsHonestly() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s"], stdout: "Events injected: 4021", exitCode: nil, timedOut: true)
        let engine = await makeEngine(runner)

        let result = await engine.run(
            featureID: "monkey", serial: "S1",
            params: ["packageId": .string("com.demo"), "count": .number(100_000)]
        )
        #expect(!result.ok)
        #expect(result.message == "Monkey stopped after 120s — events already sent were delivered.")
    }

    @Test func localeReportsARequestNotACompletedChange() async {
        // The LOCALE_CHANGED broadcast is best-effort (a full system change can
        // require root), so the toast must not claim the locale was set.
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s"], stdout: "")
        let engine = await makeEngine(runner)

        let result = await engine.run(
            featureID: "locale", serial: "S1", params: ["locale": .string("fr-FR")]
        )
        #expect(result.ok)
        #expect(result.message == "Locale change to fr-FR requested — a full system change can require root.")
    }

    @Test func monkeyIsMarkedDestructiveWithConfirmationCopy() {
        let monkey = FeatureRegistry.byID["monkey"]
        #expect(monkey?.isDestructive == true)
        #expect(monkey?.confirmLabel?.isEmpty == false)
    }

    @Test func processDeathKillsTheChosenBundleAndVerifiesDeath() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s"], stdout: "")
        runner.script(argsPrefix: ["-s", "S1", "shell", "pidof"], stdout: "")
        let engine = await makeEngine(runner)

        let result = await engine.run(
            featureID: "process-death", serial: "S1", params: ["packageId": .string("com.demo.app")]
        )
        #expect(result.ok)
        let args = runner.invocations.map(\.arguments)
        #expect(args.contains(["-s", "S1", "shell", "input", "keyevent", "3"]))
        #expect(args.contains(["-s", "S1", "shell", "am", "kill", "'com.demo.app'"]))
        #expect(args.last == ["-s", "S1", "shell", "pidof", "'com.demo.app'"])
    }

    @Test func processDeathFallsBackToTheForegroundApp() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s"], stdout: "")
        runner.script(argsPrefix: ["-s", "S1", "shell", "pidof"], stdout: "")
        runner.script(
            argsPrefix: ["-s", "S1", "shell", "dumpsys", "activity"],
            stdout: "    mResumedActivity: ActivityRecord{123 u0 com.front.app/.MainActivity t42}"
        )
        let engine = await makeEngine(runner)

        let result = await engine.run(featureID: "process-death", serial: "S1", params: [:])
        #expect(result.ok)
        #expect(result.message.contains("com.front.app"))
        #expect(runner.invocations.map(\.arguments).contains(["-s", "S1", "shell", "am", "kill", "'com.front.app'"]))
    }

    @Test func processDeathReportsASurvivingProcess() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s"], stdout: "")
        runner.script(argsPrefix: ["-s", "S1", "shell", "pidof"], stdout: "12345\n")
        let engine = await makeEngine(runner)

        let result = await engine.run(
            featureID: "process-death", serial: "S1", params: ["packageId": .string("com.demo.app")]
        )
        #expect(!result.ok)
        #expect(result.message.contains("still running"))
    }

    @Test func devHostLocalhostReversesThePort() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s"], stdout: "")
        let engine = await makeEngine(runner)

        let result = await engine.run(
            featureID: "rn-dev-host", serial: "S1", params: ["host": .string("localhost:8088")]
        )
        #expect(result.ok)
        #expect(runner.invocations.last?.arguments == ["-s", "S1", "reverse", "tcp:8088", "tcp:8088"])
    }

    @Test func devHostBarePortMeansLocalhost() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s"], stdout: "")
        let engine = await makeEngine(runner)

        let result = await engine.run(featureID: "rn-dev-host", serial: "S1", params: ["host": .string("8081")])
        #expect(result.ok)
        #expect(runner.invocations.last?.arguments == ["-s", "S1", "reverse", "tcp:8081", "tcp:8081"])
    }

    @Test func devHostRemoteSetsMetroHostWhenTheDeviceAllowsIt() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s"], stdout: "")
        runner.script(argsPrefix: ["-s", "S1", "shell", "getprop"], stdout: "192.168.1.99\n")
        let engine = await makeEngine(runner)

        let result = await engine.run(
            featureID: "rn-dev-host", serial: "S1", params: ["host": .string("192.168.1.99:8081")]
        )
        #expect(result.ok)
        #expect(result.message.contains("metro.host=192.168.1.99"))
        let args = runner.invocations.map(\.arguments)
        #expect(args.contains(["-s", "S1", "shell", "setprop", "metro.host", "'192.168.1.99'"]))
    }

    @Test func devHostRemoteFallsBackToTheDevMenuWhenSetpropIsBlocked() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s"], stdout: "")
        runner.script(argsPrefix: ["-s", "S1", "shell", "getprop"], stdout: "")
        let engine = await makeEngine(runner)

        let result = await engine.run(
            featureID: "rn-dev-host", serial: "S1", params: ["host": .string("192.168.1.99:8081")]
        )
        #expect(!result.ok)
        #expect(result.message.contains("Change Bundle Location"))
        #expect(runner.invocations.last?.arguments == ["-s", "S1", "shell", "input", "keyevent", "82"])
    }

    @Test func devHostRejectsAnInvalidPort() async {
        let runner = MockProcessRunner()
        let engine = await makeEngine(runner)

        let result = await engine.run(
            featureID: "rn-dev-host", serial: "S1", params: ["host": .string("192.168.1.99:http")]
        )
        #expect(!result.ok)
        #expect(runner.invocations.isEmpty)
    }

    @Test func devHostRejectsASchemePrefixedHost() async {
        let runner = MockProcessRunner()
        let engine = await makeEngine(runner)

        let result = await engine.run(
            featureID: "rn-dev-host", serial: "S1", params: ["host": .string("http://192.168.1.99:8081")]
        )
        #expect(!result.ok)
        #expect(result.message.contains("http://"))
        #expect(runner.invocations.isEmpty)
    }

    @Test func devHostRejectsAnIPv6Host() async {
        let runner = MockProcessRunner()
        let engine = await makeEngine(runner)

        let result = await engine.run(featureID: "rn-dev-host", serial: "S1", params: ["host": .string("fe80::1")])
        #expect(!result.ok)
        #expect(result.message.contains("IPv6"))
        #expect(runner.invocations.isEmpty)
    }

    @Test func devHostRemoteWritesDebugHttpHostForTheChosenBundle() async {
        let runner = MockProcessRunner()
        let prefsXML = FeatureEngine.upsertDebugHTTPHost(nil, hostPort: "192.168.1.99:8088")
        runner.script(argsPrefix: ["-s"], stdout: "")
        runner.script(argsPrefix: ["-s", "S1", "shell", "run-as", "'com.demo.app'", "cat"], stdout: prefsXML)
        let engine = await makeEngine(runner)

        let result = await engine.run(
            featureID: "rn-dev-host", serial: "S1",
            params: ["host": .string("192.168.1.99:8088"), "packageId": .string("com.demo.app")]
        )
        #expect(result.ok)
        #expect(result.message.contains("debug_http_host"))
        #expect(result.message.contains("192.168.1.99:8088"))

        let args = runner.invocations.map(\.arguments)
        #expect(args.contains(["-s", "S1", "shell", "run-as", "'com.demo.app'", "id"]))
        let prefsPath = "'shared_prefs/com.demo.app_preferences.xml'"
        let script = "mkdir -p shared_prefs && printf '%s' \(shellQuote(prefsXML)) > \(prefsPath)"
        #expect(args.contains(["-s", "S1", "shell", "run-as", "'com.demo.app'", "sh", "-c", shellQuote(script)]))
        #expect(args.contains(["-s", "S1", "shell", "am", "force-stop", "'com.demo.app'"]))
        #expect(args.contains([
            "-s", "S1", "shell", "monkey", "-p", "'com.demo.app'", "-c", "android.intent.category.LAUNCHER", "1",
        ]))
        #expect(!args.contains { $0.contains("setprop") })
    }

    @Test func devHostRemoteWritesDebugHttpHostForTheForegroundApp() async {
        let runner = MockProcessRunner()
        let prefsXML = FeatureEngine.upsertDebugHTTPHost(nil, hostPort: "192.168.1.99:8081")
        runner.script(argsPrefix: ["-s"], stdout: "")
        runner.script(
            argsPrefix: ["-s", "S1", "shell", "dumpsys", "activity"],
            stdout: "    mResumedActivity: ActivityRecord{123 u0 com.front.app/.MainActivity t42}"
        )
        runner.script(argsPrefix: ["-s", "S1", "shell", "run-as", "'com.front.app'", "cat"], stdout: prefsXML)
        let engine = await makeEngine(runner)

        let result = await engine.run(
            featureID: "rn-dev-host", serial: "S1", params: ["host": .string("192.168.1.99")]
        )
        #expect(result.ok)
        #expect(result.message.contains("com.front.app"))
        let args = runner.invocations.map(\.arguments)
        #expect(args.contains(["-s", "S1", "shell", "run-as", "'com.front.app'", "id"]))
    }

    @Test func devHostRemoteFallsBackToSetpropWhenTheWriteCannotBeVerified() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s"], stdout: "")
        // run-as probe and write succeed, but the prefs read back without the
        // host — the write silently didn't land, so fall back to setprop.
        runner.script(argsPrefix: ["-s", "S1", "shell", "run-as", "'com.demo.app'", "cat"], stdout: "<map></map>")
        runner.script(argsPrefix: ["-s", "S1", "shell", "getprop"], stdout: "192.168.1.99\n")
        let engine = await makeEngine(runner)

        let result = await engine.run(
            featureID: "rn-dev-host", serial: "S1",
            params: ["host": .string("192.168.1.99:8081"), "packageId": .string("com.demo.app")]
        )
        #expect(result.ok)
        #expect(result.message.contains("metro.host=192.168.1.99"))
        let args = runner.invocations.map(\.arguments)
        #expect(args.contains(["-s", "S1", "shell", "setprop", "metro.host", "'192.168.1.99'"]))
    }

    @Test func devHostRemoteDoesNotClaimARelaunchWhenTheAppHasNoLauncherActivity() async {
        let runner = MockProcessRunner()
        let prefsXML = FeatureEngine.upsertDebugHTTPHost(nil, hostPort: "192.168.1.99:8081")
        runner.script(argsPrefix: ["-s"], stdout: "")
        runner.script(argsPrefix: ["-s", "S1", "shell", "run-as", "'com.demo.app'", "cat"], stdout: prefsXML)
        runner.script(
            argsPrefix: ["-s", "S1", "shell", "monkey"],
            stdout: "** No activities found to run, monkey aborted."
        )
        let engine = await makeEngine(runner)

        let result = await engine.run(
            featureID: "rn-dev-host", serial: "S1",
            params: ["host": .string("192.168.1.99:8081"), "packageId": .string("com.demo.app")]
        )
        #expect(result.ok)
        #expect(result.message.contains("reopen the app"))
        #expect(!result.message.contains("relaunched"))
    }

    @Test func devHostRemoteShellQuotesAHostilePackage() async {
        let runner = MockProcessRunner()
        let hostile = "com.evil; rm -rf /"
        let prefsXML = FeatureEngine.upsertDebugHTTPHost(nil, hostPort: "192.168.1.99:8081")
        runner.script(argsPrefix: ["-s"], stdout: "")
        runner.script(argsPrefix: ["-s", "S1", "shell", "run-as", shellQuote(hostile), "cat"], stdout: prefsXML)
        let engine = await makeEngine(runner)

        let result = await engine.run(
            featureID: "rn-dev-host", serial: "S1",
            params: ["host": .string("192.168.1.99:8081"), "packageId": .string(hostile)]
        )
        #expect(result.ok)
        let args = runner.invocations.map(\.arguments)
        // Every run-as token carries the single-quoted package, never a raw
        // metacharacter the device shell could split on.
        #expect(args.contains(["-s", "S1", "shell", "run-as", shellQuote(hostile), "id"]))
        #expect(args.contains(["-s", "S1", "shell", "am", "force-stop", shellQuote(hostile)]))
        #expect(!args.contains { $0.contains(hostile) })
    }

    @Test func devHostRemoteFallsBackToSetpropWhenTheAppIsNotDebuggable() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s"], stdout: "")
        runner.script(
            argsPrefix: ["-s", "S1", "shell", "run-as"],
            stderr: "run-as: package not debuggable: com.demo.app", exitCode: 1
        )
        runner.script(argsPrefix: ["-s", "S1", "shell", "getprop"], stdout: "192.168.1.99\n")
        let engine = await makeEngine(runner)

        let result = await engine.run(
            featureID: "rn-dev-host", serial: "S1",
            params: ["host": .string("192.168.1.99:8081"), "packageId": .string("com.demo.app")]
        )
        #expect(result.ok)
        #expect(result.message.contains("metro.host=192.168.1.99"))
        let args = runner.invocations.map(\.arguments)
        #expect(args.contains(["-s", "S1", "shell", "setprop", "metro.host", "'192.168.1.99'"]))
        #expect(!args.contains { $0.contains("sh") && $0.contains("-c") })
    }

    @Test func upsertDebugHttpHostBuildsAFreshDocumentWhenMissing() {
        let doc = FeatureEngine.upsertDebugHTTPHost(nil, hostPort: "10.0.0.5:8081")
        #expect(doc.contains("<map>"))
        #expect(doc.contains("<string name=\"debug_http_host\">10.0.0.5:8081</string>"))
        #expect(FeatureEngine.upsertDebugHTTPHost("", hostPort: "10.0.0.5:8081") == doc)
    }

    @Test func upsertDebugHttpHostReplacesAnExistingEntryAndKeepsOthers() {
        let existing = """
        <?xml version='1.0' encoding='utf-8' standalone='yes' ?>
        <map>
            <boolean name="js_dev_mode_debug" value="true" />
            <string name="debug_http_host">10.0.0.1:8081</string>
        </map>
        """
        let doc = FeatureEngine.upsertDebugHTTPHost(existing, hostPort: "10.0.0.9:8082")
        #expect(doc.contains("<string name=\"debug_http_host\">10.0.0.9:8082</string>"))
        #expect(!doc.contains("10.0.0.1:8081"))
        #expect(doc.contains("js_dev_mode_debug"))
    }

    @Test func upsertDebugHttpHostInsertsIntoAMapWithoutTheEntry() {
        let existing = """
        <?xml version='1.0' encoding='utf-8' standalone='yes' ?>
        <map>
            <boolean name="js_dev_mode_debug" value="true" />
        </map>
        """
        let doc = FeatureEngine.upsertDebugHTTPHost(existing, hostPort: "10.0.0.9:8081")
        #expect(doc.contains("<string name=\"debug_http_host\">10.0.0.9:8081</string>"))
        #expect(doc.contains("js_dev_mode_debug"))

        let selfClosing = FeatureEngine.upsertDebugHTTPHost("<map/>", hostPort: "10.0.0.9:8081")
        #expect(selfClosing.contains("<string name=\"debug_http_host\">10.0.0.9:8081</string>"))
    }

    @Test func upsertDebugHttpHostEscapesXMLMetacharacters() {
        let doc = FeatureEngine.upsertDebugHTTPHost(nil, hostPort: "a&b<c>:8081")
        #expect(doc.contains("a&amp;b&lt;c&gt;:8081"))
    }

    @Test func devHostRemoteWithACustomPortPointsAtTheDevMenu() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s"], stdout: "")
        runner.script(argsPrefix: ["-s", "S1", "shell", "getprop"], stdout: "192.168.1.99\n")
        let engine = await makeEngine(runner)

        let result = await engine.run(
            featureID: "rn-dev-host", serial: "S1", params: ["host": .string("192.168.1.99:8088")]
        )
        #expect(result.ok)
        #expect(result.message.contains("Change Bundle Location"))
        #expect(result.message.contains("192.168.1.99:8088"))
    }

    @Test func reversePortValidatesAndRuns() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s"], stdout: "")
        let engine = await makeEngine(runner)

        let bad = await engine.run(featureID: "reverse-port", serial: "S1", params: ["port": .string("99999")])
        #expect(!bad.ok)
        #expect(bad.message == "Enter a valid port (1–65535).")
        #expect(runner.invocations.isEmpty)

        let good = await engine.run(featureID: "reverse-port", serial: "S1", params: ["port": .string("8081")])
        #expect(good.ok)
        #expect(good.message == "Reversed port 8081")
        #expect(runner.invocations.last?.arguments == ["-s", "S1", "reverse", "tcp:8081", "tcp:8081"])
    }

    @Test func disconnectAllOmitsTarget() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["disconnect"], stdout: "")
        runner.script(argsPrefix: ["devices"], stdout: "List of devices attached\n")
        let engine = await makeEngine(runner)

        let result = try await engine.connection.disconnect(target: nil)
        #expect(result.ok)
        #expect(result.message == "Disconnected all wireless devices")
        #expect(runner.invocations.contains { $0.arguments == ["disconnect"] })
    }

    @Test func disconnectWithTargetPassesIt() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["disconnect"], stdout: "")
        runner.script(argsPrefix: ["devices"], stdout: "List of devices attached\n")
        let engine = await makeEngine(runner)

        let result = try await engine.connection.disconnect(target: "192.168.1.42:5555")
        #expect(result.message == "Disconnected 192.168.1.42:5555")
        #expect(runner.invocations.contains { $0.arguments == ["disconnect", "192.168.1.42:5555"] })
    }

    @Test func getIpParsesWlanThenFallsBackToRoute() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1", "shell", "ip", "-f"], stdout: "wlan0: no address")
        runner.script(
            argsPrefix: ["-s", "S1", "shell", "ip", "route"],
            stdout: "default via 192.168.1.1 dev wlan0 src 10.1.2.3"
        )
        let engine = await makeEngine(runner)

        let result = await engine.run(featureID: "get-ip", serial: "S1", params: [:])
        #expect(result.ok)
        #expect(result.copyText == "10.1.2.3")
    }

    @Test func sendTextAsciiUsesInputText() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s"], stdout: "")
        let engine = await makeEngine(runner)

        let result = await engine.run(featureID: "send-text", serial: "S1", params: ["text": .string("hi there")])
        #expect(result.ok)
        #expect(runner.invocations.last?.arguments == ["-s", "S1", "shell", "input", "text", "hi%sthere"])
    }

    @Test func sendTextUnicodeWithoutAdbKeyboardFails() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1", "shell", "ime", "list"], stdout: "com.google.android.inputmethod.latin/.IME")
        let engine = await makeEngine(runner)

        let result = await engine.run(featureID: "send-text", serial: "S1", params: ["text": .string("héllo")])
        #expect(!result.ok)
        #expect(result.message.contains("ADBKeyboard"))
    }

    @Test func networkTogglesReportsSuccessWhenAllCommandsSucceed() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s"], stdout: "")
        let engine = await makeEngine(runner)

        let result = await engine.run(
            featureID: "network-toggles", serial: "S1",
            params: ["wifi": .bool(false), "data": .bool(true), "airplane": .bool(false)]
        )
        #expect(result.ok)
        #expect(result.message.contains("Wi-Fi off"))
    }

    @Test func networkTogglesReportsFailureInsteadOfFalseSuccess() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s"], stdout: "")
        // `svc data disable` is rejected on this ROM.
        runner.script(argsPrefix: ["-s", "S1", "shell", "svc", "data"], stderr: "Permission denial", exitCode: 1)
        let engine = await makeEngine(runner)

        let result = await engine.run(
            featureID: "network-toggles", serial: "S1",
            params: ["wifi": .bool(true), "data": .bool(false), "airplane": .bool(false)]
        )
        #expect(!result.ok)
        #expect(result.message.contains("data"))
    }

    @Test func unimplementedFeatureReportsPlaceholder() async {
        let runner = MockProcessRunner()
        let engine = await makeEngine(runner)

        let result = await engine.run(featureID: "logcat", serial: "S1", params: [:])
        #expect(!result.ok)
        #expect(result.message.contains("isn't implemented yet"))
    }

    @Test func implementedIDsAreAllRealFeatures() {
        // A typo'd or stale id in implementedIDs would silently mark a
        // non-existent feature as runnable.
        let registryIDs = Set(FeatureRegistry.byID.keys)
        for id in FeatureEngine.implementedIDs {
            #expect(registryIDs.contains(id), "implementedIDs lists \"\(id)\", which is not in the registry")
        }
    }

    @Test func everyImplementedActionResolvesToARunner() async {
        // The #1 scaling hazard: an action feature added to implementedIDs but
        // missing its dispatch case silently falls through to the "coming soon"
        // placeholder, with no other signal. (View features are intentionally in
        // implementedIDs without a dispatch case — the App layer serves them —
        // so this guard is scoped to action kinds.)
        let runner = MockProcessRunner()
        runner.script(argsPrefix: [], stdout: "")
        let engine = await makeEngine(runner)
        let actionKinds: Set<FeatureKind> = [.instantAction, .formAction, .toggleAction]
        for feature in FeatureRegistry.all
        where actionKinds.contains(feature.kind) && FeatureEngine.implementedIDs.contains(feature.id) {
            let result = await engine.run(featureID: feature.id, serial: "S1", params: [:])
            #expect(
                !result.message.contains("isn't implemented yet"),
                "\(feature.id) is action-kind and in implementedIDs but has no dispatch case"
            )
        }
    }
}

@Suite struct FeatureRegistryTests {
    @Test func hasAll59Features() {
        #expect(FeatureRegistry.all.count == 59)
        #expect(FeatureRegistry.byID.count == 59)
    }

    @Test func everyFeatureSupportsAtLeastOnePlatform() {
        for feature in FeatureRegistry.all {
            #expect(!feature.platforms.isEmpty, "\(feature.id) supports no platform at all")
        }
    }

    @Test func iosOnlyActionsAreHubMembers() {
        // An iOS-only *action* standing alone in the (Android-first) catalog
        // would read as a dead button to Android users; actions join a hub
        // that adapts to the selected platform instead. Full-screen views
        // (ios-logs) may stand alone — they render their own switch-device
        // state when an Android device is selected.
        for feature in FeatureRegistry.all
        where !feature.platforms.contains(.android) && feature.kind != .view {
            #expect(
                FeatureRegistry.absorbedFeatureIDs.contains(feature.id),
                "\(feature.id) is an iOS-only action but not folded into a hub"
            )
        }
    }

    @Test func runAllIsTheCuratedFanOutSet() {
        let runAll = FeatureRegistry.runAllFeatureIDs
        #expect(!runAll.isEmpty)
        // The stored flag and the derived set never drift apart.
        for feature in FeatureRegistry.all {
            #expect(feature.supportsRunAll == runAll.contains(feature.id))
        }
        // Every run-all id is a real feature.
        for id in runAll {
            #expect(FeatureRegistry.byID[id] != nil, "run-all id \(id) not in registry")
        }
        // The curated product decision: the two hubs that dispatch fan-out
        // actions plus the two standalone fan-out features.
        #expect(runAll == ["simulate", "react-native", "send-text", "install-app"])
        // Single-device / interactive-session features must never be run-all —
        // their fan-out is meaningless or unimplemented.
        let singleDevice: Set<String> = [
            "scrcpy", "screen-record", "file-explorer", "sandbox-browser", "logcat",
            "crash-catcher", "performance", "network-speed", "device-info", "wifi",
            "private-dns", "root-status", "system-restrictions", "meminfo", "apps",
            "reactotron", "js-console", "emulators", "custom-commands", "frida-console",
            "apk-studio", "screenshot",
        ]
        #expect(runAll.isDisjoint(with: singleDevice))
    }

    @Test func everyCatalogFeatureIsEnabledByDefault() {
        // Every feature is on out of the box — the default set is exactly the
        // catalog (non-absorbed) features. Hub members are folded into their
        // hub and never appear as standalone default rows.
        #expect(Set(FeatureRegistry.defaultEnabledIDs) == Set(FeatureRegistry.catalogFeatureIDs))
        #expect(Set(FeatureRegistry.defaultEnabledIDs).isDisjoint(with: FeatureRegistry.absorbedFeatureIDs))
    }

    @Test func hubMembersAreHiddenFromCatalogButStayInRegistry() {
        let absorbed = FeatureRegistry.absorbedFeatureIDs
        #expect(!absorbed.isEmpty)
        // Hub members remain in the registry, so they stay hotkey-able and
        // reachable through their hub …
        for id in absorbed {
            #expect(FeatureRegistry.byID[id] != nil, "absorbed id \(id) missing from registry")
            #expect(FeatureRegistry.byID[id]?.isAbsorbedByHub == true)
        }
        // … but never appear in the catalog or the default sidebar.
        #expect(absorbed.isDisjoint(with: Set(FeatureRegistry.catalogFeatureIDs)))
        #expect(absorbed.isDisjoint(with: Set(FeatureRegistry.defaultEnabledIDs)))
        // The hub screens that gather them stay catalog-visible.
        for hub in FeatureRegistry.absorbedByHub.keys {
            #expect(FeatureRegistry.catalogFeatureIDs.contains(hub), "hub \(hub) should stay in the catalog")
            #expect(FeatureRegistry.byID[hub]?.isAbsorbedByHub == false)
        }
    }

    @Test func catalogIsTheRegistryMinusHubMembers() {
        #expect(
            FeatureRegistry.catalogFeatureIDs.count
                == FeatureRegistry.all.count - FeatureRegistry.absorbedFeatureIDs.count
        )
    }

    @Test func searchMatchesKeywordsAndTitle() {
        let logcat = FeatureRegistry.byID["logcat"]!
        #expect(logcat.matches("logs"))
        #expect(logcat.matches("LOGCAT"))
        #expect(!logcat.matches("battery"))
    }

    @Test func installParsesSuccessAndFailure() {
        let success = AppInstallService.parse(
            AdbResult(stdout: "Performing Streamed Install\nSuccess\n", stderr: "", exitCode: 0, timedOut: false))
        #expect(success.ok)

        let failure = AppInstallService.parse(AdbResult(
            stdout: "", stderr: "adb: failed to install app.apk: Failure [INSTALL_FAILED_INSUFFICIENT_STORAGE]",
            exitCode: 1, timedOut: false))
        #expect(!failure.ok)
        // parse now returns a plain-English reason; the raw code stays in copyText.
        #expect(failure.message == "Not enough storage on the device.")
        #expect(failure.copyText?.contains("INSTALL_FAILED_INSUFFICIENT_STORAGE") == true)
    }

    @Test func multiWordSearchMatchesNonContiguousTokens() {
        // "copy ip" must surface Copy Device IP even though "Device" sits between
        // the two words; it should outrank the Connection hub, whose subtitle
        // only mentions "Copy IP".
        let copyIP = FeatureRegistry.byID["get-ip"]!
        let connection = FeatureRegistry.byID["connection"]!
        #expect(copyIP.matches("copy ip"))
        #expect(copyIP.relevance(for: "copy ip") > connection.relevance(for: "copy ip"))
        // Every word still has to appear somewhere — gibberish doesn't match.
        #expect(!copyIP.matches("copy battery"))
    }

    @Test func hubsStaySearchableByTheirMembersPrimaryKeyword() {
        // Absorbed members no longer surface as standalone search results, so
        // each hub must carry its members' identity: searching a member's
        // primary keyword has to surface the hub, or that gathered feature
        // becomes undiscoverable.
        for (hubID, memberIDs) in FeatureRegistry.absorbedByHub {
            let hub = FeatureRegistry.byID[hubID]!
            for memberID in memberIDs {
                let member = FeatureRegistry.byID[memberID]!
                let primary = member.keywords.first ?? member.title
                #expect(
                    hub.matches(primary),
                    "hub \(hubID) should be searchable by \(memberID)'s keyword \"\(primary)\""
                )
            }
        }
    }

    @Test func layoutDefaultsExposeEnabledSet() {
        let layout = LayoutState()
        #expect(layout.effectiveEnabledIDs.contains("send-text"))
        #expect(layout.effectiveEnabledIDs.contains("custom-commands"))
        #expect(!layout.effectiveEnabledIDs.contains("fake-battery"))
    }

    @Test func everyRoleMapsValidFeatureIDsAndCoversTheCatalog() {
        for role in UserRole.allCases {
            for id in FeatureRegistry.featuresByRole[role] ?? [] {
                #expect(FeatureRegistry.byID[id] != nil, "role \(role.rawValue): unknown feature \(id)")
                #expect(
                    !(FeatureRegistry.byID[id]?.isAbsorbedByHub ?? false),
                    "role \(role.rawValue): \(id) is a hub member; reference its hub instead"
                )
            }
        }
        // Every non-system catalog feature must be reachable from some role, so
        // curation never orphans a feature. System features are always on
        // regardless of role, so they're exempt.
        let covered = Set(UserRole.allCases.flatMap { FeatureRegistry.featuresByRole[$0] ?? [] })
        let mustCover = Set(FeatureRegistry.catalogFeatureIDs)
            .subtracting(FeatureRegistry.systemFeatureIDs)
        #expect(mustCover.isSubset(of: covered), "uncovered catalog features: \(mustCover.subtracting(covered))")
    }

    @Test func reactNativeStackIDsAreRealNonAbsorbedFeatures() {
        for id in FeatureRegistry.reactNativeStackIDs {
            #expect(FeatureRegistry.byID[id] != nil, "unknown RN stack id \(id)")
            #expect(!FeatureRegistry.absorbedFeatureIDs.contains(id),
                    "\(id) is a hub member — reference the hub instead")
        }
    }

    @Test func seedRoleWithReactNativeStackLeadsWithTheStackTools() {
        var layout = LayoutState()
        layout.seedRole(.qaTester, includeReactNativeStack: true)
        let curated = FeatureRegistry.featureIDs(for: .qaTester)
        let expected = FeatureRegistry.reactNativeStackIDs + curated
        #expect(layout.enabledIds == expected)
        #expect(layout.sidebarOrder == expected)
        #expect(layout.effectiveEnabledIDs.contains("reactotron"))
        // The role-additions baseline stays the pure role list, so future
        // role-curation changes still reach this user.
        #expect(layout.seededRoleIds == curated)
        #expect(Set(layout.enabledIds ?? []).count == (layout.enabledIds ?? []).count)
    }

    @Test func seedRoleWithReactNativeStackIsANoOpForTheRNRole() {
        var layout = LayoutState()
        layout.seedRole(.reactNativeDeveloper, includeReactNativeStack: true)
        // The RN role already carries its stack — no duplicates, no reorder.
        #expect(layout.enabledIds == FeatureRegistry.featureIDs(for: .reactNativeDeveloper))
    }

    @Test func seedRoleSetsGroupOrderFromTheCuration() {
        var layout = LayoutState()
        layout.seedRole(.securityTester)
        // Security leads with APK Studio (App Management), so that group sorts
        // ahead of the fixed display order's earlier categories.
        let order = layout.categoryOrder ?? []
        #expect(order.first == FeatureCategory.appManagement.rawValue)
        // Every seeded category is a first-occurrence walk of the feature list.
        let expected = FeatureRegistry.categoryOrder(for: .securityTester)
        #expect(order == expected)
        // No duplicates.
        #expect(Set(order).count == order.count)
    }

    @Test func seedRoleCuratesEnabledSetAndOrder() {
        var layout = LayoutState()
        layout.seedRole(.qaTester)
        let curated = FeatureRegistry.featureIDs(for: .qaTester)
        #expect(layout.selectedRole == UserRole.qaTester.rawValue)
        #expect(layout.roleChosen == true)
        #expect(layout.enabledIds == curated)
        #expect(layout.sidebarOrder == curated)
        #expect(layout.effectiveEnabledIDs.isSuperset(of: Set(curated)))
        #expect(layout.effectiveEnabledIDs.contains("custom-commands"))  // system stays on
        #expect(!layout.effectiveEnabledIDs.contains("wifi"))            // curated out for QA
        // The legacy migrations must not re-expand a curated role back to all-on.
        #expect(layout.adoptAllEnabled() == false)
        #expect(layout.adoptNewDefaults() == false)
        #expect(layout.enabledIds == curated)
    }

    @Test func flatOrderPersistsIndependentlyOfGroupedOrder() throws {
        var layout = LayoutState()
        layout.sidebarOrder = ["a", "b", "c"]
        layout.flatOrder = ["c", "a", "b"]
        let decoded = try JSONDecoder().decode(LayoutState.self, from: JSONEncoder().encode(layout))
        #expect(decoded.sidebarOrder == ["a", "b", "c"])
        #expect(decoded.flatOrder == ["c", "a", "b"])
        // A fresh layout has no flat order, so the flat sidebar mirrors the
        // grouped order until the user reorders it.
        #expect(LayoutState().flatOrder == nil)
    }

    @Test func adoptNewRoleFeaturesEnablesFeaturesAddedToTheRole() {
        var layout = LayoutState()
        layout.seedRole(.androidDeveloper)
        // Simulate a layout seeded before "emulators" joined the Android role.
        layout.enabledIds?.removeAll { $0 == "emulators" }
        layout.seededRoleIds?.removeAll { $0 == "emulators" }
        #expect(layout.enabledIds?.contains("emulators") == false)

        #expect(layout.adoptNewRoleFeatures() == true)
        #expect(layout.enabledIds?.contains("emulators") == true)
        // Idempotent once the baseline catches up.
        #expect(layout.adoptNewRoleFeatures() == false)

        // "Everything" users aren't role-curated — no-op.
        var everything = LayoutState()
        everything.seedEverything()
        #expect(everything.adoptNewRoleFeatures() == false)
    }

    @Test func seedEverythingLeavesEverythingOn() {
        var layout = LayoutState()
        layout.seedRole(.qaTester)
        layout.seedEverything()
        #expect(layout.roleChosen == true)
        #expect(layout.selectedRole == nil)
        #expect(layout.enabledIds == nil)
        #expect(Set(FeatureRegistry.catalogFeatureIDs).isSubset(of: layout.effectiveEnabledIDs))
    }
}
