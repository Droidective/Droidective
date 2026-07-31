import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

// MARK: - Transport seam

public struct HttpTransportResult: Sendable {
    public var statusCode: Int
    public var headers: [(key: String, value: String)]
    public var body: Data
    /// Total bytes the server sent, even when `body` was capped.
    public var receivedBytes: Int
    public var truncated: Bool
    public var redirects: [RedirectHop]
    public var timing: ApiTiming?
    public var finalURL: String

    public init(
        statusCode: Int,
        headers: [(key: String, value: String)] = [],
        body: Data = Data(),
        receivedBytes: Int? = nil,
        truncated: Bool = false,
        redirects: [RedirectHop] = [],
        timing: ApiTiming? = nil,
        finalURL: String = ""
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
        self.receivedBytes = receivedBytes ?? body.count
        self.truncated = truncated
        self.redirects = redirects
        self.timing = timing
        self.finalURL = finalURL
    }
}

/// The one place this feature touches the network. Mirrors `ProcessRunning`:
/// a protocol so every layer above it is testable without a socket.
public protocol HttpTransport: Sendable {
    func perform(_ prepared: PreparedRequest) async throws -> HttpTransportResult
}

// MARK: - Errors

public enum HttpTransportError: Error, LocalizedError, Sendable, Equatable {
    case notHTTP
    case offline
    case hostNotFound(String)
    /// Nothing answered, or the connection dropped before a response arrived.
    /// URLSession reports both as -1004/-1005 inconsistently, so they share one
    /// message rather than guessing which happened.
    case connectionFailed
    case timedOut(Double)
    case tlsFailure(String)
    case tooManyRedirects(Int)
    case insecureUnsupported
    case other(code: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .notHTTP:
            return "The server answered with something that isn't an HTTP response."
        case .offline:
            return "No internet connection."
        case .hostNotFound(let host):
            return "Can't find \(host). Check the hostname or your DNS."
        case .connectionFailed:
            return "Couldn't reach that address. Check the server is running and the port is right."
        case .timedOut(let seconds):
            return "No response within \(Int(seconds))s. Raise the timeout in Settings if the endpoint is slow."
        case .tlsFailure(let detail):
            return "TLS failed: \(detail). For a self-signed certificate, turn off certificate validation in Settings."
        case .tooManyRedirects(let limit):
            return "Stopped after \(limit) redirects."
        case .insecureUnsupported:
            return "Skipping certificate validation isn't available on this platform."
        case .other(let code, let message):
            return code == 0 ? message : "\(message) (\(code))"
        }
    }
}

// MARK: - URLSession transport

public struct URLSessionTransport: HttpTransport {
    public init() {}

