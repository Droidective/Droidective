import Foundation
import Testing

@testable import ADBKit

/// Exercises `URLSessionTransport` against a real socket. Everything else in the
/// API-client suite mocks the transport, so this is the only place the redirect
/// policy, cookie handling, byte cap and timeout are proven end to end.
///
/// Gated like the other device-dependent suites: `API_LIVE_TEST=1 swift test`.
@Suite(.serialized)
struct ApiTransportLiveTests {

    static var enabled: Bool {
        ProcessInfo.processInfo.environment["API_LIVE_TEST"] == "1"
    }

    private func send(
        _ request: SavedRequest, on server: LocalHTTPServer
    ) async throws -> ApiResponse {
        var request = request
        request.url = server.url(request.url)
        let client = HttpClientService(transport: URLSessionTransport())
        return try await client.send(request).response
    }

    @Test(.enabled(if: enabled))
    func plainHTTPToLoopbackSucceeds() async throws {
        let server = try LocalHTTPServer()
        defer { server.stop() }
        let response = try await send(SavedRequest(url: "/json"), on: server)
        #expect(response.statusCode == 200)
        #expect(response.isJSON)
        #expect(JSONProbe.probe("ok", in: response.body) == .bool(true))
        #expect(response.elapsedMs > 0)
    }

    @Test(.enabled(if: enabled))
    func reportsTimingBreakdown() async throws {
        let server = try LocalHTTPServer()
        defer { server.stop() }
        let response = try await send(SavedRequest(url: "/json"), on: server)
        let timing = try #require(response.timing)
        #expect(timing.total > 0)
    }

    @Test(.enabled(if: enabled))
    func parsesResponseCookies() async throws {
        let server = try LocalHTTPServer()
        defer { server.stop() }
        let response = try await send(SavedRequest(url: "/cookie"), on: server)
        let cookie = try #require(response.cookies.first { $0.name == "sid" })
        #expect(cookie.value == "abc123")
        #expect(cookie.httpOnly)
        #expect(cookie.path == "/")
    }

    @Test(.enabled(if: enabled))
    func followsARedirectAndRecordsTheHop() async throws {
        let server = try LocalHTTPServer()
        defer { server.stop() }
        let response = try await send(SavedRequest(url: "/redirect"), on: server)
        #expect(response.statusCode == 200)
        #expect(response.redirects.count == 1)
        #expect(response.redirects[0].statusCode == 302)
        #expect(response.finalURL.hasSuffix("/json"))
    }

    @Test(.enabled(if: enabled))
    func stopsAtTheRedirectWhenFollowingIsOff() async throws {
        let server = try LocalHTTPServer()
        defer { server.stop() }
        let response = try await send(
            SavedRequest(url: "/redirect", settings: RequestSettings(followRedirects: false)),
            on: server
        )
        #expect(response.statusCode == 302)
        #expect(response.headerValue("Location") != nil)
    }

    @Test(.enabled(if: enabled))
    func truncatesABodyPastTheCap() async throws {
        let server = try LocalHTTPServer()
        defer { server.stop() }
        let response = try await send(
            SavedRequest(url: "/big", settings: RequestSettings(maxResponseBytes: 4096)),
            on: server
        )
        #expect(response.truncated)
        #expect(response.body.count <= 4096)
        #expect(response.size > 4096)
    }

    @Test(.enabled(if: enabled))
    func sendsAJSONBodyAndReadsItBack() async throws {
        let server = try LocalHTTPServer()
        defer { server.stop() }
        let response = try await send(
            SavedRequest(
                method: .post,
                url: "/echo",
                headers: [ApiKeyValue(key: "X-Trace", value: "t1")],
                body: RequestBodySpec(type: .json, jsonText: #"{"name":"widget"}"#)
            ),
            on: server
        )
        #expect(response.statusCode == 200)
        #expect(JSONProbe.probe("method", in: response.body) == .string("POST"))
        #expect(JSONProbe.probe("body", in: response.body) == .string(#"{"name":"widget"}"#))
        #expect(JSONProbe.probe("headers.x-trace", in: response.body) == .string("t1"))
        #expect(
            JSONProbe.probe("headers.content-type", in: response.body)
                == .string("application/json")
        )
    }

    @Test(.enabled(if: enabled))
    func sendsAMultipartBody() async throws {
        let server = try LocalHTTPServer()
        defer { server.stop() }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("api-live-\(UUID().uuidString).txt")
        try Data("file-bytes".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let response = try await send(
            SavedRequest(
                method: .post,
                url: "/echo",
                body: RequestBodySpec(
                    type: .multipart,
                    multipartFields: [
                        ApiFormField(key: "note", value: "hi"),
                        ApiFormField(key: "doc", value: file.path, kind: .file),
                    ]
                )
            ),
            on: server
        )
        let body = try #require(JSONProbe.probe("body", in: response.body)?.stringValue)
        #expect(body.contains("name=\"note\""))
        #expect(body.contains("file-bytes"))
        #expect(
            JSONProbe.probe("headers.content-type", in: response.body)?
                .stringValue.contains("multipart/form-data; boundary=") == true
        )
    }

