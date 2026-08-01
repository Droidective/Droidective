import Foundation

/// Everything one send produced: the response, exactly what went on the wire,
/// the assertion results, and any non-fatal notes.
public struct ApiSendOutcome: Sendable {
    public var response: ApiResponse
    public var prepared: PreparedRequest
    public var assertions: [AssertionResult]
    public var warnings: [String]

    public init(
        response: ApiResponse,
        prepared: PreparedRequest,
        assertions: [AssertionResult] = [],
        warnings: [String] = []
    ) {
        self.response = response
        self.prepared = prepared
        self.assertions = assertions
        self.warnings = warnings
    }

    public var assertionsPassed: Bool { assertions.allSatisfy(\.passed) }
}

/// Resolves, builds, and sends a request.
///
/// Cancellation rides Swift's own task cancellation: the caller keeps the `Task`
/// wrapping `send` and cancels it, which tears down the URLSession task through
/// the transport's cancellation handler. There is deliberately no in-flight
/// registry — keying one by request id can't distinguish two concurrent sends of
/// the same saved request.
public actor HttpClientService {
    private let transport: any HttpTransport
    private let files: any ApiFileReading

    public init(
        transport: any HttpTransport = URLSessionTransport(),
        files: any ApiFileReading = DiskFileReader()
    ) {
        self.transport = transport
        self.files = files
    }

    /// Resolves variables, applies inherited auth, and builds the wire form
    /// without sending it — used by the code-generation and cURL previews.
    public func prepare(
        _ request: SavedRequest,
        scope: VariableScope = .empty,
        inheritedAuth: AuthSpec? = nil,
        dynamic: DynamicVariables = .live
    ) throws -> PreparedRequest {
        let resolved = Self.resolve(request, scope: scope, inheritedAuth: inheritedAuth, dynamic: dynamic)
        return try HttpRequestBuilder.prepare(resolved, files: files)
    }

    public func send(
        _ request: SavedRequest,
        scope: VariableScope = .empty,
        inheritedAuth: AuthSpec? = nil,
        dynamic: DynamicVariables = .live
    ) async throws -> ApiSendOutcome {
        let resolved = Self.resolve(request, scope: scope, inheritedAuth: inheritedAuth, dynamic: dynamic)
        let prepared = try HttpRequestBuilder.prepare(resolved, files: files)

        var warnings = prepared.warnings
        let unresolved = ApiVariables.unresolvedNames(in: request, scope: scope)
        if !unresolved.isEmpty {
            warnings.insert(
                "No value for \(unresolved.map { "{{\($0)}}" }.joined(separator: ", "))"
                    + " — sent as written.",
                at: 0
            )
        }

        try Task.checkCancellation()
        let result = try await transport.perform(prepared)

        let response = ApiResponse(
            statusCode: result.statusCode,
            headers: result.headers,
            body: result.body,
            elapsedMs: result.timing?.total ?? 0,
            size: result.receivedBytes,
            truncated: result.truncated,
            redirects: result.redirects,
            timing: result.timing,
            finalURL: result.finalURL.isEmpty ? prepared.url : result.finalURL
        )
        if result.truncated {
            warnings.append(
                "Response was larger than \(ApiResponse.formatBytes(prepared.settings.effectiveMaxResponseBytes))"
                    + " and was truncated."
            )
        }

        return ApiSendOutcome(
            response: response,
            prepared: prepared,
            assertions: ApiAssertions.evaluate(request.assertions, against: response),
            warnings: warnings
        )
    }

    /// Collection auth applies to requests that don't set their own — Postman's
    /// per-request "Inherit auth from parent".
    static func resolve(
        _ request: SavedRequest,
        scope: VariableScope,
        inheritedAuth: AuthSpec?,
        dynamic: DynamicVariables
    ) -> SavedRequest {
        var source = request
        if source.auth.type == .none, let inheritedAuth, inheritedAuth.type != .none {
            source.auth = inheritedAuth
        }
        return ApiVariables.resolveRequest(source, scope: scope, dynamic: dynamic)
    }
}
