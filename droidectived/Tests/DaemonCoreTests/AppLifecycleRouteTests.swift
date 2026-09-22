import ADBKit
import Foundation
import Testing

@testable import DaemonCore

/// Disable, enable, remove-for-user and restore, without a socket.
///
/// Two things here are easy to get wrong and expensive when wrong. The request
/// carries two optional flags and exactly one must be set, or a body saying
/// both would run two writes and report one. And `pm` announces a refusal on
/// *stdout with exit code 0* about as often as it uses the exit code — so a
/// route that trusted the code alone would report "Done." for a package the
/// device declined to touch.
@Suite struct AppLifecycleRouteTests {
    private actor CallLog {
        private(set) var disabled: [(String, Bool)] = []
        private(set) var removed: [(String, Bool)] = []
        func recordDisabled(_ packageId: String, _ on: Bool) { disabled.append((packageId, on)) }
        func recordRemoved(_ packageId: String, _ on: Bool) { removed.append((packageId, on)) }
    }

    private struct Refusal: Error, CustomStringConvertible {
        let description = "device disconnected"
    }

    private struct StubBackend: DaemonBackend {
        let log = CallLog()
        var result = AdbResult(stdout: "", stderr: "", exitCode: 0, timedOut: false)
        var refusal: Refusal?

        func setAppDisabled(
            serial: String, packageId: String, _ disabled: Bool
        ) async throws -> AdbResult {
            if let refusal { throw refusal }
            await log.recordDisabled(packageId, disabled)
            return result
        }

        func setAppRemoved(
            serial: String, packageId: String, _ removed: Bool
        ) async throws -> AdbResult {
            if let refusal { throw refusal }
            await log.recordRemoved(packageId, removed)
            return result
        }
    }

    private func request(disabled: Bool?, removed: Bool?) -> Data {
        DaemonProtocol.encoded(AppProtocol.LifecycleRequest(
            serial: "S1", packageId: "com.example.app", disabled: disabled, removed: removed))
    }

    @Test func disablingGoesToTheDisableWrite() async throws {
        let backend = StubBackend()
        let answer = await AppRoutes.lifecycle(
            body: request(disabled: true, removed: nil), backend: backend)

        #expect(answer.status == 200)
        let calls = await backend.log.disabled
        #expect(calls.count == 1)
        #expect(calls.first?.0 == "com.example.app")
        #expect(calls.first?.1 == true)
        #expect(await backend.log.removed.isEmpty)
    }

    @Test func restoringGoesToTheRemoveWriteWithFalse() async throws {
        // Restore is `removed: false`, not a verb of its own: both directions
        // of both flags are reversible, which is why the wire is a flag.
        let backend = StubBackend()
        _ = await AppRoutes.lifecycle(body: request(disabled: nil, removed: false), backend: backend)

        let calls = await backend.log.removed
        #expect(calls.first?.1 == false)
        #expect(await backend.log.disabled.isEmpty)
    }

    @Test func aBodyNamingBothIsRefusedRatherThanRunTwice() async throws {
        let backend = StubBackend()
        let answer = await AppRoutes.lifecycle(
            body: request(disabled: true, removed: true), backend: backend)

        #expect(answer.status == 400)
        #expect(await backend.log.disabled.isEmpty)
        #expect(await backend.log.removed.isEmpty)
    }

    @Test func aBodyNamingNeitherIsRefusedRatherThanSilentlyDoingNothing() async throws {
        let answer = await AppRoutes.lifecycle(
            body: request(disabled: nil, removed: nil), backend: StubBackend())
        #expect(answer.status == 400)
    }

    @Test func aRefusalOnStdoutIsNotASuccess() async throws {
        // `pm uninstall --user 0` on a package that is not installed for this
        // user prints this and exits 0. Trusting the code would report it done.
        let answer = await AppRoutes.lifecycle(
            body: request(disabled: nil, removed: true),
            backend: StubBackend(result: AdbResult(
                stdout: "Failure [not installed for 0]", stderr: "",
                exitCode: 0, timedOut: false)))

        #expect(answer.status == 200)
        let response = try JSONDecoder().decode(ActionProtocol.RunResponse.self, from: answer.body)
        #expect(!response.ok)
        #expect(response.message == "Failure [not installed for 0]")
    }

    @Test func aSilentSuccessStillSaysSomething() async throws {
        // `pm enable` prints nothing at all when it works, and a blank toast
        // reads as a button that did not fire.
        let answer = await AppRoutes.lifecycle(
            body: request(disabled: false, removed: nil), backend: StubBackend())

        let response = try JSONDecoder().decode(ActionProtocol.RunResponse.self, from: answer.body)
        #expect(response.ok)
        #expect(response.message == "Done.")
    }

    @Test func adbGoingAwayIsTheDevicesFaultNotTheDaemons() async throws {
        let answer = await AppRoutes.lifecycle(
            body: request(disabled: true, removed: nil),
            backend: StubBackend(refusal: Refusal()))
        #expect(answer.status == 502)
    }

    @Test func aBodyThatIsNotOneAtAllIsARequestProblem() async throws {
        let answer = await AppRoutes.lifecycle(body: Data("{".utf8), backend: StubBackend())
        #expect(answer.status == 400)
    }

    @Test func aPackageWithNoLifecycleReadIsOrdinary() {
        // The list ships lifecycles for every package the device mentioned. One
        // it did not mention is installed and enabled, which is what every app
        // is until something changes it — not "disabled" by default.
        let listing = AppListing(packageId: "com.example.app", versionName: "1.0", isSystem: false)
        let summary = AppProtocol.AppSummary(listing, lifecycle: nil)
        #expect(!summary.disabled)
        #expect(!summary.removed)
    }

    @Test func theListCarriesWhatTheDeviceSaid() {
        let listing = AppListing(packageId: "com.example.app", versionName: "1.0", isSystem: true)
        let summary = AppProtocol.AppSummary(
            listing, lifecycle: AppLifecycle(disabled: false, removed: true))
        #expect(summary.removed)
        #expect(!summary.disabled)
    }
}