    @Test(.enabled(if: enabled))
    func surfacesAServerErrorAsAResponseNotAThrow() async throws {
        let server = try LocalHTTPServer()
        defer { server.stop() }
        let response = try await send(SavedRequest(url: "/status/503"), on: server)
        #expect(response.statusCode == 503)
        #expect(response.statusText == "Service Unavailable")
        #expect(!response.isSuccess)
    }

    @Test(.enabled(if: enabled))
    func timesOutWithAnActionableMessage() async throws {
        let server = try LocalHTTPServer()
        defer { server.stop() }
        var request = SavedRequest(url: "/slow", settings: RequestSettings(timeoutSeconds: 1))
        request.url = server.url(request.url)
        let client = HttpClientService(transport: URLSessionTransport())
        await #expect(throws: HttpTransportError.timedOut(1)) {
            try await client.send(request)
        }
    }

    /// The everyday case: a dev server that isn't running. Deliberately outside
    /// `LocalHTTPServer`'s port range so a just-stopped server can't answer.
    @Test(.enabled(if: enabled))
    func refusesAClosedPort() async {
        var request = SavedRequest(url: "http://127.0.0.1:39117/nothing")
        request.settings.timeoutSeconds = 5
        let client = HttpClientService(transport: URLSessionTransport())
        await #expect(throws: HttpTransportError.connectionFailed) {
            try await client.send(request)
        }
    }

    @Test(.enabled(if: enabled))
    func cancellingMidFlightStopsTheRequest() async throws {
        let server = try LocalHTTPServer()
        defer { server.stop() }
        var request = SavedRequest(url: "/slow")
        request.url = server.url(request.url)
        let client = HttpClientService(transport: URLSessionTransport())
        let task = Task { try await client.send(request) }
        try await Task.sleep(for: .milliseconds(150))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

// MARK: - Local server

/// A throwaway HTTP server for the live suite, run as a child `python3`.
/// Python is present on every macOS and Linux box the suite runs on, which beats
/// hand-rolling a socket listener here.
final class LocalHTTPServer {
    let port: Int
    private let process: Process
    private let scriptURL: URL

    init() throws {
        port = Int.random(in: 41000...48000)
        scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("droidective-api-test-\(UUID().uuidString).py")
        try Data(LocalHTTPServer.script.utf8).write(to: scriptURL)

        process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", scriptURL.path, String(port)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        try waitUntilReady()
    }

    func url(_ path: String) -> String {
        path.hasPrefix("http") ? path : "http://127.0.0.1:\(port)\(path)"
    }

    func stop() {
        process.terminate()
        try? FileManager.default.removeItem(at: scriptURL)
    }

    private func waitUntilReady() throws {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if canConnect() { return }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw LocalServerError.neverStarted
    }

    private func canConnect() -> Bool {
        let reachable = Flag()
        let semaphore = DispatchSemaphore(value: 0)
        let task = URLSession.shared.dataTask(with: URL(string: url("/json"))!) { _, response, _ in
            reachable.value = (response as? HTTPURLResponse) != nil
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 1)
        task.cancel()
        return reachable.value
    }

    /// The probe's result crosses out of URLSession's callback queue.
    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = false

        var value: Bool {
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

    enum LocalServerError: Error { case neverStarted }

    static let script = """
        import json, sys, time
        from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def log_message(self, *args):
                pass

            def respond(self, code, body=b"", headers=None):
                self.send_response(code)
                for key, value in (headers or {}).items():
                    self.send_header(key, value)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                if body:
                    self.wfile.write(body)

            def handle_path(self, body=b""):
                path = self.path
                if path.startswith("/json"):
                    payload = json.dumps({"ok": True, "n": 1}).encode()
                    self.respond(200, payload, {"Content-Type": "application/json"})
                elif path.startswith("/cookie"):
                    self.respond(
                        200,
                        b"{}",
                        {
                            "Content-Type": "application/json",
                            "Set-Cookie": "sid=abc123; Path=/; HttpOnly",
                        },
                    )
                elif path.startswith("/redirect"):
                    self.respond(302, b"", {"Location": "/json"})
                elif path.startswith("/big"):
                    self.respond(200, b"x" * 200000, {"Content-Type": "text/plain"})
                elif path.startswith("/slow"):
                    time.sleep(6)
                    self.respond(200, b"late")
                elif path.startswith("/status/"):
                    try:
                        code = int(path.rsplit("/", 1)[1])
                    except ValueError:
                        code = 500
                    self.respond(code, b"{}", {"Content-Type": "application/json"})
                elif path.startswith("/echo"):
                    payload = json.dumps(
                        {
                            "method": self.command,
                            "path": path,
                            "headers": {k.lower(): v for k, v in self.headers.items()},
                            "body": body.decode("utf-8", "replace"),
                        }
                    ).encode()
                    self.respond(200, payload, {"Content-Type": "application/json"})
                else:
                    self.respond(404, b"{}", {"Content-Type": "application/json"})

            def do_GET(self):
                self.handle_path()

            def do_HEAD(self):
                self.handle_path()

            def read_body(self):
                length = int(self.headers.get("Content-Length") or 0)
                return self.rfile.read(length) if length else b""

            def do_POST(self):
                self.handle_path(self.read_body())

            def do_PUT(self):
                self.handle_path(self.read_body())

            def do_PATCH(self):
                self.handle_path(self.read_body())

            def do_DELETE(self):
                self.handle_path(self.read_body())

        ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
        """
}
