import Foundation
import Testing

@testable import ADBKit

// MARK: - URLRequest translation

@Suite struct URLSessionTransportRequestTests {

    @Test func carriesMethodTimeoutAndBody() throws {
        let prepared = PreparedRequest(
            url: "https://api.co/v1",
            method: .patch,
            headers: [(key: "X-A", value: "1")],
            body: Data("hi".utf8),
            settings: RequestSettings(timeoutSeconds: 7, sendCookies: false)
        )
        let request = try URLSessionTransport.urlRequest(from: prepared)
        #expect(request.url?.absoluteString == "https://api.co/v1")
        #expect(request.httpMethod == "PATCH")
        #expect(request.timeoutInterval == 7)
        #expect(request.httpBody == Data("hi".utf8))
        #expect(request.value(forHTTPHeaderField: "X-A") == "1")
        #expect(request.httpShouldHandleCookies == false)
    }

    /// `setValue` would drop the first of a repeated header; `addValue` keeps both.
    @Test func keepsRepeatedHeaders() throws {
        let prepared = PreparedRequest(
            url: "https://api.co/v1",
            method: .get,
            headers: [(key: "X-A", value: "1"), (key: "X-A", value: "2")]
        )
        let request = try URLSessionTransport.urlRequest(from: prepared)
        #expect(request.value(forHTTPHeaderField: "X-A") == "1,2")
    }

    @Test func rejectsAURLTheTransportCantUse() {
        #expect(throws: ApiRequestError.invalidURL("not a url at all")) {
            try URLSessionTransport.urlRequest(
                from: PreparedRequest(url: "not a url at all", method: .get, headers: [])
            )
        }
    }
}

// MARK: - Error mapping

@Suite struct URLSessionTransportErrorTests {

    private func mapped(_ code: Int, userInfo: [String: Any] = [:]) -> any Error {
        URLSessionTransport.mapped(
            NSError(domain: NSURLErrorDomain, code: code, userInfo: userInfo), timeout: 30
        )
    }

    @Test func translatesConnectivityFailures() {
        #expect(mapped(NSURLErrorNotConnectedToInternet) as? HttpTransportError == .offline)
        #expect(mapped(NSURLErrorNetworkConnectionLost) as? HttpTransportError == .connectionFailed)
        #expect(mapped(NSURLErrorCannotConnectToHost) as? HttpTransportError == .connectionFailed)
        #expect(mapped(NSURLErrorTimedOut) as? HttpTransportError == .timedOut(30))
    }

    @Test func namesTheHostThatCouldNotBeFound() {
        let error = mapped(
            NSURLErrorCannotFindHost,
            userInfo: [NSURLErrorFailingURLStringErrorKey: "https://nope.example/x"]
        )
        #expect(error as? HttpTransportError == .hostNotFound("nope.example"))
    }

    @Test func fallsBackWhenTheFailingURLIsAbsent() {
        #expect(mapped(NSURLErrorDNSLookupFailed) as? HttpTransportError == .hostNotFound("that host"))
    }

    @Test func translatesTLSFailuresIntoAnActionableMessage() throws {
        let error = mapped(NSURLErrorServerCertificateUntrusted)
        let transportError = try #require(error as? HttpTransportError)
        if case .tlsFailure = transportError {
            #expect(transportError.errorDescription?.contains("certificate validation") == true)
        } else {
            Issue.record("expected a TLS failure, got \(transportError)")
        }
    }

    @Test func cancellationStaysCancellation() {
        #expect(mapped(NSURLErrorCancelled) is CancellationError)
    }

    @Test func keepsUnrecognisedErrorsIntact() throws {
        let error = try #require(mapped(-12345) as? HttpTransportError)
        if case .other(let code, _) = error {
            #expect(code == -12345)
        } else {
            Issue.record("expected .other, got \(error)")
        }
    }

