import Foundation
import Testing

@testable import ADBKit

@Suite struct ApiVariableResolutionTests {

    @Test func substitutesEveryReference() {
        let result = ApiVariables.resolve(
            "https://{{host}}/api/v{{version}}", with: ["host": "example.com", "version": "2"]
        )
        #expect(result == "https://example.com/api/v2")
    }

    /// An unknown name stays visible rather than collapsing to an empty string,
    /// which is what makes a typo in a variable name findable.
    @Test func leavesUnknownReferencesWritten() {
        #expect(ApiVariables.resolve("{{known}}/{{unknown}}", with: ["known": "v"]) == "v/{{unknown}}")
        #expect(ApiVariables.resolve("{{host}}", with: [:]) == "{{host}}")
    }

    @Test func passesThroughTextWithoutReferences() {
        #expect(ApiVariables.resolve("plain text", with: ["host": "v"]) == "plain text")
        #expect(ApiVariables.resolve("", with: ["a": "b"]) == "")
    }

    @Test func trimsWhitespaceInsideBraces() {
        #expect(ApiVariables.resolve("{{  host  }}", with: ["host": "v"]) == "v")
    }

    @Test func handlesAdjacentReferences() {
        #expect(ApiVariables.resolve("{{a}}{{b}}{{a}}", with: ["a": "1", "b": "2"]) == "121")
    }

    @Test func ignoresMalformedReferences() {
        #expect(ApiVariables.resolve("{{}}", with: ["": "x"]) == "{{}}")
        #expect(ApiVariables.resolve("{{a", with: ["a": "1"]) == "{{a")
        #expect(ApiVariables.resolve("a}}b", with: ["a": "1"]) == "a}}b")
        #expect(ApiVariables.resolve("{{{a}}}", with: ["a": "1"]) == "{{{a}}}")
    }

    @Test func aValueContainingBracesIsNotReinterpreted() {
        // The replacement is data, not a template to re-scan for new syntax.
        #expect(ApiVariables.resolve("{{a}}", with: ["a": "{{literal"]) == "{{literal")
    }

    @Test func expandsAReferenceInsideAValue() {
        let scope = VariableScope(globals: ["base": "https://{{host}}", "host": "api.co"])
        #expect(ApiVariables.resolve("{{base}}/v1", scope: scope) == "https://api.co/v1")
    }

    @Test func aReferenceCycleTerminates() {
        let scope = VariableScope(globals: ["a": "{{b}}", "b": "{{a}}"])
        let result = ApiVariables.resolve("{{a}}", scope: scope)
        #expect(result.contains("{{"))
    }

    @Test func aSelfReferenceTerminates() {
        #expect(ApiVariables.resolve("{{a}}", with: ["a": "{{a}}"]) == "{{a}}")
    }

    @Test func aFanOutIsBoundedRatherThanExponential() {
        // Each level doubles; the depth cap and byte ceiling stop it.
        let scope = VariableScope(globals: [
            "a": "{{b}}{{b}}", "b": "{{c}}{{c}}", "c": "{{d}}{{d}}",
            "d": "{{e}}{{e}}", "e": String(repeating: "x", count: 1000),
        ])
        let result = ApiVariables.resolve("{{a}}", scope: scope)
        #expect(result.count == 16000)
    }

    // MARK: Scopes

    @Test func precedenceIsLocalThenCollectionThenEnvironmentThenGlobal() {
        let scope = VariableScope(
            globals: ["host": "global", "g": "1"],
            environment: ["host": "env", "e": "1"],
            collection: ["host": "collection", "c": "1"],
            local: ["host": "local"]
        )
        #expect(ApiVariables.resolve("{{host}}", scope: scope) == "local")
        #expect(ApiVariables.resolve("{{g}}{{e}}{{c}}", scope: scope) == "111")
    }

    @Test func lowerLayersShowThroughWhereHigherOnesAreSilent() {
        let scope = VariableScope(globals: ["a": "g"], environment: ["b": "e"])
        #expect(ApiVariables.resolve("{{a}}/{{b}}", scope: scope) == "g/e")
    }

