import Foundation
import Testing

@testable import ADBKit

// MARK: - Collection tree

@Suite struct ApiCollectionTreeTests {

    private func sample() -> [ApiItem] {
        [
            .request(SavedRequest(id: "r1", name: "Top", url: "https://a.co/1")),
            .folder(
                ApiFolder(
                    id: "f1",
                    name: "Users",
                    items: [
                        .request(SavedRequest(id: "r2", name: "List", url: "https://a.co/users")),
                        .folder(
                            ApiFolder(
                                id: "f2",
                                name: "Admin",
                                items: [
                                    .request(SavedRequest(id: "r3", name: "Ban", url: "https://a.co/ban"))
                                ]
                            )
                        ),
                    ]
                )
            ),
        ]
    }

    @Test func findsItemsAtAnyDepth() {
        let items = sample()
        #expect(ApiCollectionTree.find("r1", in: items)?.name == "Top")
        #expect(ApiCollectionTree.find("r3", in: items)?.name == "Ban")
        #expect(ApiCollectionTree.find("f2", in: items)?.name == "Admin")
        #expect(ApiCollectionTree.find("nope", in: items) == nil)
        #expect(ApiCollectionTree.findRequest("f1", in: items) == nil)
    }

    @Test func listsRequestsInDisplayOrder() {
        #expect(ApiCollectionTree.allRequests(in: sample()).map(\.name) == ["Top", "List", "Ban"])
        #expect(ApiCollectionTree.requestCount(in: sample()) == 3)
    }

    @Test func reportsFolderPaths() {
        let items = sample()
        #expect(ApiCollectionTree.path(to: "r1", in: items) == [])
        #expect(ApiCollectionTree.path(to: "r2", in: items) == ["Users"])
        #expect(ApiCollectionTree.path(to: "r3", in: items) == ["Users", "Admin"])
        #expect(ApiCollectionTree.path(to: "missing", in: items) == nil)
    }

    @Test func replacesANestedRequest() throws {
        var updated = try #require(ApiCollectionTree.findRequest("r3", in: sample()))
        updated.name = "Renamed"
        let items = try #require(ApiCollectionTree.replacing(updated, in: sample()))
        #expect(ApiCollectionTree.findRequest("r3", in: items)?.name == "Renamed")
        #expect(ApiCollectionTree.requestCount(in: items) == 3)
    }

    @Test func replacingAnAbsentRequestReportsSoRatherThanAppending() {
        #expect(ApiCollectionTree.replacing(SavedRequest(id: "ghost"), in: sample()) == nil)
    }

    @Test func renamesAFolderKeepingItsChildren() {
        let items = ApiCollectionTree.renamingFolder("f2", to: "Moderators", in: sample())
        #expect(ApiCollectionTree.find("f2", in: items)?.name == "Moderators")
        #expect(ApiCollectionTree.findRequest("r3", in: items) != nil)
    }

    @Test func removesAtAnyDepth() {
        #expect(ApiCollectionTree.find("r3", in: ApiCollectionTree.removing("r3", from: sample())) == nil)
        let withoutFolder = ApiCollectionTree.removing("f1", from: sample())
        #expect(ApiCollectionTree.requestCount(in: withoutFolder) == 1)
    }

    @Test func appendsAtTheTopOrIntoAFolder() {
        let new = ApiItem.request(SavedRequest(id: "new", name: "New"))
        #expect(ApiCollectionTree.appending(new, toFolder: nil, in: sample()).count == 3)

        let intoFolder = ApiCollectionTree.appending(new, toFolder: "f2", in: sample())
        #expect(ApiCollectionTree.path(to: "new", in: intoFolder) == ["Users", "Admin"])
    }

    @Test func appendingIntoAnUnknownFolderChangesNothing() {
        let new = ApiItem.request(SavedRequest(id: "new"))
        let items = ApiCollectionTree.appending(new, toFolder: "ghost", in: sample())
        #expect(ApiCollectionTree.find("new", in: items) == nil)
        #expect(items.count == 2)
    }

    @Test func movesBetweenFoldersAndBackToTheTop() {
        let intoAdmin = ApiCollectionTree.moving("r1", toFolder: "f2", in: sample())
        #expect(ApiCollectionTree.path(to: "r1", in: intoAdmin) == ["Users", "Admin"])
        #expect(ApiCollectionTree.requestCount(in: intoAdmin) == 3)

        let backToTop = ApiCollectionTree.moving("r3", toFolder: nil, in: sample())
        #expect(ApiCollectionTree.path(to: "r3", in: backToTop) == [])
    }

    /// Moving a folder inside itself would detach the whole subtree.
    @Test func refusesToMoveAFolderIntoItselfOrItsOwnDescendant() {
        let items = sample()
        #expect(ApiCollectionTree.moving("f1", toFolder: "f1", in: items) == items)
        #expect(ApiCollectionTree.moving("f1", toFolder: "f2", in: items) == items)
    }

