import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One call frame after Metro resolved it back through the bundle's source map.
public struct SymbolicatedFrame: Sendable, Equatable, Identifiable {
    public var id: String { "\(file):\(lineNumber):\(column):\(methodName)" }
    public let file: String
    /// 1-based, as Metro reports it (and as an editor counts).
    public let lineNumber: Int
    public let column: Int
    public let methodName: String
    /// Metro's own ignore-list flag — framework plumbing between the app's code
    /// and the console call, which Chrome hides for the same reason.
    public let collapse: Bool

    public init(file: String, lineNumber: Int, column: Int, methodName: String, collapse: Bool) {
        self.file = file
        self.lineNumber = lineNumber
        self.column = column
        self.methodName = methodName
        self.collapse = collapse
    }

    /// `emitComplexError  StreamScreen.tsx:192` — one stack line.
    public var display: String {
        let method = methodName.isEmpty ? "(anonymous)" : methodName
        return "\(method)  \(MetroSymbolicator.fileName(file)):\(lineNumber)"
    }

    /// Whether this frame is plumbing rather than the reader's own code —
    /// Metro's own flag, or a dependency's file. Drawn dimmer, the way Chrome
    /// greys its ignore-listed frames.
    public var isLibrary: Bool { collapse || MetroSymbolicator.isDependency(file) }
}

/// Where a console call came from — what Chrome prints, right-aligned, at the
/// end of every console row.
public struct ConsoleSourceLocation: Sendable, Equatable {
    /// Absolute path on the Mac running Metro.
    public let file: String
    public let line: Int
    public let function: String

    public init(file: String, line: Int, function: String) {
        self.file = file
        self.line = line
        self.function = function
    }

    /// `StreamScreen.tsx:142` — the file's own name and its line.
    public var label: String {
        "\(MetroSymbolicator.fileName(file)):\(line)"
    }
}

