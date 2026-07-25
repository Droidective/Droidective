import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A Chrome DevTools Protocol client over a single WebSocket — the transport for
/// the JS console. Connects to a target's `webSocketDebuggerUrl` (handed out by
/// `MetroInspector`), enables the `Runtime`/`Log` domains, evaluates
/// expressions, expands objects, and streams console + exception events.
///
/// Built on `URLSessionWebSocketTask` (Foundation — no dependency). The actor
/// owns the non-`Sendable` task and never lets it escape: every touch happens in
/// actor-isolated code. Request/response correlation is by integer `id`; a tiny
/// early-result buffer closes the window where a reply could land between
/// sending a request and registering its continuation.
public actor JSConsoleClient {
    public enum ClientError: Error, Sendable, LocalizedError {
        case notConnected
        case transport(String)

        public var errorDescription: String? {
            switch self {
            case .notConnected: "Not connected to a JavaScript target."
            case let .transport(detail): detail
            }
        }
    }

    /// Events streamed to the session as they arrive.
    public enum Event: Sendable {
        case console(ConsoleAPICall)
        case exception(ExceptionDetails, timestamp: Double?)
        case contextCreated(id: Int)
        case contextDestroyed
        /// `takeover`: the server closed us because another debugger attached
        /// to the same app — reconnecting automatically would steal it back.
        case closed(reason: String, takeover: Bool)
    }

    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var keepaliveTask: Task<Void, Never>?
    private var continuation: AsyncStream<Event>.Continuation?
    private var pending: [Int: CheckedContinuation<JSONValue?, Error>] = [:]
    private var earlyResults: [Int: Result<JSONValue?, Error>] = [:]
    /// Request ids whose replies are discarded on arrival (keepalives) instead
    /// of being stashed in `earlyResults` forever.
    private var ignoredIds: Set<Int> = []
    private var nextId = 1
    /// Bumped by every teardown. The receive loop, keepalive, and in-flight
    /// sends belong to the generation they started under; a stale one returns
    /// instead of touching a successor connection's state — without this, the
    /// old receive loop's close error (its socket is cancelled mid-`receive`
    /// during a reconnect) tore down the *new* connection and leaked its
    /// still-open socket, so Metro piled up zombie debugger connections.
    private var generation = 0

    public init() {}

    public var isConnected: Bool { task != nil }

    /// The WebSocket upgrade request for a debugger target. The React Native
    /// (Fusebox) inspector proxy rejects the connection with HTTP 401 unless the
    /// `Origin` header is the dev-server origin or a loopback hostname
    /// (`localhost` / `127.0.0.1` / `0.0.0.0`), so set it to `localhost` on the
    /// target's port — that satisfies the proxy's allowlist for every loopback
    /// form, and Hermes ignores the header on older React Native.
    public nonisolated static func debuggerRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("http://localhost:\(url.port ?? 8081)", forHTTPHeaderField: "Origin")
        return request
    }

    /// Open the WebSocket and enable the domains a console needs. Returns the
    /// event stream; it finishes when the connection closes or `disconnect()` is
    /// called. Re-entrant: a previous connection is torn down first. Throws if
    /// the connection can't be established (so the caller can retry), detected
    /// via `Runtime.enable` — `Log.enable` is best-effort for older peers. The
    /// handshake is bounded by `handshakeTimeout`: a proxy that accepts the
    /// socket for a dead page never answers `Runtime.enable`, and an unbounded
    /// wait would wedge the caller's reconnect loop.
    public func connect(
        to url: URL,
        handshakeTimeout: Duration = .seconds(10),
        keepaliveInterval: Duration = .seconds(10)
    ) async throws -> AsyncStream<Event> {
        teardown(reason: "reconnecting", notify: true)
        let task = URLSession.shared.webSocketTask(with: Self.debuggerRequest(for: url))
        // The default cap is 1 MiB, and a single CDP frame can far exceed it —
        // an app logging big objects trips it on the post-connect replay, the
        // socket dies with close code 1009 ("message too big"), and the
        // reconnect replays the same buffer: an endless connect/close loop.
        task.maximumMessageSize = 64 << 20
        self.task = task
        let generation = generation
        let (stream, continuation) = AsyncStream.makeStream(of: Event.self)
        self.continuation = continuation
        task.resume()
        startReceiveLoop(generation: generation)
        startKeepalive(generation: generation, interval: keepaliveInterval)
        let watchdog = Task { [weak self] in
            try? await Task.sleep(for: handshakeTimeout)
            guard !Task.isCancelled else { return }
            await self?.handshakeTimedOut(generation: generation)
        }
        defer { watchdog.cancel() }
        do {
            _ = try await send(method: "Runtime.enable", params: [:])
        } catch {
            if generation == self.generation { teardown(reason: "connect failed", notify: false) }
            throw error
        }
        _ = try? await send(method: "Log.enable", params: [:])
        return stream
    }

    /// The handshake outlasted its timeout: tear the connection down, which
    /// also fails the pending `Runtime.enable` and unblocks `connect`.
    private func handshakeTimedOut(generation: Int) {
        guard generation == self.generation else { return }
        teardown(reason: "Timed out waiting for the JS runtime.", notify: false)
    }

    public func evaluate(_ expression: String) async throws -> EvalOutcome {
        let result = try await send(method: "Runtime.evaluate", params: CDP.evaluateParams(expression: expression))
        return EvalOutcome.from(result: result)
    }

    /// A faithful deep-JSON rendering of an object, evaluated in the runtime via
    /// `callFunctionOn` — for "Copy as JSON". Returns nil on transport failure.
    public func deepStringify(objectId: String) async -> String? {
        let result = try? await send(
            method: "Runtime.callFunctionOn",
            params: CDP.callFunctionOnParams(objectId: objectId, functionDeclaration: CDP.deepStringifyFunction)
        )
        return result?["result"]?["value"]?.stringValue
    }

    /// A bounded pretty-JSON snapshot of an object for expanding it in the UI.
    /// Uses `callFunctionOn` (which returns a string) instead of `getProperties`
    /// (whose native RemoteObject converter crashes Hermes on some object
    /// graphs). Returns nil on transport failure.
    public func snapshotJSON(objectId: String) async -> String? {
        let result = try? await send(
            method: "Runtime.callFunctionOn",
            params: CDP.callFunctionOnParams(objectId: objectId, functionDeclaration: CDP.boundedSnapshotFunction)
        )
        return result?["result"]?["value"]?.stringValue
    }

    /// Ask the app to reload its JS bundle — the mechanism React Native
    /// DevTools' ⌘R uses: the app's inspector integration handles
    /// `Page.reload` itself, no `Page` domain enable needed. The reply is
    /// bounded by `replyTimeout` because a proxy relaying to a dead page never
    /// answers, and an unbounded wait would suspend the caller forever;
    /// runtimes without native reload support answer with a method-not-found
    /// error, which lands here as `ClientError.transport` so the caller can
    /// fall back to another mechanism.
    public func reloadPage(replyTimeout: Duration = .seconds(5)) async throws {
        let id = nextId
        let deadline = Task { [weak self] in
            try? await Task.sleep(for: replyTimeout)
            guard !Task.isCancelled else { return }
            await self?.resolve(id: id, .failure(ClientError.transport("Page.reload went unanswered.")))
        }
        defer { deadline.cancel() }
        _ = try await send(method: "Page.reload", params: [:])
    }

    /// Release the `console` object group — drops the device-side handles for
    /// everything evaluated/logged so far. Called when the console is cleared so
    /// remote objects don't accumulate. Best-effort.
    public func releaseConsoleObjects() async {
        _ = try? await send(method: "Runtime.releaseObjectGroup", params: CDP.releaseObjectGroupParams("console"))
    }

    public func disconnect() {
        teardown(reason: "disconnected", notify: true)
    }

    // MARK: - Request / response

    private func send(method: String, params: [String: JSONValue]) async throws -> JSONValue? {
        guard let task else { throw ClientError.notConnected }
        let generation = generation
        let id = nextId
        nextId += 1
        let envelope = CDP.request(id: id, method: method, params: params)
        guard let data = try? JSONEncoder().encode(envelope) else {
            throw ClientError.transport("Couldn't encode \(method).")
        }
        // Send first, then register the continuation. The send's suspension
        // releases the actor, so the reply can arrive before we register — the
        // receive loop stashes it in `earlyResults` and we pick it up below.
        do {
            try await task.send(.string(String(decoding: data, as: UTF8.self)))
            NetworkTrafficMeter.shared.recordSent(data.count)
        } catch {
            throw ClientError.transport("\(error.localizedDescription)")
        }
        return try await withCheckedThrowingContinuation { continuation in
            if let early = earlyResults.removeValue(forKey: id) {
                continuation.resume(with: early)
            } else if generation == self.generation, self.task != nil {
                pending[id] = continuation
            } else {
                // The connection this request went out on closed (or was
                // replaced) during the send await — its `pending` map was
                // drained, so nothing would ever resume this.
                continuation.resume(throwing: ClientError.notConnected)
            }
        }
    }

    private func resolve(id: Int, _ result: Result<JSONValue?, Error>) {
        if ignoredIds.remove(id) != nil { return }
        if let continuation = pending.removeValue(forKey: id) {
            continuation.resume(with: result)
        } else {
            earlyResults[id] = result
        }
    }

    // MARK: - Receive loop

    private func startReceiveLoop(generation: Int) {
        receiveTask = Task { [weak self] in
            await self?.receiveLoop(generation: generation)
        }
    }

    /// Reads until the socket dies. Every touch of actor state is gated on the
    /// generation: cancelling this loop's socket suspends-then-throws its
    /// `receive()`, and by the time that error lands a reconnect may already
    /// own `task`/`continuation` — a stale loop must return, not "close" the
    /// successor.
    private func receiveLoop(generation: Int) async {
        while !Task.isCancelled {
            guard generation == self.generation, let task else { return }
            do {
                let message = try await task.receive()
                guard generation == self.generation else { return }
                handle(message)
            } catch {
                if generation == self.generation {
                    let close = Self.closeDescription(for: task, fallback: error.localizedDescription)
                    handleClosed(close.reason, takeover: close.takeover)
                }
                return
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case let .string(text): data = Data(text.utf8)
        case let .data(payload): data = payload
        @unknown default: return
        }
        NetworkTrafficMeter.shared.recordReceived(data.count)
        guard let incoming = CDP.parseIncoming(data) else { return }
        switch incoming {
        case let .response(id, result, error):
            if let error {
                resolve(id: id, .failure(ClientError.transport(error.message)))
            } else {
                resolve(id: id, .success(result))
            }
        case let .event(method, params):
            emit(method: method, params: params)
        }
    }

    private func emit(method: String, params: JSONValue) {
        switch method {
        case "Runtime.consoleAPICalled":
            continuation?.yield(.console(ConsoleAPICall(params: params)))
        case "Runtime.exceptionThrown":
            if let details = params["exceptionDetails"] {
                continuation?.yield(.exception(
                    ExceptionDetails(json: details),
                    timestamp: params["timestamp"]?.doubleValue
                ))
            }
        case "Runtime.executionContextCreated":
            if let id = params["context"]?["id"]?.intValue {
                continuation?.yield(.contextCreated(id: id))
            }
        case "Runtime.executionContextDestroyed":
            continuation?.yield(.contextDestroyed)
        default:
            break
        }
    }

    private func handleClosed(_ reason: String, takeover: Bool = false) {
        guard continuation != nil else { return }
        generation += 1
        cancelTasks()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        failPending(ClientError.transport(reason))
        continuation?.yield(.closed(reason: reason, takeover: takeover))
        continuation?.finish()
        continuation = nil
    }

    /// A human close description plus whether another debugger took the target
    /// over. The server's close reason (when it sent a close frame at all —
    /// the proxy's heartbeat kill is an abrupt `terminate()` with none) beats
    /// the transport error's generic wording.
    private nonisolated static func closeDescription(
        for task: URLSessionWebSocketTask, fallback: String
    ) -> (reason: String, takeover: Bool) {
        let reasonText = task.closeReason.map { String(decoding: $0, as: UTF8.self) } ?? ""
        return (reasonText.isEmpty ? fallback : reasonText, isDebuggerTakeover(reasonText))
    }

    /// Whether a server close reason means another debugger attached to our
    /// target — dev-middleware's "[NEW_DEBUGGER_OPENED] New debugger opened for
    /// the same app instance" (RN 0.76+) or the legacy proxy's "Another
    /// debugger is already connected". Auto-reconnecting after one of these
    /// would kick that debugger straight back off, so the session must not.
    public nonisolated static func isDebuggerTakeover(_ closeReason: String) -> Bool {
        let lowered = closeReason.lowercased()
        return lowered.contains("new_debugger") || lowered.contains("another debugger")
    }

    // MARK: - Keepalive

    /// React Native's inspector proxy pings each debugger socket and abruptly
    /// `terminate()`s any that delivers neither a pong nor a data message
    /// within its window (60s of 5s pings on current dev-middleware; older
    /// releases were tighter). Pong replies are CFNetwork's business and a
    /// client-initiated WebSocket ping doesn't refresh the proxy's timer at
    /// all — the only liveness signal fully under our control is a real CDP
    /// message, so send a tiny silent no-op evaluate well inside the window.
    /// Pacing is by the timer, not the reply (which is discarded via
    /// `ignoredIds`), so a wedged JS thread can't stall the keepalive and let
    /// the proxy kill a healthy socket.
    private func startKeepalive(generation: Int, interval: Duration) {
        keepaliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                if Task.isCancelled { return }
                guard await self?.sendKeepalive(generation: generation) == true else { return }
            }
        }
    }

    private func sendKeepalive(generation: Int) -> Bool {
        guard generation == self.generation, let task else { return false }
        let id = nextId
        nextId += 1
        ignoredIds.insert(id)
        let envelope = CDP.request(id: id, method: "Runtime.evaluate", params: CDP.keepaliveParams())
        guard let data = try? JSONEncoder().encode(envelope) else { return false }
        task.send(.string(String(decoding: data, as: UTF8.self))) { [weak self] error in
            guard error != nil else { return }
            Task { await self?.keepaliveFailed(generation: generation) }
        }
        NetworkTrafficMeter.shared.recordSent(data.count)
        return true
    }

    /// The keepalive couldn't even be written to the socket — the transport is
    /// gone. Close now so reconnection starts immediately instead of waiting
    /// out the peer's timeout.
    private func keepaliveFailed(generation: Int) {
        guard generation == self.generation else { return }
        handleClosed("The connection stopped accepting messages.")
    }

    // MARK: - Teardown

    private func cancelTasks() {
        receiveTask?.cancel()
        receiveTask = nil
        keepaliveTask?.cancel()
        keepaliveTask = nil
    }

    /// Close the current connection. `notify` yields a final `.closed` so a
    /// still-attached consumer (e.g. when a stray disconnect races a fresh
    /// connection) learns the stream is over instead of waiting forever on a
    /// silently-finished feed.
    private func teardown(reason: String, notify: Bool) {
        generation += 1
        cancelTasks()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        failPending(ClientError.notConnected)
        if notify { continuation?.yield(.closed(reason: reason, takeover: false)) }
        continuation?.finish()
        continuation = nil
    }

    private func failPending(_ error: Error) {
        let waiting = pending.values
        pending.removeAll()
        earlyResults.removeAll()
        ignoredIds.removeAll()
        for continuation in waiting {
            continuation.resume(throwing: error)
        }
    }
}
