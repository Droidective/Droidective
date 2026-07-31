import Foundation
import Testing

@testable import ADBKit

// MARK: - Fixtures

private enum Fixture {

    /// Shaped like a real Postman export: nested folders, every body mode, the
    /// decomposed URL object, disabled rows, scripts, and a saved example.
    static let collectionV21 = #"""
    {
      "info": {
        "_postman_id": "11111111-2222-3333-4444-555555555555",
        "name": "Shop API",
        "description": { "content": "Storefront endpoints", "type": "text/markdown" },
        "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
      },
      "auth": {
        "type": "bearer",
        "bearer": [{ "key": "token", "value": "{{accessToken}}", "type": "string" }]
      },
      "variable": [
        { "key": "baseUrl", "value": "https://api.shop.test" },
        { "key": "retries", "value": 3 },
        { "key": "beta", "value": true },
        { "key": "legacy", "value": "x", "disabled": true }
      ],
      "item": [
        {
          "name": "Products",
          "description": "Catalogue",
          "item": [
            {
              "name": "List products",
              "request": {
                "method": "GET",
                "header": [
                  { "key": "Accept", "value": "application/json" },
                  { "key": "X-Debug", "value": "1", "disabled": true }
                ],
                "url": {
                  "raw": "{{baseUrl}}/v1/products?page=1&q=shoe",
                  "protocol": "https",
                  "host": ["api", "shop", "test"],
                  "path": ["v1", "products"],
                  "query": [
                    { "key": "page", "value": "1" },
                    { "key": "q", "value": "shoe" },
                    { "key": "debug", "value": "1", "disabled": true }
                  ]
                },
                "description": "Paged list"
              },
              "response": [{ "name": "200 OK", "body": "{}" }]
            },
            {
              "name": "Get product",
              "protocolProfileBehavior": { "followRedirects": false, "strictSSL": false },
              "request": {
                "method": "GET",
                "header": [],
                "url": {
                  "raw": "{{baseUrl}}/v1/products/:sku",
                  "host": ["{{baseUrl}}"],
                  "path": ["v1", "products", ":sku"],
                  "variable": [{ "key": "sku", "value": "ABC-1" }]
                }
              }
            },
            {
              "name": "Create product",
              "event": [
                {
                  "listen": "test",
                  "script": { "exec": ["pm.test(\"ok\", () => pm.response.to.have.status(201))"] }
                }
              ],
              "request": {
                "method": "POST",
                "header": [{ "key": "Content-Type", "value": "application/json" }],
                "body": {
                  "mode": "raw",
                  "raw": "{\"sku\":\"ABC-1\"}",
                  "options": { "raw": { "language": "json" } }
                },
                "url": { "raw": "{{baseUrl}}/v1/products" },
                "auth": {
                  "type": "basic",
                  "basic": [
                    { "key": "username", "value": "admin" },
                    { "key": "password", "value": "hunter2" }
                  ]
                }
              }
            }
          ]
        },
        {
          "name": "Login",
          "request": {
            "method": "POST",
            "header": "Accept: application/json\nX-Client: web",
            "body": {
              "mode": "urlencoded",
              "urlencoded": [
                { "key": "user", "value": "alice" },
                { "key": "pass", "value": "s3cret" },
                { "key": "remember", "value": "1", "disabled": true }
              ]
            },
            "url": "{{baseUrl}}/v1/login"
          }
        },
        {
          "name": "Upload avatar",
          "request": {
            "method": "POST",
            "body": {
              "mode": "formdata",
              "formdata": [
                { "key": "note", "value": "profile", "type": "text" },
                { "key": "file", "src": "/tmp/a.png", "type": "file", "contentType": "image/png" }
              ]
            },
            "url": { "raw": "{{baseUrl}}/v1/avatar" }
          }
        },
        {
          "name": "GraphQL me",
          "request": {
            "method": "POST",
            "body": {
              "mode": "graphql",
              "graphql": { "query": "query { me { id } }", "variables": "{\"x\":1}" }
            },
            "url": { "raw": "{{baseUrl}}/graphql" }
          }
        },
        {
          "name": "Raw XML",
          "request": {
            "method": "PUT",
            "body": {
              "mode": "raw",
              "raw": "<a/>",
              "options": { "raw": { "language": "xml" } }
            },
            "url": { "raw": "{{baseUrl}}/v1/legacy" }
          }
        },
        {
          "name": "Binary upload",
          "request": {
            "method": "PUT",
            "body": { "mode": "file", "file": { "src": "/tmp/blob.bin" } },
            "url": { "raw": "{{baseUrl}}/v1/blob" }
          }
        },
        {
          "name": "Api key query",
          "request": {
            "method": "GET",
            "auth": {
              "type": "apikey",
              "apikey": [
                { "key": "key", "value": "api_key" },
                { "key": "value", "value": "k123" },
                { "key": "in", "value": "query" }
              ]
            },
            "url": { "raw": "{{baseUrl}}/v1/ping" }
          }
        },
        {
          "name": "Digest auth",
          "request": {
            "method": "GET",
            "auth": { "type": "digest", "digest": [{ "key": "username", "value": "u" }] },
            "url": { "raw": "{{baseUrl}}/v1/secure" }
          }
        },
        {
          "name": "Shorthand",
          "request": "https://api.shop.test/v1/health"
        }
      ]
    }
    """#

    static let environment = #"""
    {
      "id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
      "name": "Staging",
      "values": [
        { "key": "baseUrl", "value": "https://staging.shop.test", "enabled": true, "type": "default" },
        { "key": "accessToken", "value": "tok-staging", "enabled": true, "type": "secret" },
        { "key": "unused", "value": "x", "enabled": false, "type": "default" }
      ],
      "_postman_variable_scope": "environment"
    }
    """#

    static let collectionV1 = #"""
    {
      "id": "old",
      "name": "Legacy",
      "requests": [
        {
          "name": "Old get",
          "method": "GET",
          "url": "https://legacy.test/v1/items?a=1",
          "headers": "Accept: application/json\n"
        },
        {
          "name": "Old post",
          "method": "POST",
          "url": "https://legacy.test/v1/items",
          "dataMode": "raw",
          "rawModeData": "{\"a\":1}"
        },
        {
          "name": "Old form",
          "method": "POST",
          "url": "https://legacy.test/v1/login",
          "dataMode": "urlencoded",
          "data": [{ "key": "u", "value": "alice" }]
        }
      ]
    }
    """#

    static func data(_ text: String) -> Data { Data(text.utf8) }
}

// MARK: - Detection

@Suite struct PostmanDetectionTests {

    @Test func recognisesEachSupportedShape() {
        #expect(PostmanFormat.detect(Fixture.data(Fixture.collectionV21)) == .collectionV2)
        #expect(PostmanFormat.detect(Fixture.data(Fixture.environment)) == .environment)
        #expect(PostmanFormat.detect(Fixture.data(Fixture.collectionV1)) == .collectionV1)
        #expect(PostmanFormat.detect(Fixture.data(#"{"item":[]}"#)) == .collectionV2)
        #expect(PostmanFormat.detect(Fixture.data(#"{"collections":[],"environments":[]}"#)) == .workspace)
    }

    @Test func rejectsUnrelatedJSON() {
        #expect(PostmanFormat.detect(Fixture.data(#"{"hello":"world"}"#)) == .unknown)
        #expect(PostmanFormat.detect(Fixture.data("not json")) == .unknown)
        #expect(PostmanFormat.detect(Data()) == .unknown)
    }

    @Test func importThrowsOnUnusableInput() {
        #expect(throws: PostmanFormatError.notJSON) {
            try PostmanFormat.importFile(Fixture.data("<xml/>"))
        }
        #expect(throws: PostmanFormatError.unrecognisedShape) {
            try PostmanFormat.importFile(Fixture.data(#"{"hello":"world"}"#))
        }
    }
}

// MARK: - Collection v2.1 import

@Suite struct PostmanCollectionImportTests {

    // Imported once per test instance: re-importing mints fresh ids, so two
    // imports can't be compared by id.
    private let result: PostmanImport
    private let collection: ApiCollection

    init() throws {
        result = try PostmanFormat.importFile(Fixture.data(Fixture.collectionV21))
        collection = try #require(result.collections.first)
    }

    private func imported() -> (collection: ApiCollection, warnings: [String]) {
        (collection, result.warnings)
    }

    private func request(_ name: String) throws -> SavedRequest {
        let match = ApiCollectionTree.allRequests(in: collection.items).first { $0.name == name }
        return try #require(match, "no request named \(name)")
    }

    @Test func readsTheCollectionHeader() {
        #expect(collection.name == "Shop API")
        #expect(collection.note == "Storefront endpoints")
        #expect(collection.auth.type == .bearer)
        #expect(collection.auth.bearerToken == "{{accessToken}}")
    }

    @Test func readsVariablesIncludingNonStringValues() {
        #expect(collection.variables.first { $0.key == "baseUrl" }?.value == "https://api.shop.test")
        #expect(collection.variables.first { $0.key == "retries" }?.value == "3")
        #expect(collection.variables.first { $0.key == "beta" }?.value == "true")
        #expect(collection.variables.first { $0.key == "legacy" }?.enabled == false)
    }

    @Test func keepsTheFolderStructure() throws {
        let folder = try #require(collection.items.first?.asFolder)
        #expect(folder.name == "Products")
        #expect(folder.note == "Catalogue")
        #expect(folder.items.count == 3)
        #expect(ApiCollectionTree.requestCount(in: collection.items) == 11)
    }

    @Test func reportsThePathToANestedRequest() throws {
        let listProducts = try request("List products")
        #expect(ApiCollectionTree.path(to: listProducts.id, in: collection.items) == ["Products"])
    }

    @Test func splitsTheURLObjectIntoBaseAndQuery() throws {
        let listProducts = try request("List products")
        #expect(listProducts.url == "{{baseUrl}}/v1/products")
        #expect(listProducts.queryParams.map(\.key) == ["page", "q", "debug"])
        #expect(listProducts.queryParams.map(\.value) == ["1", "shoe", "1"])
        #expect(listProducts.queryParams.last?.enabled == false)
    }

    @Test func carriesHeadersAndTheirDisabledState() throws {
        let listProducts = try request("List products")
        #expect(listProducts.headers.map(\.key) == ["Accept", "X-Debug"])
        #expect(listProducts.headers[0].enabled)
        #expect(listProducts.headers[1].enabled == false)
        #expect(listProducts.note == "Paged list")
    }

    @Test func readsHeadersFromTheOlderStringForm() throws {
        let login = try request("Login")
        #expect(login.headers.map(\.key) == ["Accept", "X-Client"])
        #expect(login.headers.map(\.value) == ["application/json", "web"])
    }

    @Test func readsPathVariables() throws {
        let getProduct = try request("Get product")
        #expect(getProduct.url == "{{baseUrl}}/v1/products/:sku")
        #expect(getProduct.pathVariables.first?.key == "sku")
        #expect(getProduct.pathVariables.first?.value == "ABC-1")
    }

    @Test func readsProtocolProfileBehaviour() throws {
        let getProduct = try request("Get product")
        #expect(getProduct.settings.followRedirects == false)
        #expect(getProduct.settings.validateTLS == false)
    }

    @Test func readsAShorthandStringRequest() throws {
        let shorthand = try request("Shorthand")
        #expect(shorthand.method == .get)
        #expect(shorthand.url == "https://api.shop.test/v1/health")
    }

    @Test func rawJSONBecomesTheJSONBodyKind() throws {
        let create = try request("Create product")
        #expect(create.method == .post)
        #expect(create.body.type == .json)
        #expect(create.body.jsonText == #"{"sku":"ABC-1"}"#)
    }

    @Test func rawXMLKeepsItsLanguage() throws {
        let legacy = try request("Raw XML")
        #expect(legacy.body.type == .raw)
        #expect(legacy.body.rawLanguage == .xml)
        #expect(legacy.body.rawText == "<a/>")
    }

    @Test func urlencodedBecomesFormFields() throws {
        let login = try request("Login")
        #expect(login.body.type == .formUrlEncoded)
        #expect(login.body.formFields.map(\.key) == ["user", "pass", "remember"])
        #expect(login.body.formFields.last?.enabled == false)
    }

    @Test func formdataBecomesMultipartWithFileParts() throws {
        let upload = try request("Upload avatar")
        #expect(upload.body.type == .multipart)
        #expect(upload.body.multipartFields.count == 2)
        #expect(upload.body.multipartFields[0].kind == .text)
        let file = try #require(upload.body.multipartFields.last)
        #expect(file.kind == .file)
        #expect(file.value == "/tmp/a.png")
        #expect(file.contentType == "image/png")
    }

    @Test func graphqlKeepsQueryAndVariables() throws {
        let graphql = try request("GraphQL me")
        #expect(graphql.body.type == .graphql)
        #expect(graphql.body.graphqlQuery == "query { me { id } }")
        #expect(graphql.body.graphqlVariables == #"{"x":1}"#)
    }

    @Test func fileModeBecomesABinaryBody() throws {
        let blob = try request("Binary upload")
        #expect(blob.body.type == .binary)
        #expect(blob.body.binaryFilePath == "/tmp/blob.bin")
    }

    @Test func readsPerRequestAuth() throws {
        let create = try request("Create product")
        #expect(create.auth.type == .basic)
        #expect(create.auth.basicUsername == "admin")
        #expect(create.auth.basicPassword == "hunter2")
    }

    @Test func readsApiKeyLocation() throws {
        let ping = try request("Api key query")
        #expect(ping.auth.type == .apiKey)
        #expect(ping.auth.apiKeyName == "api_key")
        #expect(ping.auth.apiKeyValue == "k123")
        #expect(ping.auth.apiKeyLocation == .query)
    }

    /// Anything the app can't run must be called out, never dropped in silence.
    @Test func warnsAboutScriptsExamplesAndUnsupportedAuth() {
        let warnings = imported().warnings
        #expect(warnings.contains { $0.contains("Create product") && $0.contains("test") })
        #expect(warnings.contains { $0.contains("List products") && $0.contains("example") })
        #expect(warnings.contains { $0.contains("digest") })
    }

    @Test func unsupportedAuthLeavesTheRequestUnauthenticated() throws {
        #expect(try request("Digest auth").auth.type == .none)
    }

    @Test func warnsAboutAnUnknownBodyMode() throws {
        let json = #"""
        {"info":{"name":"x","schema":"v2.1.0/collection.json"},
         "item":[{"name":"r","request":{"method":"POST","url":"https://a.co",
                  "body":{"mode":"msgpack","msgpack":"x"}}}]}
        """#
        let result = try PostmanFormat.importFile(Fixture.data(json))
        #expect(result.warnings.contains { $0.contains("msgpack") })
        #expect(result.collections.first?.items.first?.asRequest?.body.type == BodyType.none)
    }

    @Test func aDisabledBodyIsNotImported() throws {
        let json = #"""
        {"info":{"name":"x","schema":"v2.1.0/collection.json"},
         "item":[{"name":"r","request":{"method":"POST","url":"https://a.co",
                  "body":{"mode":"raw","raw":"{}","disabled":true}}}]}
        """#
        let result = try PostmanFormat.importFile(Fixture.data(json))
        #expect(result.collections.first?.items.first?.asRequest?.body.type == BodyType.none)
    }

    @Test func rebuildsAURLFromItsPartsWhenRawIsAbsent() throws {
        let json = #"""
        {"info":{"name":"x","schema":"v2.1.0/collection.json"},
         "item":[{"name":"r","request":{"method":"GET","url":{
            "protocol":"http","host":["localhost"],"port":"8080",
            "path":["v1","items"],"hash":"top"}}}]}
        """#
        let result = try PostmanFormat.importFile(Fixture.data(json))
        #expect(
            result.collections.first?.items.first?.asRequest?.url
                == "http://localhost:8080/v1/items#top"
        )
    }

    @Test func anUnsupportedMethodFallsBackToGETWithAWarning() throws {
        let json = #"""
        {"info":{"name":"x","schema":"v2.1.0/collection.json"},
         "item":[{"name":"r","request":{"method":"PURGE","url":"https://a.co"}}]}
        """#
        let result = try PostmanFormat.importFile(Fixture.data(json))
        #expect(result.collections.first?.items.first?.asRequest?.method == .get)
        #expect(result.warnings.contains { $0.contains("PURGE") })
    }

    @Test func summarisesWhatWasImported() {
        #expect(result.summary == "Imported 1 collection, 11 requests")
        #expect(!result.isEmpty)
    }

    @Test func theImportedCollectionCanBeSentThroughTheBuilder() throws {
        let listProducts = try request("List products")
        let scope = VariableScope(collection: collection.variables.activeMap)
        let prepared = try HttpRequestBuilder.prepare(
            ApiVariables.resolveRequest(listProducts, scope: scope)
        )
        #expect(prepared.url == "https://api.shop.test/v1/products?page=1&q=shoe")
    }
}

// MARK: - Environment

@Suite struct PostmanEnvironmentTests {

    @Test func importsValuesAndTheirEnabledState() throws {
        let result = try PostmanFormat.importFile(Fixture.data(Fixture.environment))
        let environment = try #require(result.environments.first)
        #expect(environment.name == "Staging")
        #expect(environment.variables.count == 3)
        #expect(environment.variableMap["baseUrl"] == "https://staging.shop.test")
        #expect(environment.variableMap["accessToken"] == "tok-staging")
        #expect(environment.variableMap["unused"] == nil)
        #expect(result.summary == "Imported 1 environment")
    }

    @Test func exportsAShapePostmanReimports() throws {
        let environment = ApiEnvironment(
            name: "Prod",
            variables: [
                ApiKeyValue(key: "baseUrl", value: "https://api.co"),
                ApiKeyValue(key: "off", value: "x", enabled: false),
            ]
        )
        let data = try PostmanFormat.exportEnvironment(environment, id: "fixed-id")
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(json["name"] as? String == "Prod")
        #expect(json["_postman_variable_scope"] as? String == "environment")
        let values = try #require(json["values"] as? [[String: Any]])
        #expect(values.count == 2)
        #expect(values[0]["key"] as? String == "baseUrl")
        #expect(values[1]["enabled"] as? Bool == false)
    }

    @Test func environmentSurvivesAnExportImportRoundTrip() throws {
        let original = ApiEnvironment(
            name: "Prod",
            variables: [
                ApiKeyValue(key: "a", value: "1"),
                ApiKeyValue(key: "b", value: "2", enabled: false),
            ]
        )
        let data = try PostmanFormat.exportEnvironment(original)
        let reimported = try #require(try PostmanFormat.importFile(data).environments.first)
        #expect(reimported.name == original.name)
        #expect(reimported.variables.map(\.key) == ["a", "b"])
        #expect(reimported.variables.map(\.value) == ["1", "2"])
        #expect(reimported.variables.map(\.enabled) == [true, false])
    }
}

// MARK: - Export

@Suite struct PostmanExportTests {

    /// The point of exporting v2.1 is that Postman can read it back, so the
    /// round trip through our own importer has to preserve every request.
    @Test func collectionSurvivesAnExportImportRoundTrip() throws {
        let original = try #require(
            try PostmanFormat.importFile(Fixture.data(Fixture.collectionV21)).collections.first
        )
        let exported = try PostmanFormat.exportCollection(original, includeSecrets: true)
        let reimported = try #require(try PostmanFormat.importFile(exported).collections.first)

        #expect(reimported.name == original.name)
        #expect(reimported.auth.type == original.auth.type)
        #expect(reimported.variables.map(\.key) == original.variables.map(\.key))

        let before = ApiCollectionTree.allRequests(in: original.items)
        let after = ApiCollectionTree.allRequests(in: reimported.items)
        #expect(before.count == after.count)
        for (lhs, rhs) in zip(before, after) {
            #expect(lhs.name == rhs.name)
            #expect(lhs.method == rhs.method)
            #expect(lhs.url == rhs.url)
            #expect(lhs.queryParams.map(\.key) == rhs.queryParams.map(\.key))
            #expect(lhs.queryParams.map(\.value) == rhs.queryParams.map(\.value))
            #expect(lhs.queryParams.map(\.enabled) == rhs.queryParams.map(\.enabled))
            #expect(lhs.headers.map(\.key) == rhs.headers.map(\.key))
            #expect(lhs.headers.map(\.enabled) == rhs.headers.map(\.enabled))
            #expect(lhs.body.type == rhs.body.type, "body kind changed for \(lhs.name)")
            #expect(lhs.body.jsonText == rhs.body.jsonText)
            #expect(lhs.body.rawText == rhs.body.rawText)
            #expect(lhs.body.rawLanguage == rhs.body.rawLanguage)
            #expect(lhs.body.formFields.map(\.key) == rhs.body.formFields.map(\.key))
            #expect(lhs.body.multipartFields.map(\.value) == rhs.body.multipartFields.map(\.value))
            #expect(lhs.body.graphqlQuery == rhs.body.graphqlQuery)
            #expect(lhs.body.binaryFilePath == rhs.body.binaryFilePath)
            #expect(lhs.auth.type == rhs.auth.type)
            #expect(lhs.pathVariables.map(\.value) == rhs.pathVariables.map(\.value))
        }
    }

    @Test func foldersSurviveTheRoundTrip() throws {
        let original = try #require(
            try PostmanFormat.importFile(Fixture.data(Fixture.collectionV21)).collections.first
        )
        let exported = try PostmanFormat.exportCollection(original)
        let reimported = try #require(try PostmanFormat.importFile(exported).collections.first)
        let folder = try #require(reimported.items.first?.asFolder)
        #expect(folder.name == "Products")
        #expect(folder.items.count == 3)
    }

    @Test func writesTheV21SchemaAndInfoBlock() throws {
        let data = try PostmanFormat.exportCollection(
            ApiCollection(name: "Mine", note: "hi"), id: "fixed"
        )
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let info = try #require(json["info"] as? [String: Any])
        #expect(info["schema"] as? String == PostmanFormat.schemaV21)
        #expect(info["name"] as? String == "Mine")
        #expect(info["_postman_id"] as? String == "fixed")
        #expect(json["item"] is [Any])
    }

    @Test func aRequestURLIsExportedWithItsQueryInRawAndInTheTable() throws {
        let collection = ApiCollection(
            name: "c",
            items: [
                .request(
                    SavedRequest(
                        name: "r",
                        url: "https://api.co/s",
                        queryParams: [
                            ApiKeyValue(key: "q", value: "a b"),
                            ApiKeyValue(key: "off", value: "1", enabled: false),
                        ]
                    )
                )
            ]
        )
        let data = try PostmanFormat.exportCollection(collection)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let items = try #require(json["item"] as? [[String: Any]])
        let request = try #require(items[0]["request"] as? [String: Any])
        let url = try #require(request["url"] as? [String: Any])
        #expect(url["raw"] as? String == "https://api.co/s?q=a%20b")
        let query = try #require(url["query"] as? [[String: Any]])
        #expect(query.count == 2)
        #expect(query[1]["disabled"] as? Bool == true)
    }

    /// An exported collection is a file people attach to tickets and commit to
    /// repositories, so credentials stay out of it unless explicitly asked for.
    @Test func secretsAreStrippedByDefault() throws {
        let collection = ApiCollection(
            name: "c",
            items: [
                .request(
                    SavedRequest(
                        name: "r",
                        url: "https://api.co/x",
                        headers: [ApiKeyValue(key: "X-API-Key", value: "live-key")],
                        auth: AuthSpec(type: .bearer, bearerToken: "super-secret")
                    )
                )
            ],
            auth: AuthSpec(type: .basic, basicUsername: "u", basicPassword: "collection-pass")
        )
        let stripped = try PostmanFormat.exportCollection(collection)
        let text = try #require(String(data: stripped, encoding: .utf8))
        #expect(!text.contains("super-secret"))
        #expect(!text.contains("live-key"))
        #expect(!text.contains("collection-pass"))

        let full = try PostmanFormat.exportCollection(collection, includeSecrets: true)
        let fullText = try #require(String(data: full, encoding: .utf8))
        #expect(fullText.contains("super-secret"))
        #expect(fullText.contains("live-key"))
    }

    @Test func exportsEachAuthKindInPostmansShape() throws {
        let specs: [AuthSpec] = [
            AuthSpec(type: .bearer, bearerToken: "t"),
            AuthSpec(type: .basic, basicUsername: "u", basicPassword: "p"),
            AuthSpec(type: .apiKey, apiKeyName: "k", apiKeyValue: "v", apiKeyLocation: .query),
            AuthSpec(type: .oauth2, oauth2Token: "t", oauth2HeaderPrefix: "Token"),
        ]
        for spec in specs {
            let collection = ApiCollection(
                name: "c", items: [.request(SavedRequest(url: "https://a.co", auth: spec))]
            )
            let data = try PostmanFormat.exportCollection(collection, includeSecrets: true)
            let reimported = try #require(try PostmanFormat.importFile(data).collections.first)
            let request = try #require(reimported.items.first?.asRequest)
            #expect(request.auth == spec, "auth changed for \(spec.type)")
        }
    }

    @Test func workspaceExportRoundTripsAndDropsHistory() throws {
        var data = ApiClientData(
            collections: [ApiCollection(name: "c", items: [.request(SavedRequest(name: "r", url: "https://a.co"))])],
            environments: [ApiEnvironment(name: "e", variables: [ApiKeyValue(key: "k", value: "v")])],
            globals: [ApiKeyValue(key: "g", value: "1")]
        )
        data.addToHistory(ApiHistoryEntry(method: .get, url: "https://a.co", request: SavedRequest()))

        let exported = try PostmanFormat.exportWorkspace(data)
        #expect(PostmanFormat.detect(exported) == .workspace)
        let reimported = try PostmanFormat.importFile(exported)
        #expect(reimported.collections.count == 1)
        #expect(reimported.environments.count == 1)
        #expect(reimported.collections.first?.name == "c")
        let decoded = try JSONDecoder().decode(ApiClientData.self, from: exported)
        #expect(decoded.history.isEmpty)
        #expect(decoded.globals.first?.key == "g")
    }
}

// MARK: - Collection v1

@Suite struct PostmanV1ImportTests {

    @Test func importsRequestsFromTheOlderFormat() throws {
        let result = try PostmanFormat.importFile(Fixture.data(Fixture.collectionV1))
        let collection = try #require(result.collections.first)
        #expect(collection.name == "Legacy")
        let requests = ApiCollectionTree.allRequests(in: collection.items)
        #expect(requests.map(\.name) == ["Old get", "Old post", "Old form"])
        #expect(requests[0].url == "https://legacy.test/v1/items")
        #expect(requests[0].queryParams.first?.key == "a")
        #expect(requests[0].headers.first?.key == "Accept")
        #expect(requests[1].body.type == .json)
        #expect(requests[2].body.type == .formUrlEncoded)
        #expect(requests[2].body.formFields.first?.value == "alice")
        #expect(result.warnings.contains { $0.contains("v1 collection") })
    }
}
