import ADBKit
import Foundation
import Testing

@testable import DaemonCore

/// The API Testing routes without a socket.
///
/// Two things are worth guarding here, and they are what the client cannot
/// check for itself. The **workspace** is someone's own saved work, so a round
/// trip must not lose or rewrite a field. And the **send** answer is the one
/// place where a rich in-process value (`ApiResponse`, which carries `Data` and
/// header tuples) becomes JSON: which form the body travels in is the whole
/// decision, and getting it wrong shows up as an empty pane rather than an
/// error.
@Suite struct ApiClientRouteTests {
    private struct Refusal: Error, CustomStringConvertible {
        let description = "the disk said no"
    }

    private struct Unreachable: Error, LocalizedError {
        var errorDescription: String? { "Can't find example.test. Check the hostname or your DNS." }
    }

    private actor Saved {
        private(set) var data: ApiClientData
        init(_ data: ApiClientData) { self.data = data }
        func write(_ data: ApiClientData) { self.data = data }
    }

    private struct StubBackend: DaemonBackend {
        var saved: Saved = Saved(ApiClientData())
        var refusal: Refusal?
        var outcome: ApiSendOutcome?
        var sendFailure: (any Error)?
        var parsed: CurlImport?

        func apiWorkspace() async -> ApiClientData { await saved.data }

        func writeApiWorkspace(_ data: ApiClientData) async throws {
            if let refusal { throw refusal }
            await saved.write(data)
        }

        func sendApiRequest(
            _ request: ApiClientProtocol.SendRequest
        ) async throws -> ApiSendOutcome {
            if let sendFailure { throw sendFailure }
            guard let outcome else { throw Refusal() }
            return outcome
        }

        func apiCode(_ request: ApiClientProtocol.CodeRequest) async -> String {
            "generated \(request.target) for \(request.request.url)"
        }

        func parseCurl(_ text: String) async -> CurlImport? { parsed }
    }