    @Test func leavesNonURLErrorsAlone() {
        struct Custom: Error {}
        #expect(URLSessionTransport.mapped(Custom(), timeout: 1) is Custom)
    }

    @Test func everyErrorHasAMessage() {
        let errors: [HttpTransportError] = [
            .notHTTP, .offline, .hostNotFound("h"), .connectionFailed, .timedOut(5),
            .tlsFailure("bad"), .tooManyRedirects(3), .insecureUnsupported,
            .other(code: 1, message: "m"),
        ]
        for error in errors {
            #expect(error.errorDescription?.isEmpty == false)
        }
    }
}

// MARK: - Response collector

/// Drives `ResponseCollector` the way URLSession would, so the byte cap,
/// redirect policy and single-resume guarantee are covered without a socket.
@Suite struct ResponseCollectorTests {

    private final class Outcome: @unchecked Sendable {
        private let lock = NSLock()
        private var results: [Result<HttpTransportResult, any Error>] = []

        func record(_ result: Result<HttpTransportResult, any Error>) {
            lock.lock()
            results.append(result)
            lock.unlock()
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return results.count
        }

        var value: HttpTransportResult? {
            lock.lock()
            defer { lock.unlock() }
            guard case .success(let result) = results.first else { return nil }
            return result
        }

        var error: (any Error)? {
            lock.lock()
            defer { lock.unlock() }
            guard case .failure(let error) = results.first else { return nil }
            return error
        }
    }