    @Test func movingAnUnknownItemChangesNothing() {
        let items = sample()
        #expect(ApiCollectionTree.moving("ghost", toFolder: "f1", in: items) == items)
    }

    @Test func duplicatingMintsFreshIdsThroughout() throws {
        let folder = try #require(ApiCollectionTree.find("f1", in: sample()))
        let copy = ApiCollectionTree.duplicating(folder)
        #expect(copy.id != folder.id)
        #expect(copy.name == "Users Copy")

        let originalIds = Set(ApiCollectionTree.allRequests(in: [folder]).map(\.id))
        let copyIds = Set(ApiCollectionTree.allRequests(in: [copy]).map(\.id))
        #expect(originalIds.isDisjoint(with: copyIds))
        #expect(copyIds.count == 2)
        // Only the top-level name gains the suffix.
        #expect(ApiCollectionTree.allRequests(in: [copy]).map(\.name) == ["List", "Ban"])
    }

    @Test func reidentifyingKeepsNamesAndReplacesEveryId() {
        let items = ApiCollectionTree.reidentifying(sample())
        #expect(ApiCollectionTree.allRequests(in: items).map(\.name) == ["Top", "List", "Ban"])
        #expect(ApiCollectionTree.find("r1", in: items) == nil)
        #expect(ApiCollectionTree.find("f1", in: items) == nil)
    }

    @Test func reidentifyingRefreshesRowIdsToo() throws {
        let items: [ApiItem] = [
            .request(
                SavedRequest(
                    id: "r",
                    headers: [ApiKeyValue(id: "h1", key: "A", value: "1")],
                    queryParams: [ApiKeyValue(id: "q1", key: "q", value: "1")]
                )
            )
        ]
        let request = try #require(ApiCollectionTree.allRequests(in: ApiCollectionTree.reidentifying(items)).first)
        #expect(request.headers.first?.id != "h1")
        #expect(request.queryParams.first?.id != "q1")
    }

    @Test func searchMatchesNameURLAndMethod() {
        let hits = ApiCollectionTree.search("ban", in: sample())
        #expect(hits.count == 1)
        #expect(hits[0].request.name == "Ban")
        #expect(hits[0].path == ["Users", "Admin"])

        #expect(ApiCollectionTree.search("a.co", in: sample()).count == 3)
        #expect(ApiCollectionTree.search("GET", in: sample()).count == 3)
        #expect(ApiCollectionTree.search("BAN", in: sample()).count == 1)
        #expect(ApiCollectionTree.search("", in: sample()).isEmpty)
        #expect(ApiCollectionTree.search("   ", in: sample()).isEmpty)
        #expect(ApiCollectionTree.search("zzz", in: sample()).isEmpty)
    }

    @Test func strippingSecretsReachesNestedRequests() throws {
        let items: [ApiItem] = [
            .folder(
                ApiFolder(
                    items: [
                        .request(
                            SavedRequest(
                                url: "https://a.co",
                                auth: AuthSpec(type: .bearer, bearerToken: "secret")
                            )
                        )
                    ]
                )
            )
        ]
        let stripped = ApiCollectionTree.withoutSecrets(items)
        let request = try #require(ApiCollectionTree.allRequests(in: stripped).first)
        #expect(request.auth.bearerToken.isEmpty)
    }
}

// MARK: - Secret handling

@Suite struct ApiSecretRedactionTests {

    private let request = SavedRequest(
        name: "r",
        url: "https://api.co/v1?token=in-url",
        headers: [
            ApiKeyValue(key: "Authorization", value: "Bearer abc"),
            ApiKeyValue(key: "X-Api-Key", value: "k123"),
            ApiKeyValue(key: "Cookie", value: "session=1"),
            ApiKeyValue(key: "Accept", value: "application/json"),
        ],
        auth: AuthSpec(
            type: .basic, basicUsername: "alice", basicPassword: "s3cret",
            apiKeyValue: "key", oauth2Token: "otok"
        )
    )

    @Test func blanksAuthSecretsButKeepsIdentifiers() {
        let safe = request.withoutSecrets()
        #expect(safe.auth.basicPassword.isEmpty)
        #expect(safe.auth.bearerToken.isEmpty)
        #expect(safe.auth.apiKeyValue.isEmpty)
        #expect(safe.auth.oauth2Token.isEmpty)
        #expect(safe.auth.basicUsername == "alice")
        #expect(safe.auth.type == .basic)
    }

    @Test func masksCredentialBearingHeadersAndLeavesOthers() {
        let safe = request.withoutSecrets()
        #expect(safe.headers.firstValue(forKeyIgnoringCase: "authorization") == "•••")
        #expect(safe.headers.firstValue(forKeyIgnoringCase: "x-api-key") == "•••")
        #expect(safe.headers.firstValue(forKeyIgnoringCase: "cookie") == "•••")
        #expect(safe.headers.firstValue(forKeyIgnoringCase: "accept") == "application/json")
        #expect(safe.headers.count == request.headers.count)
    }