    @Test func reportsWhichLayerAValueCameFrom() {
        let scope = VariableScope(
            globals: ["a": "1"], environment: ["b": "1"], collection: ["c": "1"], local: ["d": "1"]
        )
        #expect(scope.origin(of: "a") == "global")
        #expect(scope.origin(of: "b") == "environment")
        #expect(scope.origin(of: "c") == "collection")
        #expect(scope.origin(of: "d") == "request")
        #expect(scope.origin(of: "missing") == nil)
    }

    @Test func disabledVariablesAreInvisible() {
        let environment = ApiEnvironment(
            name: "test",
            variables: [
                ApiKeyValue(key: "on", value: "1"),
                ApiKeyValue(key: "off", value: "2", enabled: false),
                ApiKeyValue(key: "", value: "3"),
            ]
        )
        #expect(environment.variableMap == ["on": "1"])
    }

    @Test func aLaterDuplicateWins() {
        let pairs = [ApiKeyValue(key: "a", value: "first"), ApiKeyValue(key: "a", value: "second")]
        #expect(pairs.activeMap["a"] == "second")
    }

    // MARK: Dynamic values

    @Test func generatesDynamicValues() {
        let dynamic = DynamicVariables.fixed(
            uuid: "abc-123", date: Date(timeIntervalSince1970: 1_700_000_000), randomInt: 7
        )
        #expect(ApiVariables.resolve("{{$guid}}", with: [:], dynamic: dynamic) == "abc-123")
        #expect(ApiVariables.resolve("{{$randomUUID}}", with: [:], dynamic: dynamic) == "abc-123")
        #expect(ApiVariables.resolve("{{$timestamp}}", with: [:], dynamic: dynamic) == "1700000000")
        #expect(ApiVariables.resolve("{{$randomInt}}", with: [:], dynamic: dynamic) == "7")
        #expect(
            ApiVariables.resolve("{{$isoTimestamp}}", with: [:], dynamic: dynamic)
                == "2023-11-14T22:13:20.000Z"
        )
    }

    @Test func dynamicValuesResolveWithNoEnvironmentPresent() {
        let dynamic = DynamicVariables.fixed(uuid: "u")
        #expect(ApiVariables.resolve("id-{{$guid}}", with: [:], dynamic: dynamic) == "id-u")
    }

    @Test func anUnknownDollarNameIsLeftAlone() {
        #expect(ApiVariables.resolve("{{$randomFullName}}", with: [:]) == "{{$randomFullName}}")
    }

    @Test func liveGeneratorsProduceDistinctValues() {
        let first = ApiVariables.resolve("{{$guid}}", with: ["x": "1"])
        let second = ApiVariables.resolve("{{$guid}}", with: ["x": "1"])
        #expect(first != second)
        #expect(first.count == 36)
    }

    // MARK: Unresolved reporting

    @Test func listsUnresolvedNames() {
        let scope = VariableScope(environment: ["known": "1"])
        #expect(
            ApiVariables.unresolvedNames(in: "{{known}}/{{a}}/{{b}}/{{a}}", scope: scope) == ["a", "b"]
        )
        #expect(ApiVariables.unresolvedNames(in: "{{known}}", scope: scope).isEmpty)
    }

    @Test func dynamicNamesAreNotReportedAsUnresolved() {
        #expect(ApiVariables.unresolvedNames(in: "{{$guid}}", scope: .empty).isEmpty)
    }

    @Test func scansAWholeRequestForUnresolvedNames() {
        let request = SavedRequest(
            url: "https://{{host}}/x",
            headers: [ApiKeyValue(key: "X-{{hk}}", value: "{{hv}}")],
            queryParams: [ApiKeyValue(key: "q", value: "{{qv}}")],
            body: RequestBodySpec(type: .json, jsonText: #"{"a":"{{bv}}"}"#),
            auth: AuthSpec(type: .bearer, bearerToken: "{{tok}}")
        )
        let names = ApiVariables.unresolvedNames(in: request, scope: VariableScope(globals: ["host": "a.co"]))
        #expect(Set(names) == ["hk", "hv", "qv", "bv", "tok"])
    }

    @Test func disabledRowsAreNotScanned() {
        let request = SavedRequest(
            url: "https://a.co",
            headers: [ApiKeyValue(key: "X", value: "{{off}}", enabled: false)]
        )
        #expect(ApiVariables.unresolvedNames(in: request, scope: .empty).isEmpty)
    }

    // MARK: Whole-request resolution

    @Test func resolvesEveryFieldOfARequest() {
        let request = SavedRequest(
            url: "https://{{host}}/api",
            headers: [ApiKeyValue(key: "X-{{name}}", value: "Bearer {{token}}")],
            queryParams: [ApiKeyValue(key: "{{qk}}", value: "{{qv}}")],
            pathVariables: [ApiKeyValue(key: "id", value: "{{userId}}")],
            body: RequestBodySpec(type: .json, jsonText: #"{"key":"{{apiKey}}"}"#),
            auth: AuthSpec(
                type: .basic, basicUsername: "{{user}}", basicPassword: "{{password}}"
            )
        )
        let scope = VariableScope(environment: [
            "host": "api.com", "name": "Trace", "token": "tok123", "qk": "q", "qv": "search",
            "userId": "42", "apiKey": "key456", "user": "alice", "password": "s3cret",
        ])
        let resolved = ApiVariables.resolveRequest(request, scope: scope)
        #expect(resolved.url == "https://api.com/api")
        #expect(resolved.headers[0].key == "X-Trace")
        #expect(resolved.headers[0].value == "Bearer tok123")
        #expect(resolved.queryParams[0].key == "q")
        #expect(resolved.queryParams[0].value == "search")
        #expect(resolved.pathVariables[0].value == "42")
        #expect(resolved.body.jsonText == #"{"key":"key456"}"#)
        #expect(resolved.auth.basicUsername == "alice")
        #expect(resolved.auth.basicPassword == "s3cret")
    }

    @Test func resolvesEachBodyKind() {
        let scope = VariableScope(environment: ["v": "X"])
        func resolvedBody(_ spec: RequestBodySpec) -> RequestBodySpec {
            ApiVariables.resolveRequest(
                SavedRequest(url: "https://a.co", body: spec), scope: scope
            ).body
        }
        #expect(resolvedBody(RequestBodySpec(type: .raw, rawText: "{{v}}")).rawText == "X")
        #expect(
            resolvedBody(
                RequestBodySpec(type: .formUrlEncoded, formFields: [ApiKeyValue(key: "k", value: "{{v}}")])
            ).formFields[0].value == "X"
        )
        #expect(
            resolvedBody(
                RequestBodySpec(type: .multipart, multipartFields: [ApiFormField(key: "k", value: "{{v}}")])
            ).multipartFields[0].value == "X"
        )
        #expect(
            resolvedBody(
                RequestBodySpec(type: .graphql, graphqlQuery: "{ {{v}} }", graphqlVariables: #"{"a":"{{v}}"}"#)
            ).graphqlQuery == "{ X }"
        )
        #expect(
            resolvedBody(RequestBodySpec(type: .binary, binaryFilePath: "/tmp/{{v}}.bin"))
                .binaryFilePath == "/tmp/X.bin"
        )
    }

    @Test func anEmptyScopeLeavesTheRequestUntouched() {
        let request = SavedRequest(url: "https://{{host}}/api")
        #expect(ApiVariables.resolveRequest(request, scope: .empty).url == "https://{{host}}/api")
    }

    @Test func resolutionReachesTheBuiltRequest() throws {
        let request = SavedRequest(
            url: "https://{{host}}/v1",
            queryParams: [ApiKeyValue(key: "k", value: "{{v}}")],
            auth: AuthSpec(type: .bearer, bearerToken: "{{tok}}")
        )
        let scope = VariableScope(environment: ["host": "api.co", "v": "1", "tok": "t"])
        let prepared = try HttpRequestBuilder.prepare(
            ApiVariables.resolveRequest(request, scope: scope)
        )
        #expect(prepared.url == "https://api.co/v1?k=1")
        #expect(prepared.headerValue("Authorization") == "Bearer t")
    }
}
