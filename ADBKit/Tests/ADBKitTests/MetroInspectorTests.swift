import Foundation
import Testing
@testable import ADBKit

/// Parser tests for the Metro inspector `/json/list` payload across RN versions
/// — modern (with the `reactNative` metadata), legacy, the `vm:"don't use"`
/// placeholder, and the empty case.
@Suite struct MetroInspectorTests {
    @Test func parsesModernHermesTarget() {
        let json = """
        [{
          "id": "device1-page1",
          "title": "Hermes React Native",
          "appId": "com.acme.app.dev",
          "description": "com.acme.app.dev",
          "type": "node",
          "vm": "Hermes",
          "deviceName": "Pixel 7 - 14 - API 34",
          "webSocketDebuggerUrl": "ws://localhost:8081/inspector/debug?device=abc&page=1",
          "reactNative": { "logicalDeviceId": "abc-123", "capabilities": { "nativePageReloads": true } }
        }]
        """
        let targets = MetroInspector.parseTargets(Data(json.utf8))
        #expect(targets.count == 1)
        guard let target = targets.first else { Issue.record("no target parsed"); return }
        #expect(target.isHermes)
        #expect(target.appId == "com.acme.app.dev")
        #expect(target.deviceName == "Pixel 7 - 14 - API 34")
        #expect(target.webSocketDebuggerUrl == "ws://localhost:8081/inspector/debug?device=abc&page=1")
        #expect(target.logicalDeviceId == "abc-123")
    }

    @Test func dropsDontUsePlaceholderAndKeepsHermes() {
        // Older proxies list a real Hermes target plus a "don't use" placeholder.
        let json = """
        [
          { "id": "0-1", "title": "Don't use", "vm": "don't use",
            "webSocketDebuggerUrl": "ws://[::1]:8081/inspector/debug?device=0&page=1" },
          { "id": "0-2", "title": "Hermes React Native", "vm": "Hermes",
            "webSocketDebuggerUrl": "ws://[::1]:8081/inspector/debug?device=0&page=2" }
        ]
        """
        let targets = MetroInspector.parseTargets(Data(json.utf8))
        #expect(targets.count == 1)
        #expect(targets.first?.vm == "Hermes")
    }

    @Test func skipsEntriesWithoutADebuggerURL() {
        let json = """
        [{ "id": "x", "title": "no socket", "vm": "Hermes" }]
        """
        #expect(MetroInspector.parseTargets(Data(json.utf8)).isEmpty)
    }

    @Test func sortsHermesTargetsFirst() {
        let json = """
        [
          { "id": "a", "vm": "JavaScriptCore", "webSocketDebuggerUrl": "ws://h/a" },
          { "id": "b", "vm": "Hermes", "webSocketDebuggerUrl": "ws://h/b" }
        ]
        """
        let targets = MetroInspector.parseTargets(Data(json.utf8))
        #expect(targets.map(\.id) == ["b", "a"])
    }

    @Test func emptyArrayMeansNoTargets() {
        #expect(MetroInspector.parseTargets(Data("[]".utf8)).isEmpty)
    }

    @Test func malformedJSONYieldsNoTargets() {
        #expect(MetroInspector.parseTargets(Data("not json".utf8)).isEmpty)
        #expect(MetroInspector.parseTargets(Data("{}".utf8)).isEmpty)
    }

    // MARK: - Auto-connect candidate (the reconnect policy)

    private func target(
        id: String, vm: String? = "Hermes", appId: String? = nil, deviceId: String? = nil
    ) -> CDPTarget {
        CDPTarget(
            id: id, title: "RN", appId: appId, detail: "", deviceName: "Pixel",
            vm: vm, webSocketDebuggerUrl: "ws://127.0.0.1:8081/debug?page=\(id)",
            logicalDeviceId: deviceId
        )
    }

    @Test func candidatePrefersThePreviousLogicalDevice() {
        let targets = [
            target(id: "a", appId: "com.acme.one", deviceId: "dev-1"),
            target(id: "b", appId: "com.acme.two", deviceId: "dev-2"),
        ]
        let pick = MetroInspector.autoConnectCandidate(
            from: targets, preferredDeviceId: "dev-2", preferredAppId: "com.acme.one"
        )
        #expect(pick?.id == "b")
    }

    @Test func staleDeviceIdFallsBackToTheSameAppId() {
        // The proxy assigns a new logical device id when the app re-registers
        // (relaunch, phone sleep, Metro restart); the app id must still match
        // or the console never reconnects on its own again.
        let targets = [
            target(id: "a", appId: "com.acme.one", deviceId: "dev-9"),
            target(id: "b", appId: "com.acme.two", deviceId: "dev-8"),
        ]
        let pick = MetroInspector.autoConnectCandidate(
            from: targets, preferredDeviceId: "dev-gone", preferredAppId: "com.acme.two"
        )
        #expect(pick?.id == "b")
    }

    @Test func ambiguousAppIdStaysHandsOff() {
        let targets = [
            target(id: "a", appId: "com.acme.app", deviceId: "dev-1"),
            target(id: "b", appId: "com.acme.app", deviceId: "dev-2"),
        ]
        let pick = MetroInspector.autoConnectCandidate(
            from: targets, preferredDeviceId: "dev-gone", preferredAppId: "com.acme.app"
        )
        #expect(pick == nil)
    }

    @Test func staleDeviceIdStillReconnectsToALoneTarget() {
        let targets = [target(id: "a", appId: "com.acme.app", deviceId: "dev-new")]
        let pick = MetroInspector.autoConnectCandidate(
            from: targets, preferredDeviceId: "dev-gone", preferredAppId: nil
        )
        #expect(pick?.id == "a")
    }

    @Test func severalUnfamiliarTargetsAreNotAutoPicked() {
        let targets = [
            target(id: "a", appId: "com.one", deviceId: "dev-1"),
            target(id: "b", appId: "com.two", deviceId: "dev-2"),
        ]
        #expect(MetroInspector.autoConnectCandidate(
            from: targets, preferredDeviceId: nil, preferredAppId: nil
        ) == nil)
    }

    @Test func hermesTargetsShadowNonHermesOnes() {
        // A lone Hermes target wins even when a non-Hermes entry matches the
        // preferred app id — the console can only talk to Hermes anyway.
        let targets = [
            target(id: "a", vm: "JavaScriptCore", appId: "com.acme.app", deviceId: "dev-1"),
            target(id: "b", vm: "Hermes", appId: "com.acme.app", deviceId: "dev-2"),
        ]
        let pick = MetroInspector.autoConnectCandidate(
            from: targets, preferredDeviceId: nil, preferredAppId: "com.acme.app"
        )
        #expect(pick?.id == "b")
    }

    @Test func acceptsOnlyLoopbackWebSocketURLs() throws {
        for ok in [
            "ws://127.0.0.1:8081/inspector/debug?device=0&page=1",
            "ws://[::1]:8081/inspector/debug",
            "ws://localhost:8081/inspector/debug",
        ] {
            #expect(MetroInspector.isLocalDebuggerURL(try #require(URL(string: ok))), "should accept \(ok)")
        }
        for bad in [
            "ws://10.0.0.5:8081/inspector/debug", // off-host
            "wss://evil.example.com/inspector/debug", // remote
            "http://127.0.0.1:8081/inspector/debug", // wrong scheme
            "ws://127.0.0.1.evil.com/x", // look-alike host
        ] {
            #expect(!MetroInspector.isLocalDebuggerURL(try #require(URL(string: bad))), "should reject \(bad)")
        }
    }
}