    public func perform(_ prepared: PreparedRequest) async throws -> HttpTransportResult {
        let request = try Self.urlRequest(from: prepared)
        let collector = ResponseCollector(settings: prepared.settings)
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = prepared.settings.effectiveTimeout
        configuration.timeoutIntervalForResource = prepared.settings.effectiveTimeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = prepared.settings.sendCookies
        configuration.httpCookieAcceptPolicy = prepared.settings.sendCookies ? .always : .never
        let session = URLSession(configuration: configuration, delegate: collector, delegateQueue: nil)

        let start = ContinuousClock.now
        do {
            let result = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    collector.finish = { outcome in continuation.resume(with: outcome) }
                    let task = session.dataTask(with: request)
                    if collector.adopt(task) {
                        task.resume()
                    } else {
                        collector.complete(with: .failure(CancellationError()))
                    }
                }
            } onCancel: {
                collector.cancel()
            }
            session.finishTasksAndInvalidate()
            let elapsed = Self.milliseconds(since: start)
            return result.withTiming(fallbackTotal: elapsed)
        } catch {
            session.invalidateAndCancel()
            if error is CancellationError { throw error }
            throw Self.mapped(error, timeout: prepared.settings.effectiveTimeout)
        }
    }

    static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = start.duration(to: ContinuousClock.now)
        return Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
    }

    // MARK: URLRequest

    static func urlRequest(from prepared: PreparedRequest) throws -> URLRequest {
        // `URL(string:)` happily returns a scheme-less relative URL, which would
        // become a nonsense request. The builder always supplies a scheme; this
        // re-checks it so a `PreparedRequest` built by hand can't slip through.
        guard let url = URL(string: prepared.url),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false
        else {
            throw ApiRequestError.invalidURL(prepared.url)
        }
        var request = URLRequest(url: url)
        request.httpMethod = prepared.method.rawValue
        request.timeoutInterval = prepared.settings.effectiveTimeout
        request.httpShouldHandleCookies = prepared.settings.sendCookies
        request.cachePolicy = .reloadIgnoringLocalCacheData
        // `addValue` rather than `setValue` so repeated headers survive.
        for header in prepared.headers {
            request.addValue(header.value, forHTTPHeaderField: header.key)
        }
        request.httpBody = prepared.body
        return request
    }

    // MARK: Error mapping

    static func mapped(_ error: any Error, timeout: Double) -> any Error {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return error }
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorDataNotAllowed:
            return HttpTransportError.offline
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            let host = nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String
            return HttpTransportError.hostNotFound(
                host.flatMap { URL(string: $0)?.host } ?? "that host"
            )
        case NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost:
            return HttpTransportError.connectionFailed
        case NSURLErrorTimedOut:
            return HttpTransportError.timedOut(timeout)
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted,
            NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateNotYetValid,
            NSURLErrorServerCertificateHasUnknownRoot, NSURLErrorClientCertificateRejected,
            NSURLErrorClientCertificateRequired:
            return HttpTransportError.tlsFailure(nsError.localizedDescription)
        case NSURLErrorCancelled:
            return CancellationError()
        case NSURLErrorHTTPTooManyRedirects:
            return HttpTransportError.tooManyRedirects(0)
        default:
            return HttpTransportError.other(
                code: nsError.code, message: nsError.localizedDescription
            )
        }
    }
}

extension HttpTransportResult {
    func withTiming(fallbackTotal: Double) -> HttpTransportResult {
        guard timing == nil else { return self }
        var copy = self
        copy.timing = ApiTiming(total: fallbackTotal)
        return copy
    }
}

// MARK: - Delegate

