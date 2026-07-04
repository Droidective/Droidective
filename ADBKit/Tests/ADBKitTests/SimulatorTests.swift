import Foundation
import Testing
@testable import ADBKit

// MARK: - Parser

@Suite struct SimulatorListParserTests {
    private let sampleJSON = """
    {
      "devices" : {
        "com.apple.CoreSimulator.SimRuntime.iOS-18-2" : [
          {
            "udid" : "AAAA-1111",
            "name" : "iPhone 16 Pro",
            "state" : "Booted",
            "isAvailable" : true
          },
          {
            "udid" : "BBBB-2222",
            "name" : "iPad Air 11-inch (M2)",
            "state" : "Shutdown",
            "isAvailable" : true,
            "lastBootedAt" : "2026-06-30T09:15:00Z"
          }
        ],
        "com.apple.CoreSimulator.SimRuntime.iOS-17-5" : [
          {
            "udid" : "CCCC-3333",
            "name" : "iPhone 15",
            "state" : "Shutdown",
            "isAvailable" : false
          }
        ],
        "com.apple.CoreSimulator.SimRuntime.watchOS-11-0" : [
          {
            "udid" : "DDDD-4444",
            "name" : "Apple Watch Series 10 (46mm)",
            "state" : "Shutdown",
            "isAvailable" : true
          }
        ]
      }
    }
    """

    @Test func parsesAllRuntimesAndStates() {
        let sims = SimulatorListParser.parse(sampleJSON)
        #expect(sims.count == 4)
        let booted = sims.filter(\.isBooted)
        #expect(booted.map(\.udid) == ["AAAA-1111"])
        #expect(booted.first?.name == "iPhone 16 Pro")
        #expect(booted.first?.runtime == "iOS 18.2")
        #expect(sims.first { $0.udid == "CCCC-3333" }?.isAvailable == false)
    }

    @Test func sortsNewestRuntimeFirstThenByName() {
        let sims = SimulatorListParser.parse(sampleJSON)
        let runtimes = sims.map(\.runtime)
        #expect(runtimes.firstIndex(of: "iOS 18.2")! < runtimes.firstIndex(of: "iOS 17.5")!)
        let ios18 = sims.filter { $0.runtime == "iOS 18.2" }.map(\.name)
        #expect(ios18 == ios18.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }

    @Test func runtimeLabelHandlesPlatformsAndUnknownKeys() {
        #expect(SimulatorListParser.runtimeLabel("com.apple.CoreSimulator.SimRuntime.iOS-18-2") == "iOS 18.2")
        #expect(SimulatorListParser.runtimeLabel("com.apple.CoreSimulator.SimRuntime.watchOS-11-0") == "watchOS 11.0")
        #expect(SimulatorListParser.runtimeLabel("com.apple.CoreSimulator.SimRuntime.iOS-26-0-1") == "iOS 26.0.1")
        // Unrecognized shapes pass through instead of guessing.
        #expect(SimulatorListParser.runtimeLabel("something-weird") == "something-weird")
        #expect(SimulatorListParser.runtimeLabel("com.apple.Custom.NoVersion") == "com.apple.Custom.NoVersion")
    }

    @Test func malformedAndEmptyInputParseToNothing() {
        #expect(SimulatorListParser.parse("").isEmpty)
        #expect(SimulatorListParser.parse("not json at all").isEmpty)
        #expect(SimulatorListParser.parse(#"{"devices" : {}}"#).isEmpty)
    }

    @Test func bootedAvailableSimsBecomeReadyDevices() {
        let devices = SimulatorListParser.devices(from: SimulatorListParser.parse(sampleJSON))
        #expect(devices.count == 1)
        let device = devices[0]
        #expect(device.serial == "AAAA-1111")
        #expect(device.isReady)
        #expect(device.platform == .iosSimulator)
        #expect(device.label == "iPhone 16 Pro")
        #expect(device.product == "iOS 18.2")
        #expect(!device.isWireless)
    }

    @Test func unavailableBootedSimIsExcluded() {
        let sims = [Simulator(udid: "X", name: "Ghost", state: "Booted", runtime: "iOS 17.0", isAvailable: false)]
        #expect(SimulatorListParser.devices(from: sims).isEmpty)
    }

    @Test func parsesLastBootedAt() {
        let sims = SimulatorListParser.parse(sampleJSON)
        let ipad = sims.first { $0.udid == "BBBB-2222" }
        #expect(ipad?.lastBootedAt != nil)
        #expect(sims.first { $0.udid == "AAAA-1111" }?.lastBootedAt == nil)
    }

    private func sim(
        _ udid: String, state: String = "Shutdown", available: Bool = true, booted: Date? = nil
    ) -> Simulator {
        Simulator(
            udid: udid, name: udid, state: state, runtime: "iOS 18.3",
            isAvailable: available, lastBootedAt: booted
        )
    }

    @Test func quickPicksPreferRecentlyUsedAndSkipBootedOrBroken() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let sims = [
            sim("never-used"),
            sim("old", booted: now.addingTimeInterval(-86_400)),
            sim("recent", booted: now),
            sim("already-booted", state: "Booted", booted: now),
            sim("broken", available: false, booted: now),
        ]
        #expect(SimulatorListParser.quickPicks(sims).map(\.udid) == ["recent", "old"])
    }

