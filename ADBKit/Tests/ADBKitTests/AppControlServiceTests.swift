import Testing
@testable import ADBKit

@Suite struct AppControlServiceTests {
    private func makeService(_ runner: MockProcessRunner) async -> AppControlService {
        AppControlService(client: await makeTestClient(runner: runner))
    }

    @Test func openStartsTheResolvedLauncherComponent() async throws {
        let runner = MockProcessRunner()
        runner.script(
            argsPrefix: ["-s", "S1", "shell", "cmd", "package", "resolve-activity"],
            stdout: "priority=0 preferredOrder=0 match=0x108000 specificIndex=-1 isDefault=false\ncom.app/com.app.MainActivity"
        )
        runner.script(argsPrefix: ["-s", "S1", "shell", "am", "start"], stdout: "Starting: Intent { … }")
        let service = await makeService(runner)

        let result = try await service.control(serial: "S1", packageId: "com.app", action: .open)
        #expect(result.ok)
        #expect(runner.invocations.map(\.arguments) == [
            [
                "-s", "S1", "shell", "cmd", "package", "resolve-activity", "--brief", "--user", "current",
                "-c", "android.intent.category.LAUNCHER", "'com.app'",
            ],
            ["-s", "S1", "shell", "am", "start", "-n", "'com.app/com.app.MainActivity'"],
        ])
    }

    @Test func openFallsBackToMonkeyWhenResolveFails() async throws {
        // Pre-7.1 devices have no `cmd package` — the old monkey path stays,
        // gated on the injected-events line (a stub monkey exits 0 injecting
        // nothing).
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1", "shell", "cmd"], stderr: "cmd: not found", exitCode: 127)
        runner.script(argsPrefix: ["-s", "S1", "shell", "monkey"], stdout: "Events injected: 1")
        let service = await makeService(runner)

        let result = try await service.control(serial: "S1", packageId: "com.app", action: .open)
        #expect(result.ok)
        #expect(runner.invocations.last?.arguments == [
            "-s", "S1", "shell", "monkey", "-p", "'com.app'", "-c", "android.intent.category.LAUNCHER", "1",
        ])
    }

    @Test func openRejectsAChooserComponentOutsideThePackage() async throws {
        // Two launcher activities resolve to the system chooser — starting
        // that would show a picker for the wrong package; fall to monkey.
        let runner = MockProcessRunner()
        runner.script(
            argsPrefix: ["-s", "S1", "shell", "cmd"],
            stdout: "android/com.android.internal.app.ResolverActivity"
        )
        runner.script(argsPrefix: ["-s", "S1", "shell", "monkey"], stdout: "Events injected: 1")
        let service = await makeService(runner)

        let result = try await service.control(serial: "S1", packageId: "com.app", action: .open)
        #expect(result.ok)
        #expect(runner.invocations.contains { $0.arguments.contains("monkey") })
        #expect(!runner.invocations.contains { $0.arguments.contains("'android/com.android.internal.app.ResolverActivity'") })
    }

    @Test func stubMonkeyFailureReportsWhetherThePackageIsInstalled() async throws {
        // The old code blamed "is it installed?" for every launch failure.
        // Now the failure says which it is: installed-but-unlaunchable vs
        // genuinely missing.
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1", "shell", "cmd"], stdout: "No activity found", exitCode: 1)
        runner.script(argsPrefix: ["-s", "S1", "shell", "monkey"], stdout: "** SYS_KEYS has no physical keys")
        runner.script(argsPrefix: ["-s", "S1", "shell", "pm", "list"], stdout: "package:com.app\npackage:other")
        let service = await makeService(runner)

        let installed = try await service.control(serial: "S1", packageId: "com.app", action: .open)
        #expect(!installed.ok)
        #expect(installed.message.contains("no enabled launcher activity"))

        let missing = try await service.control(serial: "S1", packageId: "com.gone", action: .open)
        #expect(!missing.ok)
        #expect(missing.message.contains("isn't installed"))
    }

    @Test func restartForceStopsThenLaunches() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1", "shell", "am", "force-stop"], stdout: "")
        runner.script(
            argsPrefix: ["-s", "S1", "shell", "cmd"],
            stdout: "com.app/com.app.MainActivity"
        )
        runner.script(argsPrefix: ["-s", "S1", "shell", "am", "start"], stdout: "Starting: Intent { … }")
        let service = await makeService(runner)

        let result = try await service.control(serial: "S1", packageId: "com.app", action: .restart)
        #expect(result.ok)
        #expect(result.message == "Restarted")
        #expect(runner.invocations.first?.arguments == ["-s", "S1", "shell", "am", "force-stop", "'com.app'"])
        #expect(runner.invocations.last?.arguments == [
            "-s", "S1", "shell", "am", "start", "-n", "'com.app/com.app.MainActivity'",
        ])
    }

    @Test func launcherComponentParsing() {
        // The component is the last line; leading resolve noise is skipped.
        #expect(AppControlService.launcherComponent(
            in: "priority=0 preferredOrder=0 match=0x108000\ncom.app/com.app.MainActivity\n",
            packageId: "com.app"
        ) == "com.app/com.app.MainActivity")
        // The chooser (outside the package) and no-match outputs give nil.
        #expect(AppControlService.launcherComponent(
            in: "android/com.android.internal.app.ResolverActivity", packageId: "com.app"
        ) == nil)
        #expect(AppControlService.launcherComponent(in: "No activity found", packageId: "com.app") == nil)
        // A package that prefixes another must not match its neighbor.
        #expect(AppControlService.launcherComponent(
            in: "com.app.pro/com.app.Main", packageId: "com.app"
        ) == nil)
    }

    @Test func forceStopQuotesPackageForTheDeviceShell() async throws {
        // A package id is free text in the bundle store; a metacharacter must be
        // quoted so `am force-stop` can't be turned into a second command.
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s"], stdout: "")
        let service = await makeService(runner)

        _ = try await service.control(serial: "S1", packageId: "com.app; reboot", action: .stop)
        #expect(runner.invocations.last?.arguments == [
            "-s", "S1", "shell", "am", "force-stop", "'com.app; reboot'",
        ])
    }

    @Test func clearDataQuotesPackageAndReadsSuccessText() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s"], stdout: "Success")
        let service = await makeService(runner)

        let result = try await service.control(serial: "S1", packageId: "a'b", action: .clearData)
        #expect(result.ok)
        #expect(runner.invocations.last?.arguments == [
            "-s", "S1", "shell", "pm", "clear", "'a'\\''b'",
        ])
    }

    @Test func clearDataReportsFailureWhenPmClearFailsWithExitZero() async throws {
        // `pm clear` prints "Failed" while exiting 0 — the text is authoritative.
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s"], stdout: "Failed")
        let service = await makeService(runner)

        let result = try await service.control(serial: "S1", packageId: "com.app", action: .clearData)
        #expect(!result.ok)
    }

    @Test func clearCacheUsesCacheOnlyAndQuotesPackage() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s"], stdout: "Success")
        let service = await makeService(runner)

        let result = try await service.control(serial: "S1", packageId: "a'b", action: .clearCache)
        #expect(result.ok)
        #expect(runner.invocations.last?.arguments == [
            "-s", "S1", "shell", "pm", "clear", "--cache-only", "'a'\\''b'",
        ])
    }

    @Test func clearCacheReportsFailureWhenNoSuccessText() async throws {
        // Older devices print nothing (no --cache-only support) and exit 0.
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s"], stdout: "")
        let service = await makeService(runner)

        let result = try await service.control(serial: "S1", packageId: "com.app", action: .clearCache)
        #expect(!result.ok)
    }

    @Test func openDetectsMissingLauncherActivity() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s"], stdout: "** No activities found to run, monkey aborted.")
        let service = await makeService(runner)

        let result = try await service.control(serial: "S1", packageId: "com.app", action: .open)
        #expect(!result.ok)
    }

    @Test func destructiveActionsAreFlagged() {
        #expect(AppControlService.AppAction.clearData.isDestructive)
        #expect(AppControlService.AppAction.uninstall.isDestructive)
        #expect(!AppControlService.AppAction.open.isDestructive)
        #expect(!AppControlService.AppAction.clearCache.isDestructive)
    }

    @Test func uninstallChecksForSuccessText() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1", "uninstall"], stdout: "Failure [DELETE_FAILED_INTERNAL_ERROR]")
        let service = await makeService(runner)

        let result = try await service.control(serial: "S1", packageId: "com.app", action: .uninstall)
        #expect(!result.ok)
    }

    @Test func listsThirdPartyPackagesSorted() async throws {
        let runner = MockProcessRunner()
        runner.script(
            argsPrefix: ["-s", "S1", "shell", "pm", "list", "packages", "-3"],
            stdout: "package:com.zebra\npackage:com.alpha\n\npackage:com.middle\n"
        )
        let service = await makeService(runner)

        let packages = try await service.listInstalledPackages(serial: "S1")
        #expect(packages == ["com.alpha", "com.middle", "com.zebra"])
    }

    @Test func listInstalledPackagesStripsCarriageReturns() async throws {
        // CRLF device-shell output must not leave a trailing \r on package ids,
        // or downstream force-stop/clear/uninstall silently fail to match.
        let runner = MockProcessRunner()
        runner.script(
            argsPrefix: ["-s", "S1", "shell", "pm", "list", "packages", "-3"],
            stdout: "package:com.zebra\r\npackage:com.alpha\r\n"
        )
        let service = await makeService(runner)

        let packages = try await service.listInstalledPackages(serial: "S1")
        #expect(packages == ["com.alpha", "com.zebra"])
        #expect(!packages.contains { $0.contains("\r") })
    }

    @Test func deepLinkLaunchDetectsActivityErrors() async throws {
        let runner = MockProcessRunner()
        runner.script(
            argsPrefix: ["-s"],
            stdout: "Error: Activity not started, unable to resolve Intent"
        )
        let service = await makeService(runner)

        let result = try await service.launchDeepLink(serial: "S1", url: "myapp://home")
        #expect(!result.ok)
    }
}
