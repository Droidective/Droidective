import ADBKit
import Foundation
import Testing

@testable import DaemonCore

/// The custom-command routes without a socket.
///
/// The list is someone's own saved work, so what matters here is that a
/// round trip does not quietly lose or rewrite any of it: the whole list goes
/// in, the whole list comes back, and the fields the client never sees — the
/// created timestamp above all — survive being carried across.
@Suite struct CustomCommandRouteTests {
    private struct Refusal: Error, CustomStringConvertible {
        let description = "the disk said no"
    }

    private actor Saved {
        private(set) var commands: [CustomCommand]
        private(set) var runs: [(id: String, serial: String, bundleId: String?)] = []

        init(_ commands: [CustomCommand]) { self.commands = commands }
        func write(_ commands: [CustomCommand]) { self.commands = commands }
        func record(_ id: String, _ serial: String, _ bundleId: String?) {
            runs.append((id, serial, bundleId))
        }
    }

    private struct StubBackend: DaemonBackend {
        let saved: Saved
        var refusal: Refusal?

        func customCommands() async -> [CustomCommand] { await saved.commands }

        func writeCustomCommands(_ commands: [CustomCommand]) async throws {
            if let refusal { throw refusal }
            await saved.write(commands)
        }

        func runCustomCommand(
            id: String, serial: String, bundleId: String?
        ) async -> FeatureResult? {
            guard await saved.commands.contains(where: { $0.id == id }) else { return nil }
            await saved.record(id, serial, bundleId)
            return FeatureResult(ok: true, message: "ran \(id)")
        }
    }

    private func sample(
        id: String = "one", name: String = "Restart app", pinned: Bool = false
    ) -> CustomCommand {
        CustomCommand(
            id: id, name: name, command: "shell am force-stop {bundleId}",
            kind: .adb, needsBundle: true, createdAt: 1_700_000_000, pinned: pinned)
    }

