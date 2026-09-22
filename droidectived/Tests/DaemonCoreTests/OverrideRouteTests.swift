import ADBKit
import Foundation
import Testing

@testable import DaemonCore

/// Reading and clearing device-state overrides.
///
/// The one irreversible mistake on this route is resetting *everything* when
/// one kind was asked for, so an unrecognised kind is refused rather than
/// treated as "all" — pressing the button again cannot undo six overrides
/// nobody asked about.
@Suite struct OverrideRouteTests {
    private actor CallLog {
        private(set) var resets: [OverrideKind?] = []
        func record(_ kind: OverrideKind?) { resets.append(kind) }
    }

    private struct Refusal: Error, CustomStringConvertible {
        let description = "device disconnected"
    }

    private struct StubBackend: DaemonBackend {
        let log = CallLog()
        var overrides: [ADBKit.ActiveOverride] = []
        var refusal: Refusal?

        func activeOverrides(serial: String) async throws -> [ADBKit.ActiveOverride] {
            if let refusal { throw refusal }
            return overrides
        }

        func resetOverrides(serial: String, kind: OverrideKind?) async throws {
            if let refusal { throw refusal }
            await log.record(kind)
        }
    }

    private var serialBody: Data {
        DaemonProtocol.encoded(AppProtocol.ListRequest(serial: "S1"))
    }

    private func resetBody(kind: String?) -> Data {
        DaemonProtocol.encoded(OverrideProtocol.ResetRequest(serial: "S1", kind: kind))
    }

    @Test func activeCarriesTheLabelSoNoClientKeepsASecondCopy() async throws {
        let backend = StubBackend(overrides: [
            ADBKit.ActiveOverride(kind: .proxy, value: "10.0.0.2:8888", setAt: 1_700_000_000_000),
        ])
        let answer = await OverrideRoutes.active(body: serialBody, backend: backend)

        #expect(answer.status == 200)
        let response = try JSONDecoder().decode(
            OverrideProtocol.ActiveResponse.self, from: answer.body)
        #expect(response.overrides.count == 1)
        #expect(response.overrides.first?.kind == "proxy")
        #expect(response.overrides.first?.label == "HTTP Proxy")
        #expect(response.overrides.first?.value == "10.0.0.2:8888")
    }

    @Test func nothingOverriddenIsAnAnswerNotAFailure() async throws {
        let answer = await OverrideRoutes.active(body: serialBody, backend: StubBackend())
        #expect(answer.status == 200)

        let response = try JSONDecoder().decode(
            OverrideProtocol.ActiveResponse.self, from: answer.body)
        #expect(response.overrides.isEmpty)
    }

    @Test func noKindMeansAllOfThem() async throws {
        let backend = StubBackend()
        let answer = await OverrideRoutes.reset(body: resetBody(kind: nil), backend: backend)

        #expect(answer.status == 200)
        #expect(await backend.log.resets == [nil])
        let response = try JSONDecoder().decode(ActionProtocol.RunResponse.self, from: answer.body)
        #expect(response.message == "All overrides reset")
    }

    @Test func aNamedKindClearsOnlyThatOne() async throws {
        let backend = StubBackend()
        let answer = await OverrideRoutes.reset(body: resetBody(kind: "darkMode"), backend: backend)

        #expect(await backend.log.resets == [.darkMode])
        let response = try JSONDecoder().decode(ActionProtocol.RunResponse.self, from: answer.body)
        #expect(response.message == "Dark Mode reset")
    }

    @Test func anUnknownKindIsRefusedRatherThanTreatedAsAll() async throws {
        // Falling through to "all" here would clear six overrides nobody asked
        // about, and pressing the button again cannot put them back.
        let backend = StubBackend()
        let answer = await OverrideRoutes.reset(body: resetBody(kind: "brightness"), backend: backend)

        #expect(answer.status == 400)
        #expect(await backend.log.resets.isEmpty)
    }

    @Test func everyKindTheEnumHasIsAcceptedByName() async throws {
        // The raw values are the wire contract: a rename in ADBKit that did not
        // reach a client would look like an unknown override rather than a bug.
        for kind in OverrideKind.allCases {
            let backend = StubBackend()
            let answer = await OverrideRoutes.reset(
                body: resetBody(kind: kind.rawValue), backend: backend)
            #expect(answer.status == 200)
            #expect(await backend.log.resets == [kind])
        }
    }

    @Test func adbGoingAwayIsTheDevicesFaultNotTheDaemons() async throws {
        let backend = StubBackend(refusal: Refusal())
        #expect(await OverrideRoutes.active(body: serialBody, backend: backend).status == 502)
        #expect(await OverrideRoutes.reset(body: resetBody(kind: nil), backend: backend).status == 502)
    }

    @Test func aBodyThatIsNotOneAtAllIsARequestProblem() async {
        let broken = Data("{".utf8)
        #expect(await OverrideRoutes.active(body: broken, backend: StubBackend()).status == 400)
        #expect(await OverrideRoutes.reset(body: broken, backend: StubBackend()).status == 400)
    }
}