/// Accumulates the response, enforcing the byte cap and the redirect policy.
///
/// `@unchecked Sendable` with an explicit lock: URLSession calls these methods
/// on its own queue, and the continuation must be resumed exactly once no matter
/// which callback gets there first.
final class ResponseCollector: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let settings: RequestSettings

    private var task: URLSessionTask?
    private var cancelledByUser = false
    private var stoppedForSize = false
    private var finished = false

    private var statusCode = 0
    private var headers: [(key: String, value: String)] = []
    private var body = Data()
    private var receivedBytes = 0
    private var redirects: [RedirectHop] = []
    private var timing: ApiTiming?
    private var finalURL = ""

    var finish: (@Sendable (Result<HttpTransportResult, any Error>) -> Void)?

    init(settings: RequestSettings) {
        self.settings = settings
        super.init()
    }

    /// Returns false when the caller was already cancelled, so the task is
    /// never started at all.
    func adopt(_ task: URLSessionTask) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelledByUser else { return false }
        self.task = task
        return true
    }

    func cancel() {
        lock.lock()
        cancelledByUser = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }

    func complete(with outcome: Result<HttpTransportResult, any Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let handler = finish
        lock.unlock()
        handler?(outcome)
    }

    // MARK: Response

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse else {
            complete(with: .failure(HttpTransportError.notHTTP))
            completionHandler(.cancel)
            return
        }
        lock.lock()
        statusCode = http.statusCode
        headers = ResponseCollector.headerPairs(from: http)
        finalURL = http.url?.absoluteString ?? ""
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        receivedBytes += data.count
        let cap = settings.effectiveMaxResponseBytes
        if body.count < cap {
            let room = cap - body.count
            body.append(room >= data.count ? data : data.prefix(room))
        }
        let exceeded = receivedBytes > cap
        if exceeded, !stoppedForSize {
            stoppedForSize = true
            let task = self.task
            lock.unlock()
            task?.cancel()
            return
        }
        lock.unlock()
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?
    ) {
        lock.lock()
        let truncated = stoppedForSize
        let userCancelled = cancelledByUser
        let snapshot = HttpTransportResult(
            statusCode: statusCode,
            headers: headers,
            body: body,
            receivedBytes: receivedBytes,
            truncated: truncated,
            redirects: redirects,
            timing: timing,
            finalURL: finalURL
        )
        lock.unlock()

        if let error {
            let nsError = error as NSError
            let wasCancel = nsError.domain == NSURLErrorDomain
                && nsError.code == NSURLErrorCancelled
            // A cancel we issued to enforce the byte cap is a success, not a failure.
            if wasCancel, truncated, !userCancelled {
                complete(with: .success(snapshot))
                return
            }
            complete(with: .failure(error))
            return
        }
        complete(with: .success(snapshot))
    }

    // MARK: Redirects

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        lock.lock()
        redirects.append(
            RedirectHop(
                statusCode: response.statusCode,
                from: response.url?.absoluteString ?? "",
                to: request.url?.absoluteString ?? ""
            )
        )
        let count = redirects.count
        // The 3xx itself is the answer when redirects are off, so keep the
        // headers already recorded and stop here.
        if !settings.followRedirects {
            statusCode = response.statusCode
            headers = ResponseCollector.headerPairs(from: response)
            finalURL = response.url?.absoluteString ?? ""
            lock.unlock()
            completionHandler(nil)
            return
        }
        lock.unlock()

        guard count <= settings.effectiveMaxRedirects else {
            complete(with: .failure(HttpTransportError.tooManyRedirects(settings.effectiveMaxRedirects)))
            task.cancel()
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    // MARK: TLS

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard !settings.validateTLS,
              challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        #if canImport(Darwin)
            guard let trust = challenge.protectionSpace.serverTrust else {
                completionHandler(.performDefaultHandling, nil)
                return
            }
            completionHandler(.useCredential, URLCredential(trust: trust))
        #else
            // corelibs-foundation exposes no trust object to override.
            completionHandler(.performDefaultHandling, nil)
        #endif
    }

    // MARK: Metrics

    #if canImport(Darwin)
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didFinishCollecting metrics: URLSessionTaskMetrics
        ) {
            guard let last = metrics.transactionMetrics.last else { return }
            func span(_ from: Date?, _ to: Date?) -> Double? {
                guard let from, let to else { return nil }
                return to.timeIntervalSince(from) * 1000
            }
            lock.lock()
            timing = ApiTiming(
                dns: span(last.domainLookupStartDate, last.domainLookupEndDate),
                connect: span(last.connectStartDate, last.connectEndDate),
                tls: span(last.secureConnectionStartDate, last.secureConnectionEndDate),
                firstByte: span(last.requestStartDate, last.responseStartDate),
                total: metrics.taskInterval.duration * 1000
            )
            lock.unlock()
        }
    #endif

    static func headerPairs(from response: HTTPURLResponse) -> [(key: String, value: String)] {
        var pairs: [(key: String, value: String)] = []
        for (key, value) in response.allHeaderFields {
            guard let name = key as? String else { continue }
            pairs.append((key: name, value: String(describing: value)))
        }
        return pairs.sorted { $0.key.lowercased() < $1.key.lowercased() }
    }
}

// MARK: - Test double

/// Scripted transport for tests: records what was prepared and replays canned
/// results in order.
public actor MockTransport: HttpTransport {
    public private(set) var performed: [PreparedRequest] = []
    private var queued: [Result<HttpTransportResult, any Error>]
    private let fallback: HttpTransportResult

    public init(
        results: [Result<HttpTransportResult, any Error>] = [],
        fallback: HttpTransportResult = HttpTransportResult(statusCode: 200)
    ) {
        self.queued = results
        self.fallback = fallback
    }

    public init(status: Int, json: String) {
        self.queued = []
        self.fallback = HttpTransportResult(
            statusCode: status,
            headers: [(key: "Content-Type", value: "application/json")],
            body: Data(json.utf8)
        )
    }

    public func enqueue(_ result: HttpTransportResult) { queued.append(.success(result)) }

    public func enqueue(error: any Error) { queued.append(.failure(error)) }

    public func perform(_ prepared: PreparedRequest) async throws -> HttpTransportResult {
        performed.append(prepared)
        guard !queued.isEmpty else { return fallback }
        return try queued.removeFirst().get()
    }

    public var lastRequest: PreparedRequest? { performed.last }
}
