import ADBKit
import Foundation
import Testing

@testable import DaemonCore

/// The per-app inspection routes without a socket.
///
/// Two answers here are *not* errors and must not be reported as ones: an app
/// that is not installed, and an app that `run-as` refuses because it is not
/// debuggable. Both are the normal state of a release build on a real device,
/// and the Mac explains each rather than showing a failure — so the wire has to
/// carry the distinction instead of collapsing it into a 502.
@Suite struct AppInspectionRouteTests {
    private struct Refusal: Error, CustomStringConvertible {
        let description: String
    }

    private actor CallLog {
        private(set) var permissionWrites: [(String, Bool)] = []
        private(set) var pulls: [String] = []
        func record(_ permission: String, _ grant: Bool) {
            permissionWrites.append((permission, grant))
        }
        func recordPull(_ destination: String) { pulls.append(destination) }
    }

    private struct StubBackend: DaemonBackend {
        let log = CallLog()
        var info = AppInfo(
            installed: true, versionName: "1.4.0", versionCode: "1400", targetSdk: "34",
            minSdk: "26", firstInstall: "2026-01-02", lastUpdate: "2026-06-01",
            apkPath: "/data/app/base.apk", apkSizeBytes: 12_345)
        var entries: [PermissionEntry] = []
        var memory = MemInfo(running: true, totalPssKb: 84_120, summary: [
            ("Java Heap", "20480"), ("Native Heap", "31000"), ("TOTAL", "84120"),
        ])
        var sandbox: [FsEntry] = []
        var debuggable = true
        var apkPaths: [String] = []
        var refusal: Refusal?

        func appInfo(serial: String, packageId: String) async throws -> AppInfo {
            if let refusal { throw refusal }
            return info
        }

        func permissions(serial: String, packageId: String) async throws -> [PermissionEntry] {
            if let refusal { throw refusal }
            return entries
        }

        func setPermission(
            serial: String, packageId: String, permission: String, grant: Bool
        ) async throws -> FeatureResult {
            if let refusal { throw refusal }
            await log.record(permission, grant)
            return FeatureResult(ok: true, message: grant ? "Granted" : "Revoked")
        }

        func meminfo(serial: String, packageId: String) async throws -> MemInfo {
            if let refusal { throw refusal }
            return memory
        }

        func sandboxList(
            serial: String, packageId: String, path: String
        ) async throws -> (entries: [FsEntry], debuggable: Bool) {
            if let refusal { throw refusal }
            return (sandbox, debuggable)
        }

        func sandboxPull(
            serial: String, packageId: String, path: String, to destination: String
        ) async throws -> String {
            if let refusal { throw refusal }
            await log.recordPull(destination)
            return destination
        }

        func pullApk(
            serial: String, packageId: String, to destination: String
        ) async throws -> [String] {
            if let refusal { throw refusal }
            return apkPaths.isEmpty ? [destination] : apkPaths
        }
    }

    private func body(_ value: some Encodable) -> Data { DaemonProtocol.encoded(value) }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    private var appBody: Data {
        body(AppInspectionProtocol.AppRequest(serial: "S1", packageId: "com.example.app"))
    }

    // MARK: - App info

    @Test func appInfoCarriesEveryFieldTheScreenShows() async throws {
        let answer = await AppInspectionRoutes.info(body: appBody, backend: StubBackend())
        #expect(answer.status == 200)

        let response = try decode(AppInspectionProtocol.InfoResponse.self, answer.body)
        #expect(response.installed)
        #expect(response.versionName == "1.4.0")
        #expect(response.versionCode == "1400")
        #expect(response.targetSdk == "34")
        #expect(response.minSdk == "26")
        #expect(response.apkSizeBytes == 12_345)
    }

    @Test func anAppThatIsNotInstalledIsAnAnswerNotAFailure() async throws {
        // The Mac renders a "Not installed" empty state for this. A 502 would
        // make it look as though the read broke.
        let answer = await AppInspectionRoutes.info(
            body: appBody, backend: StubBackend(info: .notInstalled))

        #expect(answer.status == 200)
        #expect(try !decode(AppInspectionProtocol.InfoResponse.self, answer.body).installed)
    }

    @Test func adbBeingUnreachableIsAFiveOhTwo() async {
        let answer = await AppInspectionRoutes.info(
            body: appBody, backend: StubBackend(refusal: Refusal(description: "offline")))
        #expect(answer.status == 502)
    }

    @Test func aBodyWithoutAPackageIsRefused() async {
        let answer = await AppInspectionRoutes.info(
            body: body(DaemonProtocol.DeviceRequest(serial: "S1")), backend: StubBackend())
        #expect(answer.status == 400)
    }

    // MARK: - Permissions

    @Test func aPermissionCarriesItsShortNameFromTheModel() async throws {
        // Both UIs show "CAMERA" over the full name; deriving it twice is how
        // they would eventually split it differently.
        let backend = StubBackend(entries: [
            PermissionEntry(name: "android.permission.CAMERA", granted: true),
        ])
        let answer = await AppInspectionRoutes.permissions(body: appBody, backend: backend)

        let response = try decode(AppInspectionProtocol.PermissionsResponse.self, answer.body)
        #expect(response.permissions.first?.shortName == "CAMERA")
        #expect(response.permissions.first?.name == "android.permission.CAMERA")
        #expect(response.permissions.first?.granted == true)
    }

