import Foundation

/// Unified-log levels, ordered least to most severe. `notice` is what Apple
/// calls "Default" — the level `os_log`/`Logger` emit when none is given.
public enum SimLogLevel: String, Sendable, CaseIterable, Comparable {
    case debug
    case info
    case notice
    case error
    case fault

    public var label: String {
        switch self {
        case .debug: return "Debug"
        case .info: return "Info"
        case .notice: return "Notice"
        case .error: return "Error"
        case .fault: return "Fault"
        }
    }

    private var rank: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .notice: return 2
        case .error: return 3
        case .fault: return 4
        }
    }

    public static func < (lhs: SimLogLevel, rhs: SimLogLevel) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// One unified-log event, structured the way iOS developers reason about
/// their logs: process, subsystem:category, level, message.
public struct SimLogLine: Sendable, Identifiable, Equatable {
    public let id: UUID
    /// Clock-only "10:11:12.123".
    public let time: String
    public let process: String
    public let pid: String
    public let level: SimLogLevel
    public let subsystem: String
    public let category: String
    public let message: String
    /// Every filterable field lowercased once at ingest, so the free-text
    /// filter is a plain substring check per line.
    public let searchKey: String

    public init(
        time: String, process: String, pid: String, level: SimLogLevel,
        subsystem: String, category: String, message: String
    ) {
        self.id = UUID()
        self.time = time
        self.process = process
        self.pid = pid
        self.level = level
        self.subsystem = subsystem
        self.category = category
        self.message = message
        searchKey = "\(process) \(subsystem) \(category) \(message)".lowercased()
    }

    /// The line as exported to a file.
    public var exportText: String {
        let origin = subsystem.isEmpty ? "" : " [\(subsystem):\(category)]"
        return "\(time) \(process)(\(pid)) \(level.label)\(origin): \(message)"
    }

    public static func == (lhs: SimLogLine, rhs: SimLogLine) -> Bool {
        lhs.id == rhs.id
    }
}

/// What the stream asks the simulator to emit. The unified log unfiltered is
/// the whole OS — every daemon, thousands of lines a second — so scoping is
/// what keeps the feed usable.
public enum SimulatorLogScope: String, Sendable, CaseIterable {
    /// Only installed apps' processes (their binaries live under the data
    /// container's Bundle/Application path) — the Xcode-console-like default.
    case apps
    /// The whole simulator OS, daemons included.
    case everything

    public var label: String {
        switch self {
        case .apps: return "My apps"
        case .everything: return "Everything"
        }
    }
}

/// Pure parsing and argument building for `log stream --style ndjson` run
/// inside a simulator via `simctl spawn` — testable without Xcode.
public enum SimulatorLogParser {
    private struct Event: Decodable {
        let eventMessage: String?
        let messageType: String?
        let timestamp: String?
        let processID: Int?
        let processImagePath: String?
        let subsystem: String?
        let category: String?
    }

    /// Installed apps' executables live under this path inside the data
    /// container; the OS's own daemons don't — the "My apps" predicate.
    static let appsPredicate = #"processImagePath CONTAINS "/Containers/Bundle/Application/""#

    /// One ndjson event → a structured line. Non-JSON lines (the "Filtering
    /// the log data…" preamble) and events without a message return nil.
    public static func parse(_ raw: String) -> SimLogLine? {
        guard let event = try? JSONDecoder().decode(Event.self, from: Data(raw.utf8)),
              let message = event.eventMessage, !message.isEmpty
        else { return nil }
        return SimLogLine(
            time: clockTime(event.timestamp),
            process: (event.processImagePath as NSString?)?.lastPathComponent ?? "",
            pid: event.processID.map(String.init) ?? "",
            level: level(event.messageType),
            subsystem: event.subsystem ?? "",
            category: event.category ?? "",
            message: message
        )
    }

    /// "2026-07-15 10:11:12.123456+0530" → "10:11:12.123".
    private static func clockTime(_ timestamp: String?) -> String {
        guard let clock = timestamp?.split(separator: " ").dropFirst().first else { return "" }
        return String(clock.prefix(12))
    }

    private static func level(_ type: String?) -> SimLogLevel {
        switch type {
        case "Fault": return .fault
        case "Error": return .error
        case "Debug": return .debug
        case "Info": return .info
        default: return .notice
        }
    }

    /// Arguments for `xcrun`. `emit` widens what the simulator produces —
    /// nil is the OS default (notice and up); `info`/`debug` include the
    /// chattier levels.
    public static func buildArgs(
        udid: String, scope: SimulatorLogScope, emit: String?
    ) -> [String] {
        var args = ["simctl", "spawn", udid, "log", "stream", "--style", "ndjson"]
        if let emit {
            args += ["--level", emit]
        }
        if scope == .apps {
            args += ["--predicate", appsPredicate]
        }
        return args
    }
}

/// Pure display filtering behind the iOS Logs view, so it's tested without
/// a simulator.
public enum SimulatorLogFilter {
    /// Lines surviving the level set, the process pick, and the free-text
    /// filter, in stream order.
    public static func visible(
        _ lines: [SimLogLine], levels: Set<SimLogLevel>, process: String?, filter: String
    ) -> [SimLogLine] {
        let query = filter.lowercased()
        return lines.filter { line in
            if !levels.contains(line.level) { return false }
            if let process, line.process != process { return false }
            if !query.isEmpty && !line.searchKey.contains(query) { return false }
            return true
        }
    }