    @Test func quickPicksFallBackToDefaultOrderOnAFreshInstall() {
        // No sim ever booted: show the head of the default list rather than
        // an empty menu section.
        let sims = (1...8).map { sim("sim-\($0)") }
        #expect(SimulatorListParser.quickPicks(sims).map(\.udid) == ["sim-1", "sim-2", "sim-3", "sim-4", "sim-5"])
    }

    @Test func quickPicksHonorTheLimit() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let sims = (1...8).map { sim("sim-\($0)", booted: now.addingTimeInterval(Double($0))) }
        let picks = SimulatorListParser.quickPicks(sims, limit: 3)
        #expect(picks.map(\.udid) == ["sim-8", "sim-7", "sim-6"])
    }
}

// MARK: - Client

@Suite struct SimctlClientTests {
    @Test func prefixesEveryCallWithSimctl() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: [], stdout: "ok")
        let client = SimctlClient(runner: runner, log: CommandLog(), xcrunPath: "/usr/bin/xcrun")
        let result = try await client.run(["list", "-j", "devices"])
        #expect(result.succeeded)
        #expect(runner.invocations == [
            .init(executable: "/usr/bin/xcrun", arguments: ["simctl", "list", "-j", "devices"])
        ])
    }

    @Test func missingXcrunThrowsTyped() async {
        let runner = MockProcessRunner()
        let client = SimctlClient(runner: runner, log: CommandLog(), xcrunPath: "/nonexistent/xcrun")
        await #expect(throws: SimctlError.xcrunNotFound) {
            _ = try await client.run(["list"])
        }
        #expect(runner.invocations.isEmpty)
    }

    @Test func failureWithSilentStderrGetsAFallbackMessage() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: [], exitCode: 1)
        let client = SimctlClient(runner: runner, log: CommandLog(), xcrunPath: "/usr/bin/xcrun")
        let result = try await client.run(["boot", "X"])
        #expect(!result.succeeded)
        #expect(result.stderr == "simctl command failed")
    }
}

// MARK: - Service

@Suite struct SimulatorServiceTests {
    private func makeService(_ runner: MockProcessRunner) -> SimulatorService {
        SimulatorService(client: SimctlClient(runner: runner, log: CommandLog(), xcrunPath: "/usr/bin/xcrun"))
    }