/// Resolves a console call's bundle coordinates back to the file the developer
/// wrote, through Metro's `/symbolicate` endpoint — the same service React
/// Native's redbox uses, so nothing here has to parse a source map.
///
/// Chrome's console shows this at the right edge of every row. Two rules make it
/// read the same way here: line numbers cross the wire 1-based (CDP counts from
/// zero), and the frame shown is the first one the *app* owns — Metro flags its
/// own plumbing with `collapse`, and anything under `node_modules` is a library
/// the reader didn't write, which is exactly Chrome's ignore-list default.
///
/// The actor is a cache in front of the endpoint: identical stacks (the common
/// case — a console call in a loop) resolve once, concurrent asks for the same
/// stack share one request, and a Metro that can't symbolicate at all stops
/// being asked after a few failures rather than costing a request per row.
public actor MetroSymbolicator {
    private let host: String
    private let port: Int
    private let timeout: TimeInterval
    /// Resolved (or definitively unresolvable) stacks, keyed by the frames sent.
    private var cache: [String: [SymbolicatedFrame]] = [:]
    /// Requests in flight, so N rows asking for the same stack make one call.
    private var inFlight: [String: Task<[SymbolicatedFrame], Never>] = [:]
    /// Consecutive transport failures — a Metro too old to symbolicate, or one
    /// that went away, must not be asked once per rendered row.
    private var failures = 0
    private var maximumCacheEntries = 512

    private static let failureLimit = 3

    public init(host: String = "127.0.0.1", port: Int = 8081, timeout: TimeInterval = 8) {
        self.host = host
        self.port = port
        self.timeout = timeout
    }

    /// A console call's stack resolved back to source: `location(in:)` picks the
    /// one frame the row labels itself with, and the whole list is what opening
    /// the row shows instead of eight repetitions of the bundle URL. Empty when
    /// there's nothing to resolve or Metro can't — never throws, because a
    /// missing source label is a cosmetic loss and the console keeps streaming.
    public func symbolicate(_ frames: [CDPCallFrame]) async -> [SymbolicatedFrame] {
        let sendable = Self.sendableFrames(frames)
        guard !sendable.isEmpty, failures < Self.failureLimit else { return [] }
        let key = Self.cacheKey(sendable)
        if let cached = cache[key] { return cached }
        if let running = inFlight[key] { return await running.value }
        let task = Task<[SymbolicatedFrame], Never> { [weak self] in
            guard let self else { return [] }
            return await self.resolve(sendable, key: key)
        }
        inFlight[key] = task
        return await task.value
    }

    private func resolve(_ frames: [CDPCallFrame], key: String) async -> [SymbolicatedFrame] {
        defer { inFlight[key] = nil }
        guard let url = URL(string: "http://\(host):\(port)/symbolicate") else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.requestBody(frames)
        let data: Data
        do {
            let (payload, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                failures += 1
                return []
            }
            data = payload
        } catch {
            failures += 1
            return []
        }
        failures = 0
        let resolved = Self.parse(data)
        // The call sites of a console stream are few; a runaway one still can't
        // grow the cache without bound. Dropping it whole beats an LRU nobody
        // would ever exercise.
        if cache.count >= maximumCacheEntries { cache.removeAll(keepingCapacity: true) }
        cache[key] = resolved
        return resolved
    }

    // MARK: - Pure

    /// The frames worth sending: those with a real script URL, capped — Metro
    /// resolves the whole stack, and only the top few can be the app's own call.
    public static func sendableFrames(_ frames: [CDPCallFrame], limit: Int = 8) -> [CDPCallFrame] {
        frames.filter { !$0.url.isEmpty }.prefix(limit).map { $0 }
    }

    public static func cacheKey(_ frames: [CDPCallFrame]) -> String {
        frames.map { "\($0.url)|\($0.lineNumber)|\($0.columnNumber)" }.joined(separator: "\n")
    }

    /// Metro's request shape. CDP counts lines from zero and Metro from one, so
    /// every line crosses the wire incremented — off by one here silently
    /// reports the wrong source line rather than failing.
    public static func requestBody(_ frames: [CDPCallFrame]) -> Data {
        var stack: [JSONValue] = []
        for frame in frames {
            let method: String = frame.functionName.isEmpty ? "(anonymous)" : frame.functionName
            let fields: [String: JSONValue] = [
                "file": .string(frame.url),
                "lineNumber": .number(Double(frame.lineNumber + 1)),
                "column": .number(Double(frame.columnNumber)),
                "methodName": .string(method),
            ]
            stack.append(.object(fields))
        }
        let body: JSONValue = .object(["stack": .array(stack)])
        return Data(body.jsonString.utf8)
    }

    public static func parse(_ data: Data) -> [SymbolicatedFrame] {
        guard let root = try? JSONDecoder().decode(JSONValue.self, from: data),
              let stack = root["stack"]?.arrayValue else { return [] }
        return stack.compactMap { entry in
            guard let file = entry["file"]?.stringValue, !file.isEmpty,
                  let line = entry["lineNumber"]?.intValue else { return nil }
            return SymbolicatedFrame(
                file: file,
                lineNumber: line,
                column: entry["column"]?.intValue ?? 0,
                methodName: entry["methodName"]?.stringValue ?? "",
                collapse: entry["collapse"]?.boolValue ?? false
            )
        }
    }

    /// The frame to show: the first one the app owns. Metro marks React
    /// Native's own console plumbing `collapse`, and a `node_modules` path is a
    /// dependency's code — Chrome ignore-lists both by default, so pointing at
    /// either would name a file the reader never wrote. With nothing but
    /// library frames (a log from inside a dependency), the top one is honest.
    public static func location(in frames: [SymbolicatedFrame]) -> ConsoleSourceLocation? {
        guard !frames.isEmpty else { return nil }
        let owned = frames.first { !$0.collapse && !isDependency($0.file) }
            ?? frames.first { !$0.collapse }
            ?? frames[0]
        return ConsoleSourceLocation(file: owned.file, line: owned.lineNumber, function: owned.methodName)
    }

    public static func isDependency(_ path: String) -> Bool {
        path.contains("/node_modules/")
    }

    /// A path's last component. Plain string work rather than `NSString`
    /// bridging, which ADBKit keeps out of portable code — and it takes both
    /// separators, since the path is whatever the machine running Metro
    /// reports.
    public static func fileName(_ path: String) -> String {
        let last = path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init)
        return last ?? path
    }
}