    @Test func anAppWithNoRuntimePermissionsIsAnEmptyListNotAnError() async throws {
        let answer = await AppInspectionRoutes.permissions(body: appBody, backend: StubBackend())
        #expect(answer.status == 200)
        #expect(try decode(
            AppInspectionProtocol.PermissionsResponse.self, answer.body).permissions.isEmpty)
    }

    @Test func grantAndRevokeBothReachTheService() async throws {
        for grant in [true, false] {
            let backend = StubBackend()
            let answer = await AppInspectionRoutes.setPermission(
                body: body(AppInspectionProtocol.PermissionWriteRequest(
                    serial: "S1", packageId: "com.example.app",
                    permission: "android.permission.CAMERA", grant: grant)),
                backend: backend)

            #expect(answer.status == 200)
            let written = await backend.log.permissionWrites
            #expect(written.count == 1)
            #expect(written.first?.0 == "android.permission.CAMERA")
            #expect(written.first?.1 == grant)
        }
    }

    // MARK: - Memory

    @Test func meminfoKeepsDumpsysOwnRowOrder() async throws {
        // The summary is an array of pairs, not a dictionary: `dumpsys meminfo`
        // prints its rows in a meaningful order and a map would lose it.
        let answer = await AppInspectionRoutes.meminfo(body: appBody, backend: StubBackend())
        let response = try decode(AppInspectionProtocol.MemInfoResponse.self, answer.body)

        #expect(response.summary.map(\.key) == ["Java Heap", "Native Heap", "TOTAL"])
        #expect(response.totalPssKb == 84_120)
        #expect(response.running)
    }

    @Test func aStoppedAppReportsNotRunningRatherThanZeroes() async throws {
        let backend = StubBackend(memory: MemInfo(running: false, totalPssKb: nil, summary: []))
        let answer = await AppInspectionRoutes.meminfo(body: appBody, backend: backend)
        let response = try decode(AppInspectionProtocol.MemInfoResponse.self, answer.body)

        #expect(!response.running)
        #expect(response.totalPssKb == nil)
    }

    // MARK: - Sandbox

    @Test func aSandboxListingEchoesThePathItRead() async throws {
        let backend = StubBackend(sandbox: [
            FsEntry(name: "databases", isDir: true, size: 4096, perms: "drwxrwx--x"),
        ])
        let answer = await AppInspectionRoutes.sandboxList(
            body: body(AppInspectionProtocol.SandboxRequest(
                serial: "S1", packageId: "com.example.app", path: "/data/data/com.example.app")),
            backend: backend)

        let response = try decode(AppInspectionProtocol.SandboxResponse.self, answer.body)
        #expect(response.path == "/data/data/com.example.app")
        #expect(response.entries.first?.name == "databases")
        #expect(response.entries.first?.isDir == true)
    }

    @Test func aReleaseBuildIsNotDebuggableRatherThanBroken() async throws {
        // `run-as` refusing is the normal answer for a release build. It is a
        // 200 saying so, which is what lets the UI explain it.
        let backend = StubBackend(debuggable: false)
        let answer = await AppInspectionRoutes.sandboxList(
            body: body(AppInspectionProtocol.SandboxRequest(
                serial: "S1", packageId: "com.example.app", path: "/data/data/com.example.app")),
            backend: backend)

        #expect(answer.status == 200)
        let response = try decode(AppInspectionProtocol.SandboxResponse.self, answer.body)
        #expect(!response.debuggable)
        #expect(response.entries.isEmpty)
    }

    @Test func aSandboxPullAnswersWhereTheFileLanded() async throws {
        let backend = StubBackend()
        let answer = await AppInspectionRoutes.sandboxPull(
            body: body(AppInspectionProtocol.PullRequest(
                serial: "S1", packageId: "com.example.app",
                path: "/data/data/com.example.app/databases/app.db",
                destination: "/tmp/app.db")),
            backend: backend)

        #expect(answer.status == 200)
        #expect(try decode(AppInspectionProtocol.PullResponse.self, answer.body).paths
            == ["/tmp/app.db"])
        #expect(await backend.log.pulls == ["/tmp/app.db"])
    }

    @Test func aSandboxPullWithoutAPathIsRefused() async throws {
        // The APK pull shares this request shape and does not need a path, so
        // the sandbox route is where the requirement is enforced.
        let backend = StubBackend()
        let answer = await AppInspectionRoutes.sandboxPull(
            body: body(AppInspectionProtocol.PullRequest(
                serial: "S1", packageId: "com.example.app", destination: "/tmp/x")),
            backend: backend)

        #expect(answer.status == 400)
        #expect(await backend.log.pulls.isEmpty)
    }

    // MARK: - APK

    @Test func anApkPullAnswersEverySplitItSaved() async throws {
        // An App Bundle install lands several files, and the Mac's toast spells
        // out how many — so the count has to survive the wire.
        let backend = StubBackend(apkPaths: [
            "/tmp/base.apk", "/tmp/split_config.arm64_v8a.apk", "/tmp/split_config.en.apk",
        ])
        let answer = await AppInspectionRoutes.pullApk(
            body: body(AppInspectionProtocol.PullRequest(
                serial: "S1", packageId: "com.example.app", destination: "/tmp/base.apk")),
            backend: backend)

        #expect(answer.status == 200)
        #expect(try decode(AppInspectionProtocol.PullResponse.self, answer.body).paths.count == 3)
    }

    @Test func anApkPullThatFailsIsAFiveOhTwo() async {
        let answer = await AppInspectionRoutes.pullApk(
            body: body(AppInspectionProtocol.PullRequest(
                serial: "S1", packageId: "com.example.app", destination: "/tmp/base.apk")),
            backend: StubBackend(refusal: Refusal(description: "no such package")))
        #expect(answer.status == 502)
    }
}