    @Test func bootBootsThenSurfacesTheSimulatorApp() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: [], stdout: "")
        let service = makeService(runner)
        let result = try await service.boot(udid: "UDID-1")
        #expect(result.ok)
        #expect(runner.invocations == [
            .init(executable: "/usr/bin/xcrun", arguments: ["simctl", "boot", "UDID-1"]),
            .init(executable: "/usr/bin/open", arguments: ["-a", "Simulator"]),
        ])
    }

    @Test func bootFailureSkipsOpeningTheApp() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: [], stderr: "Unable to boot device in current state: Booted", exitCode: 149)
        let service = makeService(runner)
        let result = try await service.boot(udid: "UDID-1")
        #expect(!result.ok)
        #expect(result.message == "Simulator is already booted.")
        #expect(runner.invocations.count == 1)
    }

    @Test func shutdownAndOpenURLIssueExactArguments() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: [], stdout: "")
        let service = makeService(runner)
        _ = try await service.shutdown(udid: "U")
        _ = try await service.openURL(udid: "U", url: "myapp://checkout?id=1")
        #expect(runner.invocations.map(\.arguments) == [
            ["simctl", "shutdown", "U"],
            ["simctl", "openurl", "U", "myapp://checkout?id=1"],
        ])
    }

    @Test func appearanceSetAndQuery() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: [], stdout: "")
        runner.script(argsPrefix: ["simctl", "ui", "U", "appearance"], stdout: "dark\n")
        let service = makeService(runner)
        _ = try await service.setAppearance(udid: "U", dark: true)
        // The set call matches the query prefix too, so assert the vectors.
        #expect(runner.invocations.first?.arguments == ["simctl", "ui", "U", "appearance", "dark"])
        let current = await service.currentAppearance(udid: "U")
        #expect(current == "dark")
    }

    @Test func statusBarOverriddenReadsTheListOutput() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: [], stdout: "")
        let service = makeService(runner)
        // Empty output = clean bar.
        #expect(await service.statusBarOverridden(udid: "U") == false)
        runner.script(argsPrefix: ["simctl", "status_bar"], stdout: "No overrides set\n")
        #expect(await service.statusBarOverridden(udid: "U") == false)
        runner.script(argsPrefix: ["simctl", "status_bar"], stdout: "Time: 9:41\nBatteryLevel: 100\n")
        #expect(await service.statusBarOverridden(udid: "U") == true)
    }

    @Test func activeOverridesReflectSimulatorState() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["simctl", "ui"], stdout: "dark\n")
        runner.script(argsPrefix: ["simctl", "status_bar"], stdout: "Time: 9:41\n")
        let service = makeService(runner)
        let active = await service.activeOverrides(udid: "U")
        #expect(active.map(\.kind) == [.darkMode, .demo])
    }

    @Test func resetMapsKindsToSimctlCommands() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: [], stdout: "")
        let service = makeService(runner)
        try await service.reset(udid: "U", kind: .darkMode)
        try await service.reset(udid: "U", kind: .demo)
        try await service.reset(udid: "U", kind: .battery)
        try await service.reset(udid: "U", kind: .proxy) // Android-only: no-op
        #expect(runner.invocations.map(\.arguments) == [
            ["simctl", "ui", "U", "appearance", "light"],
            ["simctl", "status_bar", "U", "clear"],
            ["simctl", "status_bar", "U", "clear"],
        ])
    }

    @Test func screenshotWritesToTheGivenDestination() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: [], stdout: "")
        let service = makeService(runner)
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("sim-test-\(UUID().uuidString).png")
        let file = try await service.screenshot(udid: "U", to: dest)
        #expect(file == dest)
        #expect(runner.invocations.map(\.arguments) == [
            ["simctl", "io", "U", "screenshot", dest.path]
        ])
    }

    @Test func screenshotFailureThrowsWithTheFriendlyMessage() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: [], stderr: "Invalid device: U", exitCode: 164)
        let service = makeService(runner)
        await #expect(throws: SimulatorServiceError.self) {
            _ = try await service.screenshot(
                udid: "U",
                to: FileManager.default.temporaryDirectory.appendingPathComponent("x.png")
            )
        }
    }

    @Test func apnsPayloadIsDeterministicJSON() throws {
        let payload = SimulatorService.apnsPayload(title: "Hi", body: "There", badge: 3)
        #expect(
            String(decoding: payload, as: UTF8.self)
                == #"{"aps":{"alert":{"body":"There","title":"Hi"},"badge":3,"sound":"default"}}"#
        )
        let noBadge = SimulatorService.apnsPayload(title: "Hi", body: "", badge: nil)
        #expect(
            String(decoding: noBadge, as: UTF8.self)
                == #"{"aps":{"alert":{"body":"","title":"Hi"},"sound":"default"}}"#
        )
    }

    @Test func pushStagesThePayloadThroughATempFile() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: [], stdout: "")
        let service = makeService(runner)
        let result = try await service.push(
            udid: "U", bundleId: "com.example.app",
            payload: SimulatorService.apnsPayload(title: "T", body: "B", badge: nil)
        )
        #expect(result.ok)
        let args = try #require(runner.invocations.first?.arguments)
        #expect(args.count == 5)
        #expect(Array(args.prefix(4)) == ["simctl", "push", "U", "com.example.app"])
        #expect(args[4].hasSuffix(".apns"))
        // The staged file is cleaned up after delivery.
        #expect(!FileManager.default.fileExists(atPath: args[4]))
    }
}

// MARK: - Engine dispatch

@Suite struct FeatureEngineIOSTests {
    private func makeEngine(_ runner: MockProcessRunner) async -> FeatureEngine {
        let client = await makeTestClient(runner: runner)
        return FeatureEngine(
            client: client, locator: client.locator, monitor: DeviceMonitor(client: client),
            overridesStore: makeTempOverridesStore(),
            toolsDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("tools-\(UUID().uuidString)")
        )
    }