    @Test func anEmptySecretHeaderStaysEmptyRatherThanShowingDots() {
        let safe = SavedRequest(
            url: "https://a.co", headers: [ApiKeyValue(key: "Authorization", value: "")]
        ).withoutSecrets()
        #expect(safe.headers.first?.value == "")
    }

    /// The URL is what makes a history row recognisable, so it is kept as-is.
    @Test func theURLIsNotRedacted() {
        #expect(request.withoutSecrets().url == "https://api.co/v1?token=in-url")
    }

    @Test func historyRedactsOnTheWayIn() {
        let entry = ApiHistoryEntry(method: .get, url: "https://api.co", request: request)
        #expect(entry.request.auth.basicPassword.isEmpty)
        #expect(entry.request.headers.firstValue(forKeyIgnoringCase: "authorization") == "•••")
    }

    @Test func reportsWhetherASecretIsPresent() {
        #expect(AuthSpec(type: .bearer, bearerToken: "t").hasSecret)
        #expect(AuthSpec(type: .basic, basicUsername: "u").hasSecret == false)
        #expect(AuthSpec().hasSecret == false)
    }
}

// MARK: - Persistence

@Suite struct ApiPersistenceTests {

    @Test func theWholeShapeRoundTrips() throws {
        var original = ApiClientData(
            collections: [
                ApiCollection(
                    name: "C",
                    items: [
                        .request(SavedRequest(name: "R", method: .post, url: "https://a.co")),
                        .folder(ApiFolder(name: "F", items: [.request(SavedRequest(name: "Nested"))])),
                    ],
                    variables: [ApiKeyValue(key: "k", value: "v")],
                    auth: AuthSpec(type: .bearer, bearerToken: "t")
                )
            ],
            environments: [ApiEnvironment(name: "E", variables: [ApiKeyValue(key: "a", value: "b")])],
            globals: [ApiKeyValue(key: "g", value: "1")]
        )
        original.activeEnvironmentId = original.environments.first?.id
        original.addToHistory(ApiHistoryEntry(method: .get, url: "https://a.co", request: SavedRequest()))

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ApiClientData.self, from: data)
        #expect(decoded == original)
    }

    @Test func everyBodyKindRoundTrips() throws {
        let specs = [
            RequestBodySpec(type: .json, jsonText: "{}"),
            RequestBodySpec(type: .raw, rawText: "<a/>", rawLanguage: .xml, rawContentType: "text/xml"),
            RequestBodySpec(type: .formUrlEncoded, formFields: [ApiKeyValue(key: "a", value: "b")]),
            RequestBodySpec(
                type: .multipart,
                multipartFields: [ApiFormField(key: "f", value: "/tmp/a", kind: .file, contentType: "image/png")]
            ),
            RequestBodySpec(type: .graphql, graphqlQuery: "{ a }", graphqlVariables: "{}"),
            RequestBodySpec(type: .binary, binaryFilePath: "/tmp/b"),
        ]
        for spec in specs {
            let request = SavedRequest(body: spec)
            let decoded = try JSONDecoder().decode(
                SavedRequest.self, from: try JSONEncoder().encode(request)
            )
            #expect(decoded.body == spec)
        }
    }

    @Test func assertionsAndSettingsRoundTrip() throws {
        let request = SavedRequest(
            settings: RequestSettings(
                timeoutSeconds: 5, followRedirects: false, maxRedirects: 2,
                validateTLS: false, sendCookies: false, maxResponseBytes: 1024
            ),
            assertions: [
                ApiAssertion(target: .jsonPath("a.b"), op: .contains, expected: "x"),
                ApiAssertion(enabled: false, target: .header("X"), op: .exists),
            ]
        )
        let decoded = try JSONDecoder().decode(
            SavedRequest.self, from: try JSONEncoder().encode(request)
        )
        #expect(decoded.settings == request.settings)
        #expect(decoded.assertions == request.assertions)
    }

    /// A file written by an older build, or hand-edited, must not wipe the store.
    @Test func decodesFromAMinimalDocument() throws {
        let decoded = try JSONDecoder().decode(ApiClientData.self, from: Data("{}".utf8))
        #expect(decoded.collections.isEmpty)
        #expect(decoded.history.isEmpty)
        #expect(decoded.globals.isEmpty)
        #expect(decoded.activeEnvironmentId == nil)
    }

    @Test func fillsInDefaultsForAbsentRequestFields() throws {
        let json = #"{"id":"x","name":"Bare","url":"https://a.co"}"#
        let request = try JSONDecoder().decode(SavedRequest.self, from: Data(json.utf8))
        #expect(request.id == "x")
        #expect(request.name == "Bare")
        #expect(request.method == .get)
        #expect(request.body.type == BodyType.none)
        #expect(request.auth.type == .none)
        #expect(request.settings == RequestSettings())
        #expect(request.assertions.isEmpty)
        #expect(request.createdAt > 0)
    }

    @Test func mintsAnIdWhenAPairHasNone() throws {
        let pair = try JSONDecoder().decode(
            ApiKeyValue.self, from: Data(#"{"key":"a","value":"b"}"#.utf8)
        )
        #expect(!pair.id.isEmpty)
        #expect(pair.enabled)
    }

    @Test func tolerantOfAnItemNodeWithNoKindTag() throws {
        let json = #"{"folder":{"id":"f","name":"F","items":[]}}"#
        let item = try JSONDecoder().decode(ApiItem.self, from: Data(json.utf8))
        #expect(item.asFolder?.name == "F")
    }

    @Test func historyIsNewestFirstAndBounded() {
        var data = ApiClientData()
        for index in 0..<(ApiClientData.historyLimit + 40) {
            data.addToHistory(
                ApiHistoryEntry(method: .get, url: "https://api.co/\(index)", request: SavedRequest())
            )
        }
        #expect(data.history.count == ApiClientData.historyLimit)
        #expect(data.history.first?.url == "https://api.co/\(ApiClientData.historyLimit + 39)")
        data.clearHistory()
        #expect(data.history.isEmpty)
    }

    @Test func resolvesTheActiveEnvironmentAndScope() {
        let environment = ApiEnvironment(name: "E", variables: [ApiKeyValue(key: "host", value: "env")])
        let collection = ApiCollection(
            name: "C", variables: [ApiKeyValue(key: "path", value: "/v1")]
        )
        var data = ApiClientData(
            collections: [collection],
            environments: [environment],
            globals: [ApiKeyValue(key: "g", value: "1")]
        )
        #expect(data.activeEnvironment == nil)
        data.activeEnvironmentId = environment.id
        #expect(data.activeEnvironment?.name == "E")

        let scope = data.scope(for: collection)
        #expect(scope.environment["host"] == "env")
        #expect(scope.collection["path"] == "/v1")
        #expect(scope.globals["g"] == "1")
        #expect(data.scope(for: nil).collection.isEmpty)
    }

    @Test func findsTheCollectionOwningARequest() {
        let request = SavedRequest(id: "r1")
        let data = ApiClientData(
            collections: [
                ApiCollection(name: "Other"),
                ApiCollection(name: "Owner", items: [.folder(ApiFolder(items: [.request(request)]))]),
            ]
        )
        #expect(data.collection(containing: "r1")?.name == "Owner")
        #expect(data.collection(containing: "ghost") == nil)
    }
}

