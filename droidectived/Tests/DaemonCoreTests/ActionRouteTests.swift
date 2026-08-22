import ADBKit
import Foundation
import Testing

@testable import DaemonCore

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The action and feature routes, over a real socket.
@Suite(.timeLimit(.minutes(1))) struct ActionRouteTests {
    private actor CallLog {
        private(set) var calls: [(id: String, serial: String, platform: DevicePlatform,
                                 params: [String: FeatureValue])] = []
        func record(
            _ id: String, _ serial: String, _ platform: DevicePlatform,
            _ params: [String: FeatureValue]
        ) {
            calls.append((id, serial, platform, params))
        }
        var count: Int { calls.count }
        var last: (id: String, serial: String, platform: DevicePlatform,
                   params: [String: FeatureValue])? { calls.last }

        private(set) var appCalls: [(serial: String, packageId: String,
                                     action: AppControlService.AppAction)] = []
        func recordApp(
            _ serial: String, _ packageId: String, _ action: AppControlService.AppAction
        ) {
            appCalls.append((serial, packageId, action))
        }
        var lastApp: (serial: String, packageId: String,
                      action: AppControlService.AppAction)? { appCalls.last }

        private(set) var listedSerials: [String] = []
        func recordList(_ serial: String) { listedSerials.append(serial) }
    }

    private struct RecordingBackend: DaemonBackend {
        let log: CallLog
        var result = FeatureResult(ok: true, message: "done")

        func runAction(
            featureID: String, serial: String, platform: DevicePlatform,
            params: [String: FeatureValue]
        ) async -> FeatureResult {
            await log.record(featureID, serial, platform, params)
            return result
        }

        func listApps(serial: String) async throws -> [AppListing] {
            await log.recordList(serial)
            return [
                AppListing(packageId: "com.example.weather", versionName: "2.1", isSystem: false),
                AppListing(packageId: "com.android.settings", versionName: nil, isSystem: true),
            ]
        }

        func controlApp(
            serial: String, packageId: String, action: AppControlService.AppAction
        ) async throws -> FeatureResult {
            await log.recordApp(serial, packageId, action)
            return result
        }

        func deviceProperties(serial: String) async throws -> [String: String] {
            ["ro.product.model": "Pixel", "ro.build.version.release": "14"]
        }

        // The filesystem surface has its own suite; these are here only so this
        // backend still conforms.

        func fileOperation(
            serial: String, _ operation: FileProtocol.Operation, asRoot: Bool
        ) async throws -> FeatureResult { result }

    }

    private func withServer(
        result: FeatureResult = FeatureResult(ok: true, message: "done"),
        _ body: (_ port: Int, _ token: String, _ log: CallLog) async throws -> Void
    ) async throws {
        let token = DaemonToken.generate()
        let log = CallLog()
        let server = DaemonServer(
            backend: RecordingBackend(log: log, result: result), token: token)
        let bound = try await server.start(port: 0)
        do { try await body(bound.port, token, log) } catch {
            await server.stop()
            throw error
        }
        await server.stop()
    }

    private func post(
        port: Int, path: String, token: String, json: String? = nil
    ) async throws -> (status: Int, body: String) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let json { request.httpBody = Data(json.utf8) }
        let (data, response) = try await URLSession.shared.data(for: request)
        return (
            (response as? HTTPURLResponse)?.statusCode ?? -1,
            String(decoding: data, as: UTF8.self)
        )
    }

    // MARK: features

    @Test func listsEveryRegistryFeature() async throws {
        try await withServer { port, token, _ in
            let (status, body) = try await post(
                port: port, path: "/v1/features/list", token: token)
            #expect(status == 200)
            let decoded = try JSONDecoder().decode(
                ActionProtocol.FeaturesResponse.self, from: Data(body.utf8))
            #expect(decoded.features.count == FeatureRegistry.all.count)
            // SF Symbol names mean nothing off Apple; shipping them would
            // invite a web UI to depend on something it cannot render.
            #expect(!body.contains("\"icon\""))
        }
    }

    @Test func marksWhichFeaturesActuallyHaveRunners() async throws {
        try await withServer { port, token, _ in
            let (_, body) = try await post(port: port, path: "/v1/features/list", token: token)
            let decoded = try JSONDecoder().decode(
                ActionProtocol.FeaturesResponse.self, from: Data(body.utf8))
            let implemented = Set(decoded.features.filter(\.implemented).map(\.id))
            #expect(implemented == FeatureEngine.implementedIDs)
        }
    }

    /// The palette's ranking lives in `FeatureDef.relevance`, which reads
    /// keywords. A client that never receives them can only match titles, so
    /// searching "battery" would stop finding the Simulate hub — the exact
    /// discoverability the hub design depends on.
    @Test func carriesTheSearchVocabularyTheRegistryRanksOn() async throws {
        try await withServer { port, token, _ in
            let summaries = try await self.features(port: port, token: token)
            let byID = Dictionary(uniqueKeysWithValues: summaries.map { ($0.id, $0) })
            for def in FeatureRegistry.all {
                #expect(byID[def.id]?.keywords == def.keywords, "keywords for \(def.id)")
            }
            let simulate = try #require(byID["simulate"])
            #expect(simulate.keywords.contains("battery"))
        }
    }

    /// Hub membership and destructiveness are registry facts a client cannot
    /// re-derive: one decides whether a feature is a standalone row, the other
    /// whether it gets a confirmation step.
    @Test func carriesHubMembershipAndDestructiveness() async throws {
        try await withServer { port, token, _ in
            let summaries = try await self.features(port: port, token: token)
            let absorbed = Set(summaries.filter(\.isAbsorbedByHub).map(\.id))
            #expect(absorbed == FeatureRegistry.absorbedFeatureIDs)

            let destructive = Set(summaries.filter(\.isDestructive).map(\.id))
            let expected = Set(FeatureRegistry.all.filter(\.isDestructive).map(\.id))
            #expect(destructive == expected)
            #expect(!destructive.isEmpty, "the registry has destructive actions to mark")
        }
    }

    /// A form is only renderable if the wire carries what each control needs:
    /// bounds for a slider, and both halves of every choice.
    @Test func carriesEnoughOfAFieldToRenderIt() async throws {
        try await withServer { port, token, _ in
            let summaries = try await self.features(port: port, token: token)
            let fields = summaries.flatMap(\.fields)

            let sliders = fields.filter { $0.control == "slider" }
            #expect(!sliders.isEmpty, "the registry has sliders to check")
            for slider in sliders {
                #expect(slider.min != nil && slider.max != nil, "bounds for \(slider.name)")
            }

            let locale = try #require(
                summaries.first { $0.id == "locale" }?.fields.first { $0.name == "locale" })
            let arabic = try #require(locale.options.first { $0.value == "ar-EG" })
            #expect(
                arabic.label != arabic.value,
                "the readable half of a choice must survive the wire")
        }
    }

    /// Every `toggleAction` is driven by one implicit boolean named `on` (see
    /// `FeatureEngine`, and `ToggleActionView` on the Mac). It is a convention
    /// rather than a declared field, so a client has to know it — and this is
    /// what fails if the engine ever renames it.
    @Test func aToggleActionIsDrivenByAnOnParameter() async throws {
        let toggles = FeatureRegistry.all.filter {
            $0.kind == .toggleAction && FeatureEngine.implementedIDs.contains($0.id)
        }
        #expect(!toggles.isEmpty, "the registry has toggle actions to check")
        try await withServer { port, token, log in
            for toggle in toggles {
                _ = try await self.post(
                    port: port, path: "/v1/actions/run", token: token,
                    json: #"{"featureId":"\#(toggle.id)","serial":"s","fields":{"on":true}}"#)
                let call = try #require(await log.last)
                #expect(call.id == toggle.id)
                #expect(call.params["on"] == .bool(true), "the on parameter for \(toggle.id)")
            }
        }
    }

    // MARK: apps

    @Test func listsInstalledAppsWithTheirDisplayNames() async throws {
        try await withServer { port, token, log in
            let (status, body) = try await self.post(
                port: port, path: "/v1/apps/list", token: token,
                json: #"{"serial":"emulator-5554"}"#)
            #expect(status == 200)
            let decoded = try JSONDecoder().decode(
                AppProtocol.ListResponse.self, from: Data(body.utf8))
            #expect(await log.listedSerials == ["emulator-5554"])
            #expect(decoded.apps.count == 2)

            let weather = try #require(decoded.apps.first)
            #expect(weather.packageId == "com.example.weather")
            #expect(weather.versionName == "2.1")
            #expect(!weather.isSystem)
            // The package-id -> title rule is a computed property on
            // `AppListing`, so it only survives the wire because the DTO sends
            // it; otherwise every client reimplements it and they drift.
            #expect(weather.displayName == "Weather")
            #expect(decoded.apps.last?.isSystem == true)
        }
    }

    @Test func runsAnAppVerbThroughTheService() async throws {
        try await withServer { port, token, log in
            let (status, body) = try await self.post(
                port: port, path: "/v1/apps/control", token: token,
                json: #"{"serial":"S1","packageId":"com.x","action":"clearData"}"#)
            #expect(status == 200)
            #expect(body.contains(#""ok":true"#))

            let call = try #require(await log.lastApp)
            #expect(call.serial == "S1")
            #expect(call.packageId == "com.x")
            #expect(call.action == .clearData)
        }
    }

    /// Every verb the daemon advertises has to be one it will actually accept,
    /// or a UI built from that list offers buttons that 400.
    @Test func acceptsEveryAdvertisedAppAction() async throws {
        try await withServer { port, token, log in
            #expect(!AppProtocol.actions.isEmpty)
            for action in AppProtocol.actions {
                let (status, _) = try await self.post(
                    port: port, path: "/v1/apps/control", token: token,
                    json: #"{"serial":"S1","packageId":"com.x","action":"\#(action.id)"}"#)
                #expect(status == 200, "action \(action.id)")
                #expect(await log.lastApp?.action.rawValue == action.id)
                #expect(
                    await log.lastApp?.action.isDestructive == action.isDestructive,
                    "the advertised destructive flag must be the runner's own")
            }
        }
    }

    @Test func rejectsAnUnknownAppActionWithoutTouchingTheDevice() async throws {
        try await withServer { port, token, log in
            let (status, body) = try await self.post(
                port: port, path: "/v1/apps/control", token: token,
                json: #"{"serial":"S1","packageId":"com.x","action":"detonate"}"#)
            #expect(status == 400)
            #expect(body.contains("unknown_action"))
            #expect(await log.lastApp == nil, "an unknown verb must not reach the device")
        }
    }

    private func features(
        port: Int, token: String
    ) async throws -> [ActionProtocol.FeatureSummary] {
        let (_, body) = try await post(port: port, path: "/v1/features/list", token: token)
        return try JSONDecoder()
            .decode(ActionProtocol.FeaturesResponse.self, from: Data(body.utf8)).features
    }

    // MARK: actions

    @Test func runsAnActionThroughTheEngineUntouched() async throws {
        // The daemon must add no feature knowledge: whatever the client sends
        // is what `FeatureEngine` receives.
        try await withServer { port, token, log in
            let (status, body) = try await post(
                port: port, path: "/v1/actions/run", token: token,
                json: #"""
                    {"featureId":"dark-mode","serial":"emulator-5554",
                     "fields":{"enabled":true,"count":3,"name":"x"}}
                    """#)
            #expect(status == 200)
            #expect(body.contains(#""ok":true"#))

            let call = try #require(await log.last)
            #expect(call.id == "dark-mode")
            #expect(call.serial == "emulator-5554")
            #expect(call.platform == .android, "platform defaults to android")
            // Bare JSON scalars decode to the right FeatureValue case; bool
            // must not be read as the number 1.
            #expect(call.params["enabled"] == .bool(true))
            #expect(call.params["count"] == .number(3))
            #expect(call.params["name"] == .string("x"))
        }
    }

    @Test func aFailedActionIsStillA200() async throws {
        // "The device said no" is not "the daemon broke" — collapsing them
        // into a 5xx would destroy the distinction AdbClient exists to keep.
        try await withServer(result: FeatureResult(ok: false, message: "device offline")) {
            port, token, _ in
            let (status, body) = try await post(
                port: port, path: "/v1/actions/run", token: token,
                json: #"{"featureId":"dark-mode","serial":"x"}"#)
            #expect(status == 200)
            #expect(body.contains(#""ok":false"#))
            #expect(body.contains("device offline"))
        }
    }

    @Test func carriesTheResultsExtras() async throws {
        try await withServer(
            result: FeatureResult(
                ok: true, message: "saved", copyText: "10.0.0.1",
                revealPath: "/tmp/shot.png", needsAdbKeyboard: true)
        ) { port, token, _ in
            let (_, body) = try await post(
                port: port, path: "/v1/actions/run", token: token,
                json: #"{"featureId":"dark-mode","serial":"x"}"#)
            // Decoded, not substring-matched: JSON escapes `/` as `\/`, so a
            // raw contains() on a path is a false negative waiting to happen.
            let decoded = try JSONDecoder().decode(
                ActionProtocol.RunResponse.self, from: Data(body.utf8))
            #expect(decoded.copyText == "10.0.0.1")
            #expect(decoded.revealPath == "/tmp/shot.png")
            #expect(decoded.needsAdbKeyboard)
        }
    }

    @Test func rejectsAnUnknownFeatureWithoutCallingTheEngine() async throws {
        try await withServer { port, token, log in
            let (status, body) = try await post(
                port: port, path: "/v1/actions/run", token: token,
                json: #"{"featureId":"no-such-feature","serial":"x"}"#)
            #expect(status == 404)
            #expect(body.contains("unknown_feature"))
            #expect(await log.count == 0, "an unknown id must not reach the engine")
        }
    }

    @Test func rejectsAnUnknownPlatform() async throws {
        try await withServer { port, token, log in
            let (status, body) = try await post(
                port: port, path: "/v1/actions/run", token: token,
                json: #"{"featureId":"dark-mode","serial":"x","platform":"windows-phone"}"#)
            #expect(status == 400)
            #expect(body.contains("unknown_platform"))
            #expect(await log.count == 0)
        }
    }

    @Test func acceptsTheIOSSimulatorPlatform() async throws {
        try await withServer { port, token, log in
            _ = try await post(
                port: port, path: "/v1/actions/run", token: token,
                json: #"{"featureId":"screenshot","serial":"UDID","platform":"iosSimulator"}"#)
            #expect(await log.last?.platform == .iosSimulator)
        }
    }

    @Test func rejectsAMalformedBody() async throws {
        try await withServer { port, token, log in
            let (status, body) = try await post(
                port: port, path: "/v1/actions/run", token: token, json: "{not json")
            #expect(status == 400)
            #expect(body.contains("bad_request"))
            #expect(await log.count == 0)
        }
    }

    @Test func actionsStillNeedTheToken() async throws {
        try await withServer { port, _, log in
            var request = URLRequest(
                url: URL(string: "http://127.0.0.1:\(port)/v1/actions/run")!)
            request.httpMethod = "POST"
            request.httpBody = Data(#"{"featureId":"dark-mode","serial":"x"}"#.utf8)
            let (_, response) = try await URLSession.shared.data(for: request)
            #expect((response as? HTTPURLResponse)?.statusCode == 401)
            #expect(await log.count == 0)
        }
    }
}