    private func makeCollector(
        _ settings: RequestSettings = RequestSettings()
    ) -> (ResponseCollector, Outcome, URLSession, URLSessionDataTask) {
        let collector = ResponseCollector(settings: settings)
        let outcome = Outcome()
        collector.finish = { outcome.record($0) }
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: URLRequest(url: URL(string: "https://api.co/x")!))
        _ = collector.adopt(task)
        return (collector, outcome, session, task)
    }

    private func httpResponse(
        _ status: Int, headers: [String: String] = [:], url: String = "https://api.co/x"
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: url)!, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }

    @Test func capturesStatusHeadersAndBody() throws {
        let (collector, outcome, session, task) = makeCollector()
        defer { session.invalidateAndCancel() }

        collector.urlSession(
            session, dataTask: task,
            didReceive: httpResponse(201, headers: ["Content-Type": "application/json"]),
            completionHandler: { _ in }
        )
        collector.urlSession(session, dataTask: task, didReceive: Data("{\"a\":".utf8))
        collector.urlSession(session, dataTask: task, didReceive: Data("1}".utf8))
        collector.urlSession(session, task: task, didCompleteWithError: nil)

        let result = try #require(outcome.value)
        #expect(result.statusCode == 201)
        #expect(result.body == Data("{\"a\":1}".utf8))
        #expect(result.receivedBytes == 7)
        #expect(!result.truncated)
        #expect(result.headers.contains { $0.key == "Content-Type" })
        #expect(result.finalURL == "https://api.co/x")
    }

    @Test func rejectsANonHTTPResponse() {
        let (collector, outcome, session, task) = makeCollector()
        defer { session.invalidateAndCancel() }
        let response = URLResponse(
            url: URL(string: "https://api.co/x")!, mimeType: nil,
            expectedContentLength: 0, textEncodingName: nil
        )
        collector.urlSession(session, dataTask: task, didReceive: response, completionHandler: { _ in })
        #expect(outcome.error as? HttpTransportError == .notHTTP)
    }

    /// Past the cap the body stops growing, the task is cancelled, and the
    /// cancellation is reported as a successful truncated response.
    @Test func capsTheBodyAndReportsTruncation() throws {
        let (collector, outcome, session, task) = makeCollector(RequestSettings(maxResponseBytes: 10))
        defer { session.invalidateAndCancel() }

        collector.urlSession(session, dataTask: task, didReceive: httpResponse(200), completionHandler: { _ in })
        collector.urlSession(session, dataTask: task, didReceive: Data(repeating: 0x41, count: 8))
        collector.urlSession(session, dataTask: task, didReceive: Data(repeating: 0x42, count: 8))
        collector.urlSession(
            session, task: task,
            didCompleteWithError: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        )

        let result = try #require(outcome.value)
        #expect(result.truncated)
        #expect(result.body.count == 10)
        #expect(result.receivedBytes == 16)
        #expect(result.statusCode == 200)
    }

    @Test func aUserCancelStaysAFailure() {
        let (collector, outcome, session, task) = makeCollector()
        defer { session.invalidateAndCancel() }
        collector.urlSession(session, dataTask: task, didReceive: httpResponse(200), completionHandler: { _ in })
        collector.cancel()
        collector.urlSession(
            session, task: task,
            didCompleteWithError: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        )
        #expect(outcome.error != nil)
    }

    @Test func adoptRefusesAfterCancellation() {
        let collector = ResponseCollector(settings: RequestSettings())
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        collector.cancel()
        #expect(collector.adopt(session.dataTask(with: URL(string: "https://a.co")!)) == false)
    }

    @Test func resumesTheContinuationExactlyOnce() {
        let (collector, outcome, session, task) = makeCollector()
        defer { session.invalidateAndCancel() }
        collector.urlSession(session, task: task, didCompleteWithError: nil)
        collector.urlSession(session, task: task, didCompleteWithError: nil)
        collector.complete(with: .failure(HttpTransportError.offline))
        #expect(outcome.count == 1)
    }

    // MARK: Redirects

    @Test func recordsAndFollowsARedirect() throws {
        let (collector, outcome, session, task) = makeCollector()
        defer { session.invalidateAndCancel() }
        let followed = Box<URLRequest?>(nil)

        collector.urlSession(
            session, task: task,
            willPerformHTTPRedirection: httpResponse(301, url: "http://api.co/old"),
            newRequest: URLRequest(url: URL(string: "https://api.co/new")!),
            completionHandler: { followed.value = $0 }
        )
        #expect(followed.value?.url?.absoluteString == "https://api.co/new")

        collector.urlSession(session, dataTask: task, didReceive: httpResponse(200), completionHandler: { _ in })
        collector.urlSession(session, task: task, didCompleteWithError: nil)

        let result = try #require(outcome.value)
        #expect(result.redirects.count == 1)
        #expect(result.redirects[0].statusCode == 301)
        #expect(result.redirects[0].from == "http://api.co/old")
        #expect(result.redirects[0].to == "https://api.co/new")
        #expect(result.statusCode == 200)
    }

    /// With following off, the 3xx itself is the answer — status and headers
    /// come from the redirect response rather than being thrown away.
    @Test func stopsAtTheRedirectWhenFollowingIsOff() throws {
        let (collector, outcome, session, task) = makeCollector(
            RequestSettings(followRedirects: false)
        )
        defer { session.invalidateAndCancel() }
        let followed = Box<URLRequest?>(URLRequest(url: URL(string: "https://placeholder")!))

        collector.urlSession(
            session, task: task,
            willPerformHTTPRedirection: httpResponse(
                302, headers: ["Location": "/new"], url: "https://api.co/old"
            ),
            newRequest: URLRequest(url: URL(string: "https://api.co/new")!),
            completionHandler: { followed.value = $0 }
        )
        #expect(followed.value == nil)

        collector.urlSession(session, task: task, didCompleteWithError: nil)
        let result = try #require(outcome.value)
        #expect(result.statusCode == 302)
        #expect(result.headers.contains { $0.key == "Location" && $0.value == "/new" })
        #expect(result.redirects.count == 1)
        #expect(result.finalURL == "https://api.co/old")
    }

    @Test func failsPastTheRedirectLimit() {
        let (collector, outcome, session, task) = makeCollector(RequestSettings(maxRedirects: 2))
        defer { session.invalidateAndCancel() }

        for index in 0..<3 {
            collector.urlSession(
                session, task: task,
                willPerformHTTPRedirection: httpResponse(302, url: "https://api.co/\(index)"),
                newRequest: URLRequest(url: URL(string: "https://api.co/\(index + 1)")!),
                completionHandler: { _ in }
            )
        }
        #expect(outcome.error as? HttpTransportError == .tooManyRedirects(2))
    }

    @Test func zeroRedirectsMeansTheFirstHopFails() {
        let (collector, outcome, session, task) = makeCollector(RequestSettings(maxRedirects: 0))
        defer { session.invalidateAndCancel() }
        collector.urlSession(
            session, task: task,
            willPerformHTTPRedirection: httpResponse(302),
            newRequest: URLRequest(url: URL(string: "https://api.co/new")!),
            completionHandler: { _ in }
        )
        #expect(outcome.error as? HttpTransportError == .tooManyRedirects(0))
    }

    // MARK: TLS

    @Test func performsDefaultHandlingWhenValidationIsOn() {
        let (collector, _, session, task) = makeCollector()
        defer { session.invalidateAndCancel() }
        let disposition = Box<URLSession.AuthChallengeDisposition?>(nil)
        collector.urlSession(
            session, task: task,
            didReceive: URLAuthenticationChallenge(
                protectionSpace: URLProtectionSpace(
                    host: "api.co", port: 443, protocol: "https", realm: nil,
                    authenticationMethod: NSURLAuthenticationMethodServerTrust
                ),
                proposedCredential: nil, previousFailureCount: 0, failureResponse: nil,
                error: nil, sender: NoopChallengeSender()
            ),
            completionHandler: { disposition.value = $0; _ = $1 }
        )
        #expect(disposition.value == .performDefaultHandling)
    }

    @Test func doesNotOverrideANonServerTrustChallenge() {
        let (collector, _, session, task) = makeCollector(RequestSettings(validateTLS: false))
        defer { session.invalidateAndCancel() }
        let disposition = Box<URLSession.AuthChallengeDisposition?>(nil)
        collector.urlSession(
            session, task: task,
            didReceive: URLAuthenticationChallenge(
                protectionSpace: URLProtectionSpace(
                    host: "api.co", port: 443, protocol: "https", realm: nil,
                    authenticationMethod: NSURLAuthenticationMethodHTTPBasic
                ),
                proposedCredential: nil, previousFailureCount: 0, failureResponse: nil,
                error: nil, sender: NoopChallengeSender()
            ),
            completionHandler: { disposition.value = $0; _ = $1 }
        )
        #expect(disposition.value == .performDefaultHandling)
    }
}

// MARK: - Test helpers

private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: T

    init(_ value: T) { storage = value }

    var value: T {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }
}

private final class NoopChallengeSender: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
}

// MARK: - Mock transport

@Suite struct MockTransportTests {

    @Test func replaysQueuedResultsThenFallsBack() async throws {
        let transport = MockTransport(
            results: [
                .success(HttpTransportResult(statusCode: 201)),
                .failure(HttpTransportError.offline),
            ],
            fallback: HttpTransportResult(statusCode: 418)
        )
        let prepared = PreparedRequest(url: "https://a.co", method: .get, headers: [])

        #expect(try await transport.perform(prepared).statusCode == 201)
        await #expect(throws: HttpTransportError.offline) { try await transport.perform(prepared) }
        #expect(try await transport.perform(prepared).statusCode == 418)
        #expect(await transport.performed.count == 3)
    }

    @Test func recordsWhatItWasAskedToSend() async throws {
        let transport = MockTransport(status: 200, json: "{}")
        let prepared = PreparedRequest(
            url: "https://a.co/x", method: .post, headers: [(key: "X", value: "1")],
            body: Data("b".utf8)
        )
        _ = try await transport.perform(prepared)
        #expect(await transport.lastRequest == prepared)
    }
}