    private func decode<T: Decodable>(_ answer: DaemonProtocol.Answer, as type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: answer.body)
    }

    // MARK: - read

    @Test func readAnswersTheSavedList() async throws {
        let backend = StubBackend(saved: Saved([sample(), sample(id: "two", name: "Clear data")]))
        let answer = await CustomCommandRoutes.read(backend: backend)
        #expect(answer.status == 200)

        let body = try decode(answer, as: CustomCommandProtocol.ListResponse.self)
        #expect(body.commands.map(\.id) == ["one", "two"])
        #expect(body.commands.first?.name == "Restart app")
        #expect(body.commands.first?.needsBundle == true)
    }

    @Test func anEmptyStoreIsAnEmptyListRatherThanAFailure() async throws {
        let answer = await CustomCommandRoutes.read(backend: StubBackend(saved: Saved([])))
        #expect(answer.status == 200)
        #expect(try decode(answer, as: CustomCommandProtocol.ListResponse.self).commands.isEmpty)
    }

    // MARK: - write

    @Test func writeReplacesTheWholeList() async throws {
        // The whole list, not an add: the client holds what it is showing, and
        // a per-item verb would make the daemon re-derive it.
        let saved = Saved([sample(), sample(id: "two")])
        let request = CustomCommandProtocol.WriteRequest(
            commands: [CustomCommandProtocol.Command(sample(id: "three", name: "Only one left"))])
        let answer = await CustomCommandRoutes.write(
            body: try JSONEncoder().encode(request), backend: StubBackend(saved: saved))

        #expect(answer.status == 200)
        #expect(await saved.commands.map(\.id) == ["three"])
    }

    @Test func aRoundTripKeepsEveryFieldIncludingTheOnesTheClientNeverSets() async throws {
        // `createdAt` is the one worth naming: it is not editable in any UI, so
        // a DTO that dropped it would silently restamp everyone's list the
        // first time they saved.
        let original = CustomCommand(
            id: "keep", name: "Logcat", command: "logcat -d", kind: .shell,
            needsBundle: false, createdAt: 1_234.5, runsInTerminal: true,
            terminal: .defaultTerminal, pinned: true)
        let carried = CustomCommandProtocol.Command(original).model

        #expect(carried == original)
    }

    @Test func anUnknownKindFallsBackRatherThanLosingTheList() throws {
        // A newer client's word for a runner is not a reason to reject someone's
        // whole saved list.
        let json = Data(
            """
            {"id":"x","name":"n","command":"c","kind":"quantum","needsBundle":false,
             "runsInTerminal":false,"terminal":"holodeck","pinned":false,"createdAt":1}
            """.utf8)
        let decoded = try JSONDecoder().decode(CustomCommandProtocol.Command.self, from: json)
        #expect(decoded.model.kind == .adb)
        #expect(decoded.model.terminal == .droidective)
    }

    @Test func aMalformedWriteIsRefusedRatherThanClearingTheList() async throws {
        let saved = Saved([sample()])
        let answer = await CustomCommandRoutes.write(
            body: Data("not json".utf8), backend: StubBackend(saved: saved))

        #expect(answer.status == 400)
        // The point of the test: a body the daemon cannot read must not be
        // treated as "save an empty list".
        #expect(await saved.commands.map(\.id) == ["one"])
    }

    @Test func aStoreThatRefusesTheWriteSaysSo() async throws {
        let backend = StubBackend(saved: Saved([]), refusal: Refusal())
        let request = CustomCommandProtocol.WriteRequest(commands: [])
        let answer = await CustomCommandRoutes.write(
            body: try JSONEncoder().encode(request), backend: backend)

        #expect(answer.status == 500)
        let error = try decode(answer, as: DaemonProtocol.ErrorBody.self)
        #expect(error.error.code == "store_failed")
    }

    // MARK: - run

    @Test func runPassesTheTargetAndBundleThrough() async throws {
        let saved = Saved([sample()])
        let request = CustomCommandProtocol.RunRequest(
            id: "one", serial: "emulator-5554", bundleId: "com.example")
        let answer = await CustomCommandRoutes.run(
            body: try JSONEncoder().encode(request), backend: StubBackend(saved: saved))

        #expect(answer.status == 200)
        #expect(try decode(answer, as: ActionProtocol.RunResponse.self).ok)
        let run = await saved.runs.first
        #expect(run?.serial == "emulator-5554")
        #expect(run?.bundleId == "com.example")
    }

    @Test func runningACommandThatIsNotThereIsANotFound() async throws {
        // A 404 rather than a failed run: nothing was attempted, and a client
        // showing a stale list should be told which of the two happened.
        let request = CustomCommandProtocol.RunRequest(id: "ghost", serial: "emulator-5554")
        let answer = await CustomCommandRoutes.run(
            body: try JSONEncoder().encode(request), backend: StubBackend(saved: Saved([])))

        #expect(answer.status == 404)
        #expect(try decode(answer, as: DaemonProtocol.ErrorBody.self).error.code == "unknown_command")
    }

    @Test func runNeedsBothAnIdAndADevice() async throws {
        let backend = StubBackend(saved: Saved([sample()]))
        for request in [
            CustomCommandProtocol.RunRequest(id: "", serial: "emulator-5554"),
            CustomCommandProtocol.RunRequest(id: "one", serial: ""),
        ] {
            let answer = await CustomCommandRoutes.run(
                body: try JSONEncoder().encode(request), backend: backend)
            #expect(answer.status == 400)
        }
    }
}

/// The preset library, as the wire carries it.
///
/// Served rather than ported so the two apps cannot drift: a client with its
/// own copy of these fourteen would fall behind the Mac one preset at a time,
/// and nothing would fail while it did.
@Suite struct CustomCommandPresetTests {
    private struct EmptyBackend: DaemonBackend {
        func customCommands() async -> [CustomCommand] { [] }
    }

    @Test func readCarriesTheWholePresetLibrary() async throws {
        let answer = await CustomCommandRoutes.read(backend: EmptyBackend())
        let body = try JSONDecoder().decode(
            CustomCommandProtocol.ListResponse.self, from: answer.body)

        #expect(body.presets.count == CommandPreset.library.count)
        #expect(body.presets.map(\.name) == CommandPreset.library.map(\.name))
    }

    @Test func aPresetKeepsItsTemplateAndWhetherItNeedsAnApp() async throws {
        let answer = await CustomCommandRoutes.read(backend: EmptyBackend())
        let body = try JSONDecoder().decode(
            CustomCommandProtocol.ListResponse.self, from: answer.body)
        let forceStop = try #require(body.presets.first { $0.name == "Force-stop app" })

        // The `{bundleId}` placeholder and the flag that makes the client ask
        // for an app travel together, or the command runs against nothing.
        #expect(forceStop.command.contains("{bundleId}"))
        #expect(forceStop.needsBundle)
    }
}
