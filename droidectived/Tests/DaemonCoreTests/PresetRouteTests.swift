import ADBKit
import Foundation
import Testing

@testable import DaemonCore

/// The saved Send Text snippets.
///
/// The rules for what a snippet may be are `Presets`' own and are tested in
/// ADBKit; what is worth testing here is that the verb reaches them and that a
/// refusal is an answer rather than a silent no-op.
@Suite struct PresetRouteTests {
    /// A backend holding a real `Presets`, so the route's effect is the
    /// store's — a stub that recorded the verb would prove only that it
    /// arrived.
    private actor Store {
        private var presets = Presets()
        func snapshot() -> [SendTextSnippet] { presets.sendTextSnippets }
        func mutate(_ request: PresetProtocol.WriteRequest) -> [SendTextSnippet]? {
            switch request.op {
            case .add:
                guard presets.addSnippet(named: request.name, text: request.text ?? "") else {
                    return nil
                }
            case .remove: presets.removeSnippet(named: request.name)
            case .use: presets.recordSnippetUse(named: request.name)
            }
            return presets.sendTextSnippets
        }
    }

    private struct StubBackend: DaemonBackend {
        let store: Store
        func listDevices() async -> [Device] { [] }
        func snippets() async -> [SendTextSnippet] { await store.snapshot() }
        func writeSnippet(_ request: PresetProtocol.WriteRequest) async -> [SendTextSnippet]? {
            await store.mutate(request)
        }
        func expandSnippet(_ request: PresetProtocol.ExpandRequest) async -> (String, String?) {
            var values: [String: String] = ["ip": "192.168.1.5"]
            if let clipboard = request.clipboard { values["clipboard"] = clipboard }
            return (SnippetPlaceholders.expand(request.text, values: values), "192.168.1.5")
        }
    }

    private func write(_ json: String, _ backend: StubBackend) async -> DaemonProtocol.Answer {
        await PresetRoutes.write(body: Data(json.utf8), backend: backend)
    }

    private func decoded(_ body: Data) throws -> [SendTextSnippet] {
        try JSONDecoder().decode(PresetProtocol.SnippetsResponse.self, from: body).snippets
    }

    @Test func addsASnippetAndAnswersTheNewList() async throws {
        let backend = StubBackend(store: Store())
        let (status, body) = await write(
            #"{"op":"add","name":"Login","text":"user@example.com"}"#, backend)
        #expect(status == 200)
        let snippets = try decoded(body)
        #expect(snippets.map(\.name) == ["Login"])
        #expect(snippets.first?.text == "user@example.com")
    }

    @Test func refusesADuplicateNameRatherThanSilentlyDoingNothing() async throws {
        let backend = StubBackend(store: Store())
        _ = await write(#"{"op":"add","name":"Login","text":"a"}"#, backend)
        let (status, body) = await write(#"{"op":"add","name":"Login","text":"b"}"#, backend)
        // 409 with a message the screen can put beside the field: a no-op
        // would read as a button that does not work.
        #expect(status == 409)
        let error = try JSONDecoder().decode(DaemonProtocol.ErrorBody.self, from: body)
        #expect(error.error.code == "snippet_rejected")
    }

    @Test func refusesAnEmptyNameOrText() async throws {
        let backend = StubBackend(store: Store())
        #expect(await write(#"{"op":"add","name":"  ","text":"a"}"#, backend).status == 409)
        #expect(await write(#"{"op":"add","name":"Login","text":""}"#, backend).status == 409)
    }

    @Test func removesOne() async throws {
        let backend = StubBackend(store: Store())
        _ = await write(#"{"op":"add","name":"Login","text":"a"}"#, backend)
        let (status, body) = await write(#"{"op":"remove","name":"Login"}"#, backend)
        #expect(status == 200)
        #expect(try decoded(body).isEmpty)
    }

    @Test func recordingAUseBumpsTheCount() async throws {
        let backend = StubBackend(store: Store())
        _ = await write(#"{"op":"add","name":"Login","text":"a"}"#, backend)
        let (status, body) = await write(#"{"op":"use","name":"Login"}"#, backend)
        #expect(status == 200)
        #expect(try decoded(body).first?.uses == 1)
    }

    @Test func usingAMissingSnippetIsNotAnError() async throws {
        // The ranking is best-effort bookkeeping; a snippet removed in another
        // window must not turn an insert into a failure.
        let backend = StubBackend(store: Store())
        #expect(await write(#"{"op":"use","name":"Gone"}"#, backend).status == 200)
    }

    @Test func listsWhatIsStored() async throws {
        let backend = StubBackend(store: Store())
        _ = await write(#"{"op":"add","name":"Login","text":"a"}"#, backend)
        let (status, body) = await PresetRoutes.snippets(backend: backend)
        #expect(status == 200)
        #expect(try decoded(body).map(\.name) == ["Login"])
    }

    // MARK: - Expansion

    @Test func fillsInTheLiveValues() async throws {
        let backend = StubBackend(store: Store())
        let (status, body) = await PresetRoutes.expand(
            body: Data(#"{"text":"open http://{ip}:8081 as {clipboard}","clipboard":"me"}"#.utf8),
            backend: backend)
        #expect(status == 200)
        let answer = try JSONDecoder().decode(PresetProtocol.ExpandResponse.self, from: body)
        #expect(answer.text == "open http://192.168.1.5:8081 as me")
        #expect(answer.hostIp == "192.168.1.5")
    }

    @Test func leavesAnUnknownTokenAlone() async throws {
        let backend = StubBackend(store: Store())
        let (_, body) = await PresetRoutes.expand(
            body: Data(#"{"text":"{nope} and {ip}"}"#.utf8), backend: backend)
        let answer = try JSONDecoder().decode(PresetProtocol.ExpandResponse.self, from: body)
        #expect(answer.text == "{nope} and 192.168.1.5")
    }

    @Test func doesNotRescanASubstitutedValue() async throws {
        // `SnippetPlaceholders`' own rule: a clipboard holding "{ip}" is
        // inserted verbatim rather than expanding a second time.
        let backend = StubBackend(store: Store())
        let (_, body) = await PresetRoutes.expand(
            body: Data(#"{"text":"{clipboard}","clipboard":"{ip}"}"#.utf8), backend: backend)
        let answer = try JSONDecoder().decode(PresetProtocol.ExpandResponse.self, from: body)
        #expect(answer.text == "{ip}")
    }

    @Test func aBodyItCannotReadIsA400() async {
        let backend = StubBackend(store: Store())
        #expect(await write("not json", backend).status == 400)
        let (status, _) = await PresetRoutes.expand(body: Data("nope".utf8), backend: backend)
        #expect(status == 400)
    }
}