    @Test func darkModeRoutesToSimctlForSimulators() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: [], stdout: "")
        let engine = await makeEngine(runner)
        let result = await engine.run(
            featureID: "dark-mode", serial: "UDID-9", platform: .iosSimulator, params: ["on": .bool(true)]
        )
        #expect(result.ok)
        #expect(runner.invocations.map(\.arguments) == [
            ["simctl", "ui", "UDID-9", "appearance", "dark"]
        ])
    }

    @Test func demoModeOverridesAndClearsTheStatusBar() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: [], stdout: "")
        let engine = await makeEngine(runner)
        _ = await engine.run(
            featureID: "demo-mode", serial: "U", platform: .iosSimulator, params: ["on": .bool(true)]
        )
        _ = await engine.run(
            featureID: "demo-mode", serial: "U", platform: .iosSimulator, params: ["on": .bool(false)]
        )
        #expect(runner.invocations.map(\.arguments) == [
            ["simctl", "status_bar", "U", "override"] + SimulatorService.demoStatusBarArguments,
            ["simctl", "status_bar", "U", "clear"],
        ])
    }

    @Test func fakeBatteryMapsToAStatusBarOverride() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: [], stdout: "")
        let engine = await makeEngine(runner)
        let result = await engine.run(
            featureID: "fake-battery", serial: "U", platform: .iosSimulator,
            params: ["level": .number(17), "unplugged": .bool(true)]
        )
        #expect(result.ok)
        #expect(runner.invocations.map(\.arguments) == [
            ["simctl", "status_bar", "U", "override", "--batteryState", "discharging", "--batteryLevel", "17"]
        ])
    }

    @Test func pushNotificationValidatesAndDelivers() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: [], stdout: "")
        let engine = await makeEngine(runner)
        let missing = await engine.run(
            featureID: "push-notification", serial: "U", platform: .iosSimulator, params: [:]
        )
        #expect(!missing.ok)
        #expect(missing.message.contains("bundle ID"))
        #expect(runner.invocations.isEmpty)

        let sent = await engine.run(
            featureID: "push-notification", serial: "U", platform: .iosSimulator,
            params: ["bundleId": .string("com.example.app"), "title": .string("T"), "body": .string("B")]
        )
        #expect(sent.ok)
        #expect(runner.invocations.first?.arguments.prefix(4) == ["simctl", "push", "U", "com.example.app"])
    }

    @Test func pushNotificationOnAndroidRedirectsToSimulators() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: [], stdout: "")
        let engine = await makeEngine(runner)
        let result = await engine.run(featureID: "push-notification", serial: "S1", params: [:])
        #expect(!result.ok)
        #expect(result.message.contains("iOS Simulator"))
        #expect(runner.invocations.isEmpty)
    }

    @Test func androidOnlyFeatureOnASimulatorExplainsItself() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: [], stdout: "")
        let engine = await makeEngine(runner)
        let result = await engine.run(
            featureID: "send-text", serial: "U", platform: .iosSimulator, params: ["text": .string("hi")]
        )
        #expect(!result.ok)
        #expect(result.message.contains("isn't available for iOS Simulators"))
        #expect(runner.invocations.isEmpty)
    }

    @Test func everyIOSCapableActionResolvesToASimctlRunner() async {
        // Mirror of everyImplementedActionResolvesToARunner for the simctl
        // path: an action id annotated .iosSimulator in the registry but
        // missing its dispatchIOS case would silently fall through to the
        // "isn't available" redirect.
        let runner = MockProcessRunner()
        runner.script(argsPrefix: [], stdout: "")
        let engine = await makeEngine(runner)
        // Keep the screenshot runner's capture-folder fallback out of the
        // user's real ~/Downloads.
        let defaults = UserDefaults.standard
        let priorFolder = defaults.string(forKey: ScreenCaptureService.captureFolderDefaultsKey)
        defaults.set(
            FileManager.default.temporaryDirectory
                .appendingPathComponent("captures-\(UUID().uuidString)").path,
            forKey: ScreenCaptureService.captureFolderDefaultsKey
        )
        defer { defaults.set(priorFolder, forKey: ScreenCaptureService.captureFolderDefaultsKey) }

        let actionKinds: Set<FeatureKind> = [.instantAction, .formAction, .toggleAction]
        for feature in FeatureRegistry.all
        where actionKinds.contains(feature.kind) && feature.platforms.contains(.iosSimulator) {
            let result = await engine.run(
                featureID: feature.id, serial: "UDID", platform: .iosSimulator, params: [:]
            )
            #expect(
                !result.message.contains("isn't available for iOS Simulators"),
                "\(feature.id) is annotated .iosSimulator but has no simctl runner"
            )
        }
    }
}