    /// IDs of the lines matching the Find query, in display (stream) order.
    public static func findMatches(in lines: [SimLogLine], query: String) -> [UUID] {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return [] }
        return lines.filter { $0.searchKey.contains(needle) }.map(\.id)
    }

    /// Processes seen in the buffer with their line counts, busiest first —
    /// feeds the Process menu, so it's self-populating from the stream.
    public static func processCounts(_ lines: [SimLogLine]) -> [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for line in lines where !line.process.isEmpty {
            counts[line.process, default: 0] += 1
        }
        return counts
            .map { (name: $0.key, count: $0.value) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }
}

/// Live unified-log streaming for a booted iOS Simulator: spawns
/// `xcrun simctl spawn <udid> log stream`, parses ndjson events, and yields
/// debounced batches. One session per streamer; restarting stops the
/// previous process. Sessions are epoch-stamped so a stale reader from a
/// previous session (whose EOF arrives after a restart) can't tear down the
/// new one.
public actor SimulatorLogStreamer {
    static let flushInterval: Duration = .milliseconds(300)
    static let maxBatch = 500

    private let xcrunPath: String
    private var process: Process?
    private var readHandle: FileHandle?
    private var continuation: AsyncStream<[SimLogLine]>.Continuation?
    private var batch: [SimLogLine] = []
    private var readerTask: Task<Void, Never>?
    private var flusherTask: Task<Void, Never>?
    /// Session stamp; bumped on every start/stop so stale tasks no-op.
    private var epoch: UInt64 = 0

    public init(xcrunPath: String = "/usr/bin/xcrun") {
        self.xcrunPath = xcrunPath
    }

    /// Start (or restart) streaming. The stream finishes when the process
    /// exits or `stop()` is called.
    public func start(
        udid: String, scope: SimulatorLogScope, emit: String?
    ) throws(SimctlError) -> AsyncStream<[SimLogLine]> {
        stop()
        guard FileManager.default.isExecutableFile(atPath: xcrunPath) else {
            throw .xcrunNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: xcrunPath)
        process.arguments = SimulatorLogParser.buildArgs(udid: udid, scope: scope, emit: emit)
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe

        let (stream, continuation) = AsyncStream.makeStream(
            of: [SimLogLine].self, bufferingPolicy: .bufferingNewest(64)
        )
        epoch += 1
        let sessionEpoch = epoch
        self.continuation = continuation

        do {
            try process.run()
        } catch {
            continuation.finish()
            self.continuation = nil
            return stream
        }
        self.process = process
        self.readHandle = pipe.fileHandleForReading

        let handle = UncheckedSendable(pipe.fileHandleForReading)
        readerTask = Task {
            // Apple platforms keep Foundation's own reader — see the matching
            // note in `LogcatStreamer`. `FileHandle.bytes` is Darwin-only, so
            // other hosts assemble lines themselves. Either way the stream ends
            // on EOF — including a killed process's closed pipe — then falls
            // through to the final flush.
            #if canImport(Darwin)
            do {
                for try await line in handle.value.bytes.lines {
                    guard !Task.isCancelled else { break }
                    guard let parsed = SimulatorLogParser.parse(line) else { continue }
                    self.append(parsed, epoch: sessionEpoch)
                }
            } catch {
                // Pipe closed (process killed) — fall through to final flush.
            }
            #else
            for await line in FileHandleLines.lines(of: handle.value) {
                guard !Task.isCancelled else { break }
                guard let parsed = SimulatorLogParser.parse(line) else { continue }
                self.append(parsed, epoch: sessionEpoch)
            }
            #endif
            self.finishStream(epoch: sessionEpoch)
        }
        flusherTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.flushInterval)
                self.flush(epoch: sessionEpoch)
            }
        }
        return stream
    }

    public func stop() {
        epoch += 1
        readerTask?.cancel()
        flusherTask?.cancel()
        readerTask = nil
        flusherTask = nil
        process?.terminate()
        process = nil
        // Closing our read end EOFs the stale reader promptly. Off-Darwin the
        // reader thread owns the fd (see FileHandleLines); the terminated
        // child EOFs it instead.
        #if canImport(Darwin)
        try? readHandle?.close()
        #endif
        readHandle = nil
        if !batch.isEmpty {
            continuation?.yield(batch)
            batch.removeAll()
        }
        continuation?.finish()
        continuation = nil
    }

    private func append(_ line: SimLogLine, epoch: UInt64) {
        guard epoch == self.epoch else { return }
        batch.append(line)
        if batch.count >= Self.maxBatch {
            flush(epoch: epoch)
        }
    }

    private func flush(epoch: UInt64) {
        guard epoch == self.epoch, !batch.isEmpty, let continuation else { return }
        continuation.yield(batch)
        batch.removeAll()
    }

    private func finishStream(epoch: UInt64) {
        guard epoch == self.epoch else { return }
        flush(epoch: epoch)
        continuation?.finish()
        continuation = nil
        flusherTask?.cancel()
        flusherTask = nil
        process = nil
        #if canImport(Darwin)
        try? readHandle?.close()
        #endif
        readHandle = nil
    }
}
