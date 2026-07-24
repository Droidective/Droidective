import Testing
@testable import ADBKit

@Suite struct DeveloperSettingsServiceTests {
    // MARK: - Table invariants

    @Test func toggleAndScaleIDsAreUnique() {
        let toggleIDs = DeveloperSettingsService.toggles.map(\.id)
        #expect(Set(toggleIDs).count == toggleIDs.count)
        let scaleIDs = DeveloperSettingsService.animationScales.map(\.id)
        #expect(Set(scaleIDs).count == scaleIDs.count)
    }

    @Test func everyToggleRoundTripsItsOwnValues() {
        // The panel keeps optimistic values on success, so what `set` writes
        // must read back as the same boolean (SystemRestrictionsView's rule).
        for toggle in DeveloperSettingsService.toggles {
            let (on, off): (String, String)
            switch toggle.backing {
            case .setting(_, _, let onValue, let offValue): (on, off) = (onValue, offValue)
            case .sysprop(let _, let onValue, let offValue): (on, off) = (onValue, offValue)
            }
            #expect(DeveloperSettingsService.isOn(on + "\n", toggle: toggle))
            #expect(!DeveloperSettingsService.isOn(off + "\n", toggle: toggle))
            // Never-set: `settings get` prints null, `getprop` an empty line.
            #expect(!DeveloperSettingsService.isOn("null\n", toggle: toggle))
            #expect(!DeveloperSettingsService.isOn("", toggle: toggle))
        }
    }

    // MARK: - Arg vectors

    @Test func settingToggleWritesTheNamespaceKeyAndValue() async throws {
        let runner = MockProcessRunner()
        let service = DeveloperSettingsService(client: await makeTestClient(runner: runner))
        let touches = try #require(DeveloperSettingsService.toggles.first { $0.id == "show-touches" })
        _ = try await service.set(touches, on: true, serial: "S1")
        #expect(runner.invocations.contains {
            $0.arguments == ["-s", "S1", "shell", "settings", "put", "system", "show_touches", "1"]
        })
    }

    @Test func syspropToggleWritesThenPokes() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1", "shell", "setprop"], stdout: "")
        runner.script(argsPrefix: ["-s", "S1", "shell", "service"], stdout: "Result: Parcel(...)")
        let service = DeveloperSettingsService(client: await makeTestClient(runner: runner))
        let bounds = try #require(DeveloperSettingsService.toggles.first { $0.id == "layout-bounds" })
        _ = try await service.set(bounds, on: true, serial: "S1")
        let args = runner.invocations.map(\.arguments)
        let setIndex = args.firstIndex(of: ["-s", "S1", "shell", "setprop", "debug.layout", "true"])
        let pokeIndex = args.firstIndex(of: ["-s", "S1", "shell", "service", "call", "activity", "1599295570"])
        #expect(setIndex != nil && pokeIndex != nil)
        if let setIndex, let pokeIndex { #expect(setIndex < pokeIndex) }
    }

    @Test func failedSyspropWriteSkipsThePoke() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1", "shell", "setprop"], stderr: "setprop: failed", exitCode: 1)
        let service = DeveloperSettingsService(client: await makeTestClient(runner: runner))
        let bounds = try #require(DeveloperSettingsService.toggles.first { $0.id == "layout-bounds" })
        let result = try await service.set(bounds, on: true, serial: "S1")
        #expect(!result.succeeded)
        #expect(!runner.invocations.contains { $0.arguments.contains("1599295570") })
    }

    @Test func scaleWriteUsesBareIntsForWholeNumbers() async throws {
        let runner = MockProcessRunner()
        let service = DeveloperSettingsService(client: await makeTestClient(runner: runner))
        let window = DeveloperSettingsService.animationScales[0]
        _ = try await service.setScale(window, value: 0.5, serial: "S1")
        _ = try await service.setScale(window, value: 10, serial: "S1")
        #expect(runner.invocations.contains {
            $0.arguments == ["-s", "S1", "shell", "settings", "put", "global", "window_animation_scale", "0.5"]
        })
        #expect(runner.invocations.contains {
            $0.arguments == ["-s", "S1", "shell", "settings", "put", "global", "window_animation_scale", "10"]
        })
    }

    // MARK: - Reads

    @Test func readTogglesParsesDeviceOutput() async throws {
        let runner = MockProcessRunner()
        runner.script(
            argsPrefix: ["-s", "S1", "shell", "settings", "get", "system", "show_touches"],
            stdout: "1\n")
        runner.script(
            argsPrefix: ["-s", "S1", "shell", "getprop", "debug.layout"],
            stdout: "true\n")
        let service = DeveloperSettingsService(client: await makeTestClient(runner: runner))
        let values = await service.readToggles(serial: "S1")
        #expect(values["show-touches"] == true)
        #expect(values["layout-bounds"] == true)
        // Unscripted keys return empty output — read as off, never crash.
        #expect(values["gpu-overdraw"] == false)
    }

    @Test func scaleParsingDefaultsNullToOne() {
        #expect(DeveloperSettingsService.parseScale("null\n") == 1.0)
        #expect(DeveloperSettingsService.parseScale("") == 1.0)
        #expect(DeveloperSettingsService.parseScale("0.5\n") == 0.5)
        #expect(DeveloperSettingsService.parseScale("10.0") == 10.0)
    }
}