// MARK: - Send pipeline

private struct HangingTransport: HttpTransport {
    func perform(_ prepared: PreparedRequest) async throws -> HttpTransportResult {
        try await Task.sleep(for: .seconds(30))
        return HttpTransportResult(statusCode: 200)
    }
}

private struct FailingTransport: HttpTransport {
    let error: any Error
    func perform(_ prepared: PreparedRequest) async throws -> HttpTransportResult { throw error }
}

@Suite struct HttpClientServiceTests {

    @Test func sendsWhatTheBuilderProduced() async throws {
        let transport = MockTransport(status: 200, json: #"{"ok":true}"#)
        let client = HttpClientService(transport: transport, files: StubFileReader())
        let request = SavedRequest(
            method: .post,
            url: "api.example.com/v1/items",
            headers: [ApiKeyValue(key: "X-A", value: "1")],
            queryParams: [ApiKeyValue(key: "q", value: "a b")],
            body: RequestBodySpec(type: .json, jsonText: #"{"a":1}"#),
            auth: AuthSpec(type: .bearer, bearerToken: "tok")
        )

        let outcome = try await client.send(request)
        let sent = try #require(await transport.lastRequest)
        #expect(sent.url == "https://api.example.com/v1/items?q=a%20b")
        #expect(sent.method == .post)
        #expect(sent.headerValue("X-A") == "1")
        #expect(sent.headerValue("Authorization") == "Bearer tok")
        #expect(sent.headerValue("Content-Type") == "application/json")
        #expect(sent.body == Data(#"{"a":1}"#.utf8))
        #expect(outcome.response.statusCode == 200)
        #expect(outcome.response.isJSON)
    }

    @Test func mapsTheTransportResultOntoTheResponse() async throws {
        let transport = MockTransport(
            results: [
                .success(
                    HttpTransportResult(
                        statusCode: 201,
                        headers: [(key: "Location", value: "/v1/items/9")],
                        body: Data(#"{"id":9}"#.utf8),
                        redirects: [RedirectHop(statusCode: 301, from: "http://a.co", to: "https://a.co")],
                        timing: ApiTiming(dns: 1, connect: 2, tls: 3, firstByte: 4, total: 42),
                        finalURL: "https://a.co/v1/items"
                    )
                )
            ]
        )
        let client = HttpClientService(transport: transport)
        let outcome = try await client.send(SavedRequest(url: "https://a.co/v1/items"))
        #expect(outcome.response.statusCode == 201)
        #expect(outcome.response.statusText == "Created")
        #expect(outcome.response.headerValue("Location") == "/v1/items/9")
        #expect(outcome.response.elapsedMs == 42)
        #expect(outcome.response.timing?.dns == 1)
        #expect(outcome.response.redirects.count == 1)
        #expect(outcome.response.finalURL == "https://a.co/v1/items")
    }

    @Test func fallsBackToThePreparedURLWhenTheTransportGivesNone() async throws {
        let client = HttpClientService(transport: MockTransport(status: 200, json: "{}"))
        let outcome = try await client.send(SavedRequest(url: "https://a.co/x"))
        #expect(outcome.response.finalURL == "https://a.co/x")
    }

    @Test func resolvesVariablesBeforeSending() async throws {
        let transport = MockTransport(status: 200, json: "{}")
        let client = HttpClientService(transport: transport)
        _ = try await client.send(
            SavedRequest(url: "https://{{host}}/x", auth: AuthSpec(type: .bearer, bearerToken: "{{tok}}")),
            scope: VariableScope(environment: ["host": "api.co", "tok": "t"])
        )
        let sent = try #require(await transport.lastRequest)
        #expect(sent.url == "https://api.co/x")
        #expect(sent.headerValue("Authorization") == "Bearer t")
    }

    @Test func warnsAboutAVariableWithNoValue() async throws {
        let client = HttpClientService(transport: MockTransport(status: 200, json: "{}"))
        let outcome = try await client.send(SavedRequest(url: "https://api.co/{{missing}}"))
        #expect(outcome.warnings.contains { $0.contains("{{missing}}") })
    }

    @Test func appliesCollectionAuthOnlyWhenTheRequestHasNone() async throws {
        let transport = MockTransport(status: 200, json: "{}")
        let client = HttpClientService(transport: transport)
        let inherited = AuthSpec(type: .bearer, bearerToken: "inherited")

        _ = try await client.send(SavedRequest(url: "https://a.co/x"), inheritedAuth: inherited)
        #expect(await transport.lastRequest?.headerValue("Authorization") == "Bearer inherited")

        _ = try await client.send(
            SavedRequest(url: "https://a.co/x", auth: AuthSpec(type: .bearer, bearerToken: "own")),
            inheritedAuth: inherited
        )
        #expect(await transport.lastRequest?.headerValue("Authorization") == "Bearer own")
    }

    @Test func evaluatesTheRequestsAssertions() async throws {
        let transport = MockTransport(status: 201, json: #"{"id":7}"#)
        let client = HttpClientService(transport: transport)
        let outcome = try await client.send(
            SavedRequest(
                url: "https://a.co/x",
                assertions: [
                    ApiAssertion(target: .statusCode, op: .equals, expected: "201"),
                    ApiAssertion(target: .jsonPath("id"), op: .equals, expected: "7"),
                    ApiAssertion(target: .statusCode, op: .equals, expected: "500"),
                ]
            )
        )
        #expect(outcome.assertions.count == 3)
        #expect(outcome.assertions.map(\.passed) == [true, true, false])
        #expect(!outcome.assertionsPassed)
    }

    @Test func reportsTruncation() async throws {
        let transport = MockTransport(
            results: [
                .success(
                    HttpTransportResult(
                        statusCode: 200, body: Data(count: 10), receivedBytes: 99_999, truncated: true
                    )
                )
            ]
        )
        let client = HttpClientService(transport: transport)
        let outcome = try await client.send(SavedRequest(url: "https://a.co/big"))
        #expect(outcome.response.truncated)
        #expect(outcome.response.size == 99_999)
        #expect(outcome.warnings.contains { $0.contains("truncated") })
    }

    @Test func carriesBuilderWarningsThrough() async throws {
        let client = HttpClientService(transport: MockTransport(status: 200, json: "{}"))
        let outcome = try await client.send(
            SavedRequest(
                method: .get, url: "https://a.co/x",
                body: RequestBodySpec(type: .json, jsonText: "{bad")
            )
        )
        #expect(outcome.warnings.contains { $0.contains("isn't valid JSON") })
        #expect(outcome.warnings.contains { $0.contains("don't normally carry a body") })
    }

    @Test func buildFailuresSurfaceBeforeAnythingIsSent() async {
        let transport = MockTransport(status: 200, json: "{}")
        let client = HttpClientService(transport: transport)
        await #expect(throws: ApiRequestError.emptyURL) {
            try await client.send(SavedRequest(url: ""))
        }
        #expect(await transport.performed.isEmpty)
    }

    @Test func transportErrorsPropagate() async {
        let client = HttpClientService(
            transport: FailingTransport(error: HttpTransportError.connectionFailed)
        )
        await #expect(throws: HttpTransportError.connectionFailed) {
            try await client.send(SavedRequest(url: "https://a.co/x"))
        }
    }

    @Test func cancellingTheCallingTaskCancelsTheSend() async throws {
        let client = HttpClientService(transport: HangingTransport())
        let task = Task { try await client.send(SavedRequest(url: "https://a.co/slow")) }
        // Let the send reach the transport before pulling the rug.
        try await Task.sleep(for: .milliseconds(20))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func prepareBuildsWithoutSending() async throws {
        let transport = MockTransport(status: 200, json: "{}")
        let client = HttpClientService(transport: transport)
        let prepared = try await client.prepare(
            SavedRequest(url: "https://{{host}}/x"),
            scope: VariableScope(environment: ["host": "api.co"])
        )
        #expect(prepared.url == "https://api.co/x")
        #expect(await transport.performed.isEmpty)
    }
}

// MARK: - Collection runner

@Suite struct ApiRunnerTests {

    private func collection() -> [ApiItem] {
        [
            .request(
                SavedRequest(
                    name: "First", url: "https://a.co/1",
                    assertions: [ApiAssertion(target: .statusCode, op: .equals, expected: "200")]
                )
            ),
            .folder(
                ApiFolder(
                    name: "Nested",
                    items: [.request(SavedRequest(name: "Second", url: "https://a.co/2"))]
                )
            ),
        ]
    }

    @Test func runsEveryRequestInOrderWithItsPath() async throws {
        let transport = MockTransport(status: 200, json: "{}")
        let runner = ApiRunner(client: HttpClientService(transport: transport))
        let summary = await runner.run(collection())

        #expect(summary.results.map(\.name) == ["First", "Second"])
        #expect(summary.results.map(\.path) == [[], ["Nested"]])
        #expect(summary.passedCount == 2)
        #expect(summary.failedCount == 0)
        #expect(summary.assertionCount == 1)
        #expect(!summary.cancelled)
        #expect(await transport.performed.map(\.url) == ["https://a.co/1", "https://a.co/2"])
    }

    @Test func reportsProgressAsItGoes() async {
        let runner = ApiRunner(client: HttpClientService(transport: MockTransport(status: 200, json: "{}")))
        let seen = Progress()
        _ = await runner.run(collection(), onProgress: { seen.add($0.name) })
        #expect(seen.names == ["First", "Second"])
    }

    @Test func aFailedAssertionFailsItsRow() async throws {
        let transport = MockTransport(status: 500, json: "{}")
        let runner = ApiRunner(client: HttpClientService(transport: transport))
        let summary = await runner.run(collection())
        #expect(summary.passedCount == 0)
        #expect(summary.results[0].assertions.first?.passed == false)
        #expect(summary.results[1].statusCode == 500)
    }

    @Test func aTransportErrorBecomesAFailedRowNotAThrow() async {
        let runner = ApiRunner(
            client: HttpClientService(transport: FailingTransport(error: HttpTransportError.offline))
        )
        let summary = await runner.run(collection())
        #expect(summary.results.count == 2)
        #expect(summary.results.allSatisfy { !$0.passed })
        #expect(summary.results[0].errorText?.contains("No internet") == true)
    }

    @Test func stopsOnTheFirstFailureWhenAsked() async {
        let runner = ApiRunner(client: HttpClientService(transport: MockTransport(status: 500, json: "{}")))
        let summary = await runner.run(collection(), options: RunOptions(stopOnFailure: true))
        #expect(summary.results.count == 1)
    }

    @Test func repeatsForEachIteration() async {
        let runner = ApiRunner(client: HttpClientService(transport: MockTransport(status: 200, json: "{}")))
        let summary = await runner.run(collection(), options: RunOptions(iterations: 3))
        #expect(summary.results.count == 6)
        #expect(summary.results.map(\.iteration) == [1, 1, 2, 2, 3, 3])
    }

    @Test func iterationsAreClamped() async {
        #expect(RunOptions(iterations: 0).effectiveIterations == 1)
        #expect(RunOptions(iterations: -3).effectiveIterations == 1)
        #expect(RunOptions(iterations: 5000).effectiveIterations == 100)
    }

    @Test func honoursTheDelayBetweenRequests() async {
        let runner = ApiRunner(client: HttpClientService(transport: MockTransport(status: 200, json: "{}")))
        let started = ContinuousClock.now
        let summary = await runner.run(collection(), options: RunOptions(delayMs: 40))
        #expect(summary.results.count == 2)
        // One delay, before the second request only.
        #expect(URLSessionTransport.milliseconds(since: started) >= 40)
    }

    @Test func passesTheScopeAndInheritedAuthToEachRequest() async throws {
        let transport = MockTransport(status: 200, json: "{}")
        let runner = ApiRunner(client: HttpClientService(transport: transport))
        _ = await runner.run(
            [.request(SavedRequest(name: "r", url: "https://{{host}}/x"))],
            collectionAuth: AuthSpec(type: .bearer, bearerToken: "ct"),
            scope: VariableScope(collection: ["host": "api.co"])
        )
        let sent = try #require(await transport.lastRequest)
        #expect(sent.url == "https://api.co/x")
        #expect(sent.headerValue("Authorization") == "Bearer ct")
    }

    @Test func anEmptyCollectionRunsClean() async {
        let runner = ApiRunner(client: HttpClientService(transport: MockTransport(status: 200, json: "{}")))
        let summary = await runner.run([])
        #expect(summary.results.isEmpty)
        #expect(summary.headline.contains("0/0 passed"))
    }

    @Test func cancellationStopsTheRunAndSaysSo() async throws {
        let runner = ApiRunner(client: HttpClientService(transport: HangingTransport()))
        let task = Task { await runner.run(collection()) }
        try await Task.sleep(for: .milliseconds(20))
        task.cancel()
        let summary = await task.value
        #expect(summary.cancelled || summary.results.contains { $0.errorText == "Cancelled" })
        #expect(summary.results.count < 2)
    }

    @Test func theHeadlineSummarisesTheRun() async {
        let runner = ApiRunner(client: HttpClientService(transport: MockTransport(status: 200, json: "{}")))
        let summary = await runner.run(collection())
        #expect(summary.headline.contains("2/2 passed"))
        #expect(summary.headline.contains("1 assertion"))
    }
}

/// Collects progress callbacks from the runner's concurrency domain.
private final class Progress: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func add(_ name: String) {
        lock.lock()
        storage.append(name)
        lock.unlock()
    }

    var names: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

// MARK: - Code generation

@Suite struct CodeGeneratorTests {

    private let request = SavedRequest(
        name: "Create",
        method: .post,
        url: "https://api.co/v1/items",
        headers: [ApiKeyValue(key: "Accept", value: "application/json")],
        queryParams: [ApiKeyValue(key: "dry", value: "1")],
        body: RequestBodySpec(type: .json, jsonText: #"{"name":"a"}"#),
        auth: AuthSpec(type: .bearer, bearerToken: "tok")
    )

    @Test func everyTargetIncludesTheEssentials() {
        for target in CodeTarget.allCases {
            let code = CodeGenerator.generate(target, for: request)
            #expect(code.contains("api.co/v1/items"), "\(target) lost the URL")
            #expect(code.contains("dry=1"), "\(target) lost the query")
            #expect(code.lowercased().contains("post"), "\(target) lost the method")
            #expect(code.contains("tok"), "\(target) lost the token")
            #expect(!code.contains("{{"), "\(target) left a variable unresolved")
        }
    }

    @Test func fetchBuildsAValidLookingCall() {
        let code = CodeGenerator.generate(.fetch, for: request)
        #expect(code.contains("await fetch(\"https://api.co/v1/items?dry=1\", {"))
        #expect(code.contains("method: \"POST\","))
        #expect(code.contains("\"Authorization\": \"Bearer tok\","))
        #expect(code.contains(#"body: {"name":"a"},"#))
    }

    @Test func axiosCarriesTimeoutAndRedirectPolicy() {
        let code = CodeGenerator.generate(
            .axios,
            for: SavedRequest(
                url: "https://api.co/x",
                settings: RequestSettings(timeoutSeconds: 5, followRedirects: false)
            )
        )
        #expect(code.contains("timeout: 5000,"))
        #expect(code.contains("maxRedirects: 0,"))
    }

    @Test func pythonEmitsKeywordArguments() {
        let code = CodeGenerator.generate(.pythonRequests, for: request)
        #expect(code.contains("import requests"))
        #expect(code.contains("response = requests.post("))
        #expect(code.contains("headers=headers"))
        #expect(code.contains("timeout=60"))
    }

    @Test func pythonMarksInsecureAndNoRedirect() {
        let code = CodeGenerator.generate(
            .pythonRequests,
            for: SavedRequest(
                url: "https://api.co/x",
                settings: RequestSettings(followRedirects: false, validateTLS: false)
            )
        )
        #expect(code.contains("verify=False"))
        #expect(code.contains("allow_redirects=False"))
    }

    @Test func swiftUsesARawStringForAJSONBody() {
        let code = CodeGenerator.generate(.swiftURLSession, for: request)
        #expect(code.contains("var request = URLRequest(url: URL(string: \"https://api.co/v1/items?dry=1\")!)"))
        #expect(code.contains(##"Data(#"{"name":"a"}"#.utf8)"##))
    }

    @Test func multipartUsesEachLanguagesIdiom() {
        let multipart = SavedRequest(
            method: .post,
            url: "https://api.co/up",
            body: RequestBodySpec(
                type: .multipart,
                multipartFields: [
                    ApiFormField(key: "note", value: "hi"),
                    ApiFormField(key: "photo", value: "/tmp/a.png", kind: .file),
                ]
            )
        )
        #expect(CodeGenerator.generate(.curl, for: multipart).contains("-F 'photo=@/tmp/a.png'"))
        #expect(CodeGenerator.generate(.fetch, for: multipart).contains("new FormData()"))
        #expect(CodeGenerator.generate(.axios, for: multipart).contains("fs.createReadStream"))
        #expect(CodeGenerator.generate(.pythonRequests, for: multipart).contains("files = {"))
        #expect(CodeGenerator.generate(.httpie, for: multipart).contains("--multipart"))

        // The library sets its own boundary, so the generated code must not
        // hard-code the one the builder invented.
        for target in CodeTarget.allCases where target != .curl {
            #expect(
                !CodeGenerator.generate(target, for: multipart).contains("DroidectiveBoundary"),
                "\(target) hard-coded a boundary"
            )
        }
    }

    @Test func escapesQuotesAndNewlinesPerLanguage() {
        let awkward = SavedRequest(
            method: .post,
            url: "https://api.co/x",
            headers: [ApiKeyValue(key: "X-Note", value: #"say "hi""#)],
            body: RequestBodySpec(type: .raw, rawText: "line1\nline2\t\"q\"")
        )
        #expect(CodeGenerator.generate(.fetch, for: awkward).contains(#"say \"hi\""#))
        #expect(CodeGenerator.generate(.fetch, for: awkward).contains(#"line1\nline2\t\"q\""#))
        #expect(CodeGenerator.generate(.pythonRequests, for: awkward).contains("\"\"\""))
        #expect(CodeGenerator.generate(.curl, for: awkward).contains(#"'X-Note: say "hi"'"#))
    }

    @Test func aBadURLProducesAHintNotACrash() {
        #expect(CodeGenerator.generate(.curl, for: SavedRequest(url: "")).contains("valid URL"))
    }

    @Test func dynamicValuesArePinnedSoThePreviewDoesNotChurn() {
        let request = SavedRequest(url: "https://api.co/{{$guid}}")
        #expect(
            CodeGenerator.generate(.curl, for: request)
                == CodeGenerator.generate(.curl, for: request)
        )
    }

    @Test func everyTargetHasALabelAndLanguage() {
        for target in CodeTarget.allCases {
            #expect(!target.label.isEmpty)
            #expect(target.id == target.rawValue)
        }
    }
}

// MARK: - Sidebar rows

@Suite struct ApiCollectionRowsTests {

    private func tree() -> [ApiItem] {
        [
            .request(SavedRequest(id: "r1", name: "One")),
            .folder(
                ApiFolder(
                    id: "f1",
                    name: "Folder",
                    items: [
                        .request(SavedRequest(id: "r2", name: "Two")),
                        .folder(
                            ApiFolder(
                                id: "f2", name: "Inner",
                                items: [.request(SavedRequest(id: "r3", name: "Three"))]
                            )
                        ),
                    ]
                )
            ),
            .request(SavedRequest(id: "r4", name: "Four")),
        ]
    }

    @Test func aCollapsedTreeShowsOnlyTheTopLevel() {
        let rows = ApiCollectionTree.rows(tree(), expanded: [])
        #expect(rows.map(\.id) == ["r1", "f1", "r4"])
        #expect(rows.allSatisfy { $0.depth == 0 })
    }

    @Test func anExpandedFolderContributesItsChildrenOneLevelDeeper() {
        let rows = ApiCollectionTree.rows(tree(), expanded: ["f1"])
        #expect(rows.map(\.id) == ["r1", "f1", "r2", "f2", "r4"])
        #expect(rows.map(\.depth) == [0, 0, 1, 1, 0])
    }

    @Test func nestingGoesAsDeepAsItIsExpanded() {
        let rows = ApiCollectionTree.rows(tree(), expanded: ["f1", "f2"])
        #expect(rows.map(\.id) == ["r1", "f1", "r2", "f2", "r3", "r4"])
        #expect(rows.map(\.depth) == [0, 0, 1, 1, 2, 0])
    }

    @Test func expandingAnInnerFolderWhoseParentIsClosedChangesNothing() {
        let rows = ApiCollectionTree.rows(tree(), expanded: ["f2"])
        #expect(rows.map(\.id) == ["r1", "f1", "r4"])
    }

    @Test func anEmptyTreeHasNoRows() {
        #expect(ApiCollectionTree.rows([], expanded: ["f1"]).isEmpty)
    }

    @Test func anExpandedEmptyFolderStillShowsItself() {
        let rows = ApiCollectionTree.rows(
            [.folder(ApiFolder(id: "f1", name: "Empty", items: []))], expanded: ["f1"]
        )
        #expect(rows.map(\.id) == ["f1"])
    }

    @Test func everyRowIsUniquelyIdentified() {
        let rows = ApiCollectionTree.rows(tree(), expanded: ["f1", "f2"])
        #expect(Set(rows.map(\.id)).count == rows.count)
    }
}
