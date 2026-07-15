import Foundation
import Testing
@testable import ADBKit

@Suite struct AppInspectionArgTests {
    @Test func setPermissionQuotesPackageAndPermission() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s"], stdout: "")
        let service = AppInspectionService(client: await makeTestClient(runner: runner))

        _ = try await service.setPermission(
            serial: "S1", packageId: "com.app;x", permission: "android.permission.CAMERA", grant: true
        )
        #expect(runner.invocations.last?.arguments == [
            "-s", "S1", "shell", "pm", "grant", "'com.app;x'", "'android.permission.CAMERA'",
        ])
    }

    @Test func sandboxListQuotesPackageAndDir() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s"], stdout: "")
        let service = AppInspectionService(client: await makeTestClient(runner: runner))

        _ = try await service.sandboxList(serial: "S1", packageId: "com.app", dir: "/data/x y")
        #expect(runner.invocations.last?.arguments == [
            "-s", "S1", "shell", "run-as", "'com.app'", "ls", "-la", "'/data/x y'",
        ])
    }

    @Test func pullApkPullsEverySplitBaseFirst() async throws {
        let runner = MockProcessRunner()
        // pm path lists a split *before* base — the pull must still put
        // base.apk at the user's chosen destination.
        runner.script(argsPrefix: ["-s", "S1", "shell", "pm", "path"], stdout: """
        package:/data/app/~~a==/com.x-1/split_config.arm64_v8a.apk
        package:/data/app/~~a==/com.x-1/base.apk
        package:/data/app/~~a==/com.x-1/split_config.en.apk
        """)
        runner.script(argsPrefix: ["-s", "S1", "pull"], stdout: "1 file pulled")
        let service = AppInspectionService(client: await makeTestClient(runner: runner))
        let dest = URL(fileURLWithPath: "/tmp/out/com.x.apk")

        let saved = try await service.pullApk(serial: "S1", packageId: "com.x", to: dest)

        #expect(saved.map(\.path) == [
            "/tmp/out/com.x.apk",
            "/tmp/out/com.x.split_config.arm64_v8a.apk",
            "/tmp/out/com.x.split_config.en.apk",
        ])
        let pulls = runner.invocations.filter { $0.arguments.contains("pull") }.map(\.arguments)
        #expect(pulls == [
            ["-s", "S1", "pull", "/data/app/~~a==/com.x-1/base.apk", "/tmp/out/com.x.apk"],
            ["-s", "S1", "pull", "/data/app/~~a==/com.x-1/split_config.arm64_v8a.apk",
             "/tmp/out/com.x.split_config.arm64_v8a.apk"],
            ["-s", "S1", "pull", "/data/app/~~a==/com.x-1/split_config.en.apk",
             "/tmp/out/com.x.split_config.en.apk"],
        ])
    }

    @Test func pullApkSingleApkLandsExactlyAtTheChosenDestination() async throws {
        let runner = MockProcessRunner()
        runner.script(
            argsPrefix: ["-s", "S1", "shell", "pm", "path"],
            stdout: "package:/data/app/com.x-1/base.apk\n")
        runner.script(argsPrefix: ["-s", "S1", "pull"], stdout: "1 file pulled")
        let service = AppInspectionService(client: await makeTestClient(runner: runner))
        let dest = URL(fileURLWithPath: "/tmp/out/renamed.apk")

        let saved = try await service.pullApk(serial: "S1", packageId: "com.x", to: dest)

        #expect(saved.map(\.path) == ["/tmp/out/renamed.apk"])
        // The package reaches the device shell, so it must be quoted.
        #expect(runner.invocations.first?.arguments == ["-s", "S1", "shell", "pm", "path", "'com.x'"])
    }

    @Test func pullApkWithNoInstalledPathsThrowsApkNotFound() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1", "shell", "pm", "path"], stdout: "")
        let service = AppInspectionService(client: await makeTestClient(runner: runner))
        await #expect(throws: AppInspectionService.PullError.self) {
            _ = try await service.pullApk(
                serial: "S1", packageId: "com.gone", to: URL(fileURLWithPath: "/tmp/x.apk"))
        }
    }

    @Test func appInfoApkSizeSumsEverySplit() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1", "shell", "dumpsys"], stdout: """
        Package [com.x] (abc):
            versionName=1.0
            versionCode=7
        """)
        runner.script(argsPrefix: ["-s", "S1", "shell", "pm", "path"], stdout: """
        package:/a/base.apk
        package:/a/split_config.en.apk
        """)
        runner.script(argsPrefix: ["-s", "S1", "shell", "stat"], stdout: "100\n40\n")
        let service = AppInspectionService(client: await makeTestClient(runner: runner))

        let info = try await service.getAppInfo(serial: "S1", packageId: "com.x")

        #expect(info.apkPath == "/a/base.apk")
        #expect(info.apkSizeBytes == 140)
        let stat = runner.invocations.first { $0.arguments.contains("stat") }
        #expect(stat?.arguments == [
            "-s", "S1", "shell", "stat", "-c", "%s", "'/a/base.apk'", "'/a/split_config.en.apk'",
        ])
    }

    @Test func sandboxPullPassesRawArgvBecauseExecOutDoesNotUseAShell() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s"], stdout: "file bytes")
        let service = AppInspectionService(client: await makeTestClient(runner: runner))
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("sandbox-pull-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dest) }

        _ = try await service.sandboxPull(
            serial: "S1", packageId: "com.app", filePath: "/data/shared prefs/a.xml", to: dest
        )
        // `exec-out` execs argv directly on the device — quoting would send the
        // literal quotes to run-as/cat and fail. The space in the path is a
        // single argv element, so no escaping is needed or wanted.
        #expect(runner.invocations.last?.arguments == [
            "-s", "S1", "exec-out", "run-as", "com.app", "cat", "/data/shared prefs/a.xml",
        ])
    }
}

@Suite struct PermissionParsingTests {
    @Test func parsesRuntimePermissionBlock() {
        let dump = """
        Packages:
          Package [com.app] (abc):
            runtime permissions:
              android.permission.CAMERA: granted=true, flags=[ USER_SET]
              android.permission.RECORD_AUDIO: granted=false, flags=[ USER_SET]

            enabled components:
        """
        let permissions = AppInspectionService.parsePermissions(dump)
        #expect(permissions.count == 2)
        #expect(permissions[0].name == "android.permission.CAMERA")
        #expect(permissions[0].granted)
        #expect(permissions[0].shortName == "CAMERA")
        #expect(!permissions[1].granted)
    }

    @Test func noRuntimeBlockYieldsEmpty() {
        #expect(AppInspectionService.parsePermissions("Packages:\n  nothing here").isEmpty)
    }
}

@Suite struct AppInfoParsingTests {
    @Test func parsesVersionFields() {
        let dump = """
        Package [com.app] (1234):
            versionCode=421 minSdk=24 targetSdk=34
            versionName=2.4.1
            firstInstallTime=2024-01-15 10:00:00
            lastUpdateTime=2025-11-01 09:30:00
        """
        let info = AppInspectionService.parseAppInfo(dump, packageId: "com.app")
        #expect(info.installed)
        #expect(info.versionName == "2.4.1")
        #expect(info.versionCode == "421")
        #expect(info.targetSdk == "34")
        #expect(info.minSdk == "24")
        #expect(info.firstInstall == "2024-01-15 10:00:00")
    }

    @Test func missingPackageReportsNotInstalled() {
        let info = AppInspectionService.parseAppInfo("Unable to find package: com.app", packageId: "com.other")
        #expect(!info.installed)
    }
}

@Suite struct ForegroundActivityParsingTests {
    @Test func parsesResumedActivity() {
        let dump = """
          mResumedActivity: ActivityRecord{abc123 u0 com.myapp/.MainActivity t42}
        """
        #expect(AppInspectionService.parseResumedActivity(dump) == "com.myapp/.MainActivity")
    }

    @Test func parsesTopResumedVariant() {
        let dump = "topResumedActivity=ActivityRecord{def456 u0 com.other/com.other.ui.HomeActivity t7}"
        #expect(AppInspectionService.parseResumedActivity(dump) == "com.other/com.other.ui.HomeActivity")
    }

    @Test func missingActivityReturnsNil() {
        #expect(AppInspectionService.parseResumedActivity("nothing useful") == nil)
    }
}

@Suite struct MemInfoParsingTests {
    @Test func parsesTotalAndSummary() {
        let output = """
        Applications Memory Usage (in Kilobytes):
        ** MEMINFO in pid 1234 [com.app] **
                 Native Heap    25000
                 Dalvik Heap    18000
                       TOTAL    98765
        """
        let info = AppInspectionService.parseMemInfo(output)
        #expect(info.running)
        #expect(info.totalPssKb == 98765)
        #expect(info.summary.contains { $0.key == "Native Heap" && $0.value == "25000" })
    }

    @Test func noProcessMeansNotRunning() {
        let info = AppInspectionService.parseMemInfo("No process found for: com.app")
        #expect(!info.running)
        #expect(info.totalPssKb == nil)
    }
}

@Suite struct SandboxParsingTests {
    @Test func parsesLsOutputDirsFirst() {
        let output = """
        total 48
        drwxrws--x  5 u0_a123 u0_a123 4096 2025-06-01 10:00 .
        drwx------ 41 u0_a123 u0_a123 4096 2025-06-01 10:00 ..
        -rw-------  1 u0_a123 u0_a123  1234 2025-06-01 10:00 app.db
        drwxrws--x  2 u0_a123 u0_a123 4096 2025-06-01 10:00 shared_prefs
        -rw-------  1 u0_a123 u0_a123    99 2025-06-01 10:00 my file.txt
        """
        let entries = AppInspectionService.parseLsOutput(output)
        #expect(entries.map(\.name) == ["shared_prefs", "app.db", "my file.txt"])
        #expect(entries[0].isDir)
        #expect(entries[1].size == 1234)
    }

    @Test func detectsNotDebuggable() {
        #expect(AppInspectionService.isNotDebuggable("run-as: package not debuggable: com.app"))
        #expect(AppInspectionService.isNotDebuggable("run-as: Could not set capabilities: not an application"))
        #expect(!AppInspectionService.isNotDebuggable(""))
    }
}