    private func decode<T: Decodable>(_ answer: DaemonProtocol.Answer, as type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: answer.body)
    }

    private func encoded(_ value: some Encodable) throws -> Data {
        try DaemonProtocol.encode(value)
    }

    private func response(
        contentType: String, body: Data, status: Int = 200
    ) -> ApiResponse {
        ApiResponse(
            statusCode: status,
            headers: [(key: "Content-Type", value: contentType)],
            body: body,
            elapsedMs: 12,
            finalURL: "https://example.test/thing")
    }

    private func outcome(
        _ response: ApiResponse, warnings: [String] = [], sentBytes: Int = 0
    ) -> ApiSendOutcome {
        ApiSendOutcome(
            response: response,
            prepared: PreparedRequest(
                url: "https://example.test/thing", method: .get, headers: [],
                body: sentBytes > 0 ? Data(repeating: 0x61, count: sentBytes) : nil),
            warnings: warnings)
    }

    // MARK: - Workspace

    @Test func readAnswersTheSavedWorkspace() async throws {
        let stored = ApiClientData(
            collections: [ApiCollection(id: "c1", name: "Checkout")],
            environments: [ApiEnvironment(id: "e1", name: "Staging")],
            activeEnvironmentId: "e1")
        let backend = StubBackend(saved: Saved(stored))

        let answer = await ApiClientRoutes.read(backend: backend)
        #expect(answer.status == 200)

        let body = try decode(answer, as: ApiClientProtocol.ReadResponse.self)
        #expect(body.data.collections.map(\.name) == ["Checkout"])
        #expect(body.data.activeEnvironmentId == "e1")
    }

    /// The whole document survives the trip, nesting and timestamps included.
    /// A field silently dropped here is work that disappears at the next
    /// launch, which is exactly the failure the Mac's `persistFailure` strip
    /// exists to make visible.
    @Test func writeRoundTripsEveryField() async throws {
        let request = SavedRequest(
            id: "r1", name: "Create order", method: .post,
            url: "{{base}}/orders",
            headers: [ApiKeyValue(id: "h1", key: "X-Trace", value: "1", enabled: false)],
            body: RequestBodySpec(type: .json, jsonText: "{\"sku\":1}"),
            auth: AuthSpec(type: .bearer, bearerToken: "secret"),
            assertions: [ApiAssertion(id: "a1", target: .statusCode, op: .equals, expected: "201")],
            createdAt: 1_700_000_000, modifiedAt: 1_700_000_500)
        let document = ApiClientData(
            collections: [ApiCollection(
                id: "c1", name: "Orders",
                items: [.folder(ApiFolder(id: "f1", name: "Writes", items: [.request(request)]))],
                variables: [ApiKeyValue(id: "v1", key: "base", value: "https://example.test")],
                createdAt: 1_699_000_000)],
            globals: [ApiKeyValue(id: "g1", key: "token", value: "abc")])
        let backend = StubBackend()

        let answer = await ApiClientRoutes.write(
            body: try encoded(ApiClientProtocol.WriteRequest(data: document)), backend: backend)
        #expect(answer.status == 200)

        let stored = await backend.saved.data
        #expect(stored == document)
        // And the answer is the document, so the client can adopt what landed
        // rather than trusting its optimistic copy.
        let body = try decode(answer, as: ApiClientProtocol.ReadResponse.self)
        #expect(body.data == document)
    }

    @Test func writeRefusesABodyThatIsNotAWorkspace() async throws {
        let answer = await ApiClientRoutes.write(
            body: Data("{\"nope\":true}".utf8), backend: StubBackend())
        #expect(answer.status == 400)
    }

    @Test func aStoreThatWillNotWriteIsAFiveHundred() async throws {
        let backend = StubBackend(refusal: Refusal())
        let answer = await ApiClientRoutes.write(
            body: try encoded(ApiClientProtocol.WriteRequest(data: ApiClientData())),
            backend: backend)
        #expect(answer.status == 500)
        let body = try decode(answer, as: DaemonProtocol.ErrorBody.self)
        #expect(body.error.code == "store_failed")
    }

    // MARK: - Send

    /// A textual body travels as text — twice, because Raw and Pretty are two
    /// different strings and the pane offers both. What it must *not* do is
    /// also carry the same bytes as base64.
    @Test func aTextualBodyTravelsAsTextAndNotAsBytes() async throws {
        let backend = StubBackend(
            outcome: outcome(
                response(contentType: "application/json", body: Data("{\"a\":1}".utf8)),
                sentBytes: 7))
        let answer = await ApiClientRoutes.send(
            body: try encoded(ApiClientProtocol.SendRequest(request: SavedRequest())),
            backend: backend)
        #expect(answer.status == 200)

        let body = try decode(answer, as: ApiClientProtocol.SendResponse.self)
        #expect(body.bodyText == "{\"a\":1}")
        #expect(body.prettyBody?.contains("\n") == true)
        #expect(body.bodyBase64 == nil)
        #expect(body.bodyOmitted == false)
        #expect(body.format == "json")
        #expect(body.sentBytes == 7)
        #expect(body.preparedURL == "https://example.test/thing")
    }

    /// An image is the one case where the bytes themselves are the content, so
    /// they ride as base64 — without that the preview has nothing to draw.
    @Test func anImageTravelsAsBytes() async throws {
        let pixels = Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x01])
        let backend = StubBackend(
            outcome: outcome(response(contentType: "image/png", body: pixels)))
        let answer = await ApiClientRoutes.send(
            body: try encoded(ApiClientProtocol.SendRequest(request: SavedRequest())),
            backend: backend)

        let body = try decode(answer, as: ApiClientProtocol.SendResponse.self)
        #expect(body.format == "image")
        #expect(body.bodyBase64 == pixels.base64EncodedString())
        #expect(body.bodyText == nil)
        #expect(body.bodyOmitted == false)
    }

    /// Past the inline cap the bytes stay behind and the answer says so.
    /// Silently sending nothing would look like an empty response.
    @Test func anOversizedBinaryIsReportedRatherThanInlined() async throws {
        let big = Data(repeating: 0, count: ApiClientProtocol.maxInlineBodyBytes + 1)
        let backend = StubBackend(
            outcome: outcome(response(contentType: "application/zip", body: big)))
        let answer = await ApiClientRoutes.send(
            body: try encoded(ApiClientProtocol.SendRequest(request: SavedRequest())),
            backend: backend)

        let body = try decode(answer, as: ApiClientProtocol.SendResponse.self)
        #expect(body.bodyBase64 == nil)
        #expect(body.bodyOmitted)
        #expect(body.size == big.count)
    }

    @Test func headersCookiesAndAssertionsAllTravel() async throws {
        let response = ApiResponse(
            statusCode: 201,
            headers: [
                (key: "Content-Type", value: "application/json"),
                (key: "Set-Cookie", value: "sid=abc; Path=/; HttpOnly"),
            ],
            body: Data("{}".utf8),
            elapsedMs: 30)
        let backend = StubBackend(
            outcome: ApiSendOutcome(
                response: response,
                prepared: PreparedRequest(url: "https://example.test", method: .post, headers: []),
                assertions: [AssertionResult(
                    id: "a1", label: "Status code equals 200", passed: false, detail: "201")],
                warnings: ["Body on a GET is unusual."]))

        let answer = await ApiClientRoutes.send(
            body: try encoded(ApiClientProtocol.SendRequest(request: SavedRequest())),
            backend: backend)
        let body = try decode(answer, as: ApiClientProtocol.SendResponse.self)

        #expect(body.statusCode == 201)
        #expect(body.statusText == "Created")
        #expect(body.headers.map(\.key) == ["Content-Type", "Set-Cookie"])
        #expect(body.cookies.map(\.name) == ["sid"])
        #expect(body.cookies.first?.httpOnly == true)
        #expect(body.assertions.first?.passed == false)
        #expect(body.warnings == ["Body on a GET is unusual."])
    }

    /// A transport that never reached a response is the pane's *error* state,
    /// not a 200 with a status of zero — the same line `AdbClient` draws
    /// between "the device said no" and "adb could not run".
    @Test func aFailedSendCarriesTheTransportsOwnReason() async throws {
        let backend = StubBackend(sendFailure: Unreachable())
        let answer = await ApiClientRoutes.send(
            body: try encoded(ApiClientProtocol.SendRequest(request: SavedRequest())),
            backend: backend)
        #expect(answer.status == 502)

        let body = try decode(answer, as: DaemonProtocol.ErrorBody.self)
        #expect(body.error.code == "send_failed")
        #expect(body.error.message.contains("example.test"))
    }

    @Test func aCancelledSendSaysSoRatherThanFailing() async throws {
        let backend = StubBackend(sendFailure: CancellationError())
        let answer = await ApiClientRoutes.send(
            body: try encoded(ApiClientProtocol.SendRequest(request: SavedRequest())),
            backend: backend)
        let body = try decode(answer, as: DaemonProtocol.ErrorBody.self)
        #expect(body.error.code == "cancelled")
    }

    // MARK: - Cancel

    /// Cancel has to actually stop the request, not just stop showing it: the
    /// Mac's button tears the URLSession task down, and a button here that let
    /// a 60-second request run on would be a different button wearing the same
    /// label.
    @Test func cancellingAnInFlightSendStopsIt() async throws {
        let registry = InFlightSends()
        let started = AsyncStream<Void>.makeStream()
        let task = Task<ApiSendOutcome, any Error> {
            started.continuation.yield()
            started.continuation.finish()
            try await Task.sleep(for: .seconds(60))
            throw Refusal()
        }
        await registry.register("s1", task: task)
        for await _ in started.stream { break }

        #expect(await registry.cancel("s1"))
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(task.isCancelled)
    }

    /// A send that finished a moment before Cancel was pressed is the ordinary
    /// race. Reporting it as a failure would put a red banner over a response
    /// that arrived correctly.
    @Test func cancellingSomethingAlreadyFinishedIsNotAFailure() async throws {
        let registry = InFlightSends()
        #expect(await registry.cancel("gone") == false)

        let answer = await ApiClientRoutes.cancel(
            body: try encoded(ApiClientProtocol.CancelRequest(sendId: "gone")),
            backend: StubBackend())
        #expect(answer.status == 200)
        let body = try decode(answer, as: ApiClientProtocol.CancelResponse.self)
        #expect(body.cancelled == false)
    }

    /// The registry empties as sends finish, so a daemon left running all day
    /// does not accumulate an entry per request ever made.
    @Test func aFinishedSendLeavesTheRegistry() async throws {
        let registry = InFlightSends()
        let task = Task<ApiSendOutcome, any Error> { throw Refusal() }
        await registry.register("s1", task: task)
        await registry.finished("s1")
        #expect(await registry.cancel("s1") == false)
        _ = try? await task.value
    }

    @Test func cancelRefusesAnEmptyId() async throws {
        let answer = await ApiClientRoutes.cancel(
            body: try encoded(ApiClientProtocol.CancelRequest(sendId: "")),
            backend: StubBackend())
        #expect(answer.status == 400)
    }

    // MARK: - Code

    @Test func codePassesTheTargetThrough() async throws {
        let answer = await ApiClientRoutes.code(
            body: try encoded(ApiClientProtocol.CodeRequest(
                request: SavedRequest(url: "https://example.test"), target: "httpie")),
            backend: StubBackend())
        #expect(answer.status == 200)
        let body = try decode(answer, as: ApiClientProtocol.CodeResponse.self)
        #expect(body.code == "generated httpie for https://example.test")
    }

    /// An unknown target is refused rather than quietly generating cURL, which
    /// would read as a picker that does nothing.
    @Test func anUnknownCodeTargetIsRefused() async throws {
        let answer = await ApiClientRoutes.code(
            body: try encoded(ApiClientProtocol.CodeRequest(
                request: SavedRequest(), target: "cobol")),
            backend: StubBackend())
        #expect(answer.status == 400)
        let body = try decode(answer, as: DaemonProtocol.ErrorBody.self)
        #expect(body.error.code == "unknown_target")
    }

    // MARK: - cURL

    @Test func curlAnswersTheParsedRequestAndItsWarnings() async throws {
        let parsed = CurlImport(
            request: SavedRequest(name: "example.test", method: .post, url: "https://example.test"),
            warnings: ["--compressed was ignored."])
        let answer = await ApiClientRoutes.curl(
            body: try encoded(ApiClientProtocol.CurlRequest(text: "curl https://example.test")),
            backend: StubBackend(parsed: parsed))
        #expect(answer.status == 200)

        let body = try decode(answer, as: ApiClientProtocol.CurlResponse.self)
        #expect(body.request.method == .post)
        #expect(body.warnings == ["--compressed was ignored."])
    }

    /// Text that is not a cURL command is a 422 with the sheet's own wording,
    /// not a 500: nothing broke, the input was not what was asked for.
    @Test func textThatIsNotCurlIsRefusedWithTheSheetsWording() async throws {
        let answer = await ApiClientRoutes.curl(
            body: try encoded(ApiClientProtocol.CurlRequest(text: "wget https://example.test")),
            backend: StubBackend())
        #expect(answer.status == 422)
        let body = try decode(answer, as: DaemonProtocol.ErrorBody.self)
        #expect(body.error.code == "not_curl")
    }

    // MARK: - Import and export, against the real formats

    /// The live backend, not a stub: importing is the one route whose whole job
    /// is a file on disk, and a stub would test nothing but the plumbing.
    private func liveBackend() -> LiveBackend {
        let locator = ToolLocator()
        let client = AdbClient(locator: locator)
        let monitor = DeviceMonitor(client: client)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("api-routes-\(UUID().uuidString)")
        return LiveBackend(
            monitor: monitor,
            engine: FeatureEngine(
                client: client, locator: locator, monitor: monitor,
                overridesStore: JSONStore<OverridesMap>(
                    filename: "overrides.json", default: [:], directory: directory),
                toolsDirectory: directory),
            client: client,
            emulators: EmulatorService(client: client, locator: locator),
            locator: locator,
            deepLinks: JSONStore<DeepLinksMap>(
                filename: "deep-links.json", default: [:], directory: directory),
            customCommands: JSONStore<[CustomCommand]>(
                filename: "custom-commands.json", default: [], directory: directory),
            apiClient: JSONStore<ApiClientData>(
                filename: "api-client.json", default: ApiClientData(), directory: directory),
            toolsDirectory: directory)
    }

    private func writeTemporary(_ text: String) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("postman-\(UUID().uuidString).json")
        try Data(text.utf8).write(to: url)
        return url.path
    }

    /// Importing the same file twice must not produce two collections that
    /// share every id — the second import would then overwrite the first
    /// everywhere the tree looks something up by id.
    @Test func importGivesEveryItemAFreshId() async throws {
        let path = try writeTemporary("""
            {"info":{"name":"Orders","schema":"https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},
             "item":[{"name":"List","request":{"method":"GET","url":"https://example.test/orders"}}]}
            """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let backend = liveBackend()

        let first = try await backend.importApiFile(path: path)
        let second = try await backend.importApiFile(path: path)

        #expect(first.collections.first?.name == "Orders")
        #expect(first.collections.first?.id != second.collections.first?.id)
        let firstRequest = ApiCollectionTree.allRequests(in: first.collections[0].items).first
        let secondRequest = ApiCollectionTree.allRequests(in: second.collections[0].items).first
        #expect(firstRequest?.url == "https://example.test/orders")
        #expect(firstRequest?.id != secondRequest?.id)
    }

    @Test func aFileThatIsNotAPostmanExportIsRefused() async throws {
        let path = try writeTemporary("{\"hello\":\"world\"}")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let answer = await ApiClientRoutes.importFile(
            body: try encoded(ApiClientProtocol.ImportRequest(path: path)),
            backend: liveBackend())
        #expect(answer.status == 422)
        let body = try decode(answer, as: DaemonProtocol.ErrorBody.self)
        #expect(body.error.code == "import_failed")
    }

    /// Each export names its own file, because the three land in the same
    /// folder and `export.json` three times would overwrite the last one.
    @Test func eachExportKindSuggestsItsOwnName() async throws {
        let backend = liveBackend()

        let collection = try await backend.exportApi(ApiClientProtocol.ExportRequest(
            payload: .collection(ApiCollection(name: "Orders"))))
        #expect(collection.suggestedName == "Orders.postman_collection.json")
        #expect(collection.json.contains("\"Orders\""))

        let environment = try await backend.exportApi(ApiClientProtocol.ExportRequest(
            payload: .environment(ApiEnvironment(name: "Staging"))))
        #expect(environment.suggestedName == "Staging.postman_environment.json")

        let workspace = try await backend.exportApi(ApiClientProtocol.ExportRequest(
            payload: .workspace(ApiClientData())))
        #expect(workspace.suggestedName == "droidective-api.json")
    }

    /// The secrets switch has to reach the formatter: an export shared with a
    /// colleague that still carries a bearer token is the failure this guards.
    @Test func secretsLeaveAnExportUnlessTheyWereAskedFor() async throws {
        let backend = liveBackend()
        let collection = ApiCollection(
            name: "Orders",
            items: [.request(SavedRequest(
                name: "List", url: "https://example.test",
                auth: AuthSpec(type: .bearer, bearerToken: "super-secret")))])

        let hidden = try await backend.exportApi(
            ApiClientProtocol.ExportRequest(payload: .collection(collection)))
        #expect(!hidden.json.contains("super-secret"))

        let shown = try await backend.exportApi(ApiClientProtocol.ExportRequest(
            payload: .collection(collection), includeSecrets: true))
        #expect(shown.json.contains("super-secret"))
    }

    /// The workspace on disk is the Mac's own `api-client.json`, so a developer
    /// running both apps has one set of collections rather than two.
    @Test func theWorkspaceRoundTripsThroughTheRealStore() async throws {
        let backend = liveBackend()
        let document = ApiClientData(collections: [ApiCollection(id: "c1", name: "Orders")])

        try await backend.writeApiWorkspace(document)
        #expect(await backend.apiWorkspace() == document)
    }
}
