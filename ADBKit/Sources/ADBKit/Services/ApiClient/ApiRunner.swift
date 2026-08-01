import Foundation

// MARK: - Options and results

public struct RunOptions: Sendable, Equatable {
    public var iterations: Int
    /// Pause between requests, in milliseconds.
    public var delayMs: Int
    public var stopOnFailure: Bool

    public init(iterations: Int = 1, delayMs: Int = 0, stopOnFailure: Bool = false) {
        self.iterations = iterations
        self.delayMs = delayMs
        self.stopOnFailure = stopOnFailure
    }

    public var effectiveIterations: Int { max(1, min(iterations, 100)) }
}

public struct RunResult: Sendable, Identifiable {
    public var id: String
    public var iteration: Int
    public var name: String
    /// Folder names leading to the request.
    public var path: [String]
    public var method: HttpMethod
    public var url: String
    public var statusCode: Int?
    public var elapsedMs: Double?
    public var errorText: String?
    public var assertions: [AssertionResult]

    public init(
        id: String = UUID().uuidString,
        iteration: Int,
        name: String,
        path: [String],
        method: HttpMethod,
        url: String,
        statusCode: Int? = nil,
        elapsedMs: Double? = nil,
        errorText: String? = nil,
        assertions: [AssertionResult] = []
    ) {
        self.id = id
        self.iteration = iteration
        self.name = name
        self.path = path
        self.method = method
        self.url = url
        self.statusCode = statusCode
        self.elapsedMs = elapsedMs
        self.errorText = errorText
        self.assertions = assertions
    }

    /// A row passes when it got a 2xx and every assertion held. A request with
    /// no assertions is judged on its status alone.
    public var passed: Bool {
        guard errorText == nil, let statusCode, (200..<300).contains(statusCode) else { return false }
        return assertions.allSatisfy(\.passed)
    }
}

public struct RunSummary: Sendable {
    public var results: [RunResult]
    public var totalMs: Double
    public var cancelled: Bool

    public init(results: [RunResult], totalMs: Double, cancelled: Bool = false) {
        self.results = results
        self.totalMs = totalMs
        self.cancelled = cancelled
    }

    public var passedCount: Int { results.filter(\.passed).count }
    public var failedCount: Int { results.count - passedCount }
    public var assertionCount: Int { results.reduce(0) { $0 + $1.assertions.count } }

    public var headline: String {
        let requests = results.count
        return "\(passedCount)/\(requests) passed · \(assertionCount) assertion"
            + (assertionCount == 1 ? "" : "s")
            + String(format: " · %.1fs", totalMs / 1000)
    }
}

// MARK: - Runner

/// Runs a collection or folder top to bottom, the way Postman's collection
/// runner does: sequential, one variable scope, assertions evaluated per
/// request. Sequential is deliberate — API test suites usually depend on order
/// (create, then read, then delete).
public struct ApiRunner: Sendable {
    private let client: HttpClientService

    public init(client: HttpClientService) {
        self.client = client
    }

    public func run(
        _ items: [ApiItem],
        collectionAuth: AuthSpec? = nil,
        scope: VariableScope = .empty,
        options: RunOptions = RunOptions(),
        onProgress: (@Sendable (RunResult) -> Void)? = nil
    ) async -> RunSummary {
        let plan = flatten(items, prefix: [])
        var results: [RunResult] = []
        let start = ContinuousClock.now
        var cancelled = false

        iterations: for iteration in 1...options.effectiveIterations {
            for step in plan {
                if Task.isCancelled { cancelled = true; break iterations }

                if options.delayMs > 0, !results.isEmpty {
                    do {
                        try await Task.sleep(for: .milliseconds(options.delayMs))
                    } catch {
                        cancelled = true
                        break iterations
                    }
                }

                let result = await runOne(
                    step, iteration: iteration, collectionAuth: collectionAuth, scope: scope
                )
                results.append(result)
                onProgress?(result)

                if options.stopOnFailure, !result.passed { break iterations }
            }
        }

        return RunSummary(
            results: results,
            totalMs: URLSessionTransport.milliseconds(since: start),
            cancelled: cancelled
        )
    }

    private func runOne(
        _ step: Step, iteration: Int, collectionAuth: AuthSpec?, scope: VariableScope
    ) async -> RunResult {
        do {
            let outcome = try await client.send(
                step.request, scope: scope, inheritedAuth: collectionAuth
            )
            return RunResult(
                iteration: iteration,
                name: step.request.name,
                path: step.path,
                method: step.request.method,
                url: outcome.prepared.url,
                statusCode: outcome.response.statusCode,
                elapsedMs: outcome.response.elapsedMs,
                assertions: outcome.assertions
            )
        } catch is CancellationError {
            return RunResult(
                iteration: iteration,
                name: step.request.name,
                path: step.path,
                method: step.request.method,
                url: step.request.url,
                errorText: "Cancelled"
            )
        } catch {
            return RunResult(
                iteration: iteration,
                name: step.request.name,
                path: step.path,
                method: step.request.method,
                url: step.request.url,
                errorText: error.localizedDescription
            )
        }
    }

    struct Step: Sendable {
        var request: SavedRequest
        var path: [String]
    }

    func flatten(_ items: [ApiItem], prefix: [String]) -> [Step] {
        var out: [Step] = []
        for item in items {
            switch item {
            case .request(let request):
                out.append(Step(request: request, path: prefix))
            case .folder(let folder):
                out.append(contentsOf: flatten(folder.items, prefix: prefix + [folder.name]))
            }
        }
        return out
    }
}
