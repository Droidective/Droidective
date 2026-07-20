import Foundation

public struct LogLine: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let raw: String
    public let time: String
    public let pid: String
    /// The emitting thread id (threadtime format); empty for sources that
    /// don't carry one (unparsed lines, the simulator log).
    public let tid: String
    public let level: String
    public let tag: String
    public let message: String
    /// The process name behind `pid`, stamped at ingest from a `ps` snapshot
    /// (see `LogcatStreamer.processNames`); nil renders as "?" like the pid
    /// map does for a process that already exited.
    public var processName: String?
    /// `raw` lowercased once at ingest, so the search filter is a plain
    /// substring check per line instead of a locale-aware case-insensitive
    /// scan re-done for the full buffer on every streamed batch.
    public let searchKey: String

    public init(
        raw: String, time: String, pid: String, tid: String = "",
        level: String, tag: String, message: String
    ) {
        self.id = UUID()
        self.raw = raw
        self.time = time
        self.pid = pid
        self.tid = tid
        self.level = level
        self.tag = tag
        self.message = message
        searchKey = raw.lowercased()
    }

    public static func == (lhs: LogLine, rhs: LogLine) -> Bool {
        lhs.id == rhs.id
    }
}

public struct LogcatFilters: Sendable, Equatable {
    /// `-T`: start from the last N lines.
    public var tail: Int
    /// Extra `-b` buffers (e.g. "crash").
    public var buffers: [String]
    /// Minimum level for `*:LEVEL` (V/D/I/W/E/F).
    public var level: String?
    /// Filter to one app's PID. Resolve via `LogcatStreamer.resolvePid` —
    /// callers decide what to do when the app isn't running (a nil pid here
    /// means no `--pid` filter, i.e. the full stream).
    public var pid: Int?

    public init(tail: Int = 300, buffers: [String] = [], level: String? = nil, pid: Int? = nil) {
        self.tail = tail
        self.buffers = buffers
        self.level = level
        self.pid = pid
    }
}

/// Pure threadtime line parsing, testable without a device.
public enum LogcatLineParser {
    /// Hoisted so the regex is compiled once, not rebuilt per line — logcat
    /// streams hundreds of lines a second. `nonisolated(unsafe)` because `Regex`
    /// isn't `Sendable`, but matching against it is a read-only operation with
    /// no shared mutable state, so concurrent `parse` calls are safe.
    nonisolated(unsafe) static let threadtime = /^(\d\d-\d\d \d\d:\d\d:\d\d\.\d\d\d)\s+(\d+)\s+(\d+)\s+([VDIWEFS])\s+(.*?):\s?(.*)$/

    public static func parse(_ raw: String) -> LogLine {
        guard let match = raw.wholeMatch(of: threadtime) else {
            return LogLine(raw: raw, time: "", pid: "", level: "", tag: "", message: raw)
        }
        return LogLine(
            raw: raw,
            time: String(match.1),
            pid: String(match.2),
            tid: String(match.3),
            level: String(match.4),
            tag: String(match.5),
            message: String(match.6)
        )
    }

    /// Parse `ps -A -o PID,NAME` output into pid → process name, for the log
    /// pane's process column. Tolerates the header row, CRLF, and ragged
    /// whitespace; rows that don't lead with a number are skipped.
    public static func parseProcessNames(_ output: String) -> [String: String] {
        var names: [String: String] = [:]
        for row in output.components(separatedBy: .newlines) {
            let fields = row.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard fields.count == 2, fields[0].allSatisfy(\.isNumber) else { continue }
            names[String(fields[0])] = fields[1].trimmingCharacters(in: .whitespaces)
        }
        return names
    }

    public static func buildArgs(serial: String, filters: LogcatFilters) -> [String] {
        var args = ["-s", serial, "logcat", "-v", "threadtime", "-T", String(filters.tail)]
        for buffer in filters.buffers {
            args += ["-b", buffer]
        }
        if let pid = filters.pid {
            args += ["--pid", String(pid)]
        }
        if let level = filters.level {
            args.append("*:\(level)")
        }
        return args
    }
}

/// Live logcat streaming: spawns `adb logcat`, parses threadtime lines, and
/// yields debounced batches. One session per streamer; restarting stops the
/// previous process.
public actor LogcatStreamer {
    static let flushInterval: Duration = .milliseconds(120)
    static let maxBatch = 500

    private let client: AdbClient
    private var process: Process?
    private var readHandle: FileHandle?
    private var continuation: AsyncStream<[LogLine]>.Continuation?
    private var batch: [LogLine] = []
    private var readerTask: Task<Void, Never>?
    private var flusherTask: Task<Void, Never>?
    /// Session stamp; bumped on every start/stop so stale tasks no-op.
    private var epoch: UInt64 = 0

    public init(client: AdbClient) {
        self.client = client
    }

    /// A snapshot of the device's running processes (pid → name), for the
    /// log pane's process column. Best-effort: an error reads as an empty
    /// map and the column shows "?".
    public func processNames(serial: String) async -> [String: String] {
        guard let result = try? await client.run(on: serial, ["shell", "ps", "-A", "-o", "PID,NAME"]) else {
            return [:]
        }
        return LogcatLineParser.parseProcessNames(result.stdout)
    }

    /// Resolve a package's running PID, or nil if it isn't running.
    public func resolvePid(serial: String, packageId: String) async throws(AdbError) -> Int? {
        let result = try await client.run(on: serial, ["shell", "pidof", "-s", shellQuote(packageId)])
        let first = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ").first
        return first.flatMap { Int($0) }
    }

    /// Start (or restart) streaming. The stream finishes when the process
    /// exits or `stop()` is called.
    ///
    /// Sessions are epoch-stamped: a stale reader from a previous session
    /// (whose EOF arrives after a restart) must not tear down the new one.
    public func start(serial: String, filters: LogcatFilters) async throws(AdbError) -> AsyncStream<[LogLine]> {
        stop()
        let adbPath = try await client.locator.adbPath()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: adbPath)
        process.arguments = LogcatLineParser.buildArgs(serial: serial, filters: filters)
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe

        let (stream, continuation) = AsyncStream.makeStream(
            of: [LogLine].self, bufferingPolicy: .bufferingNewest(64)
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
            do {
                for try await line in handle.value.bytes.lines {
                    guard !Task.isCancelled else { break }
                    if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
                    self.append(LogcatLineParser.parse(line), epoch: sessionEpoch)
                }
            } catch {
                // Pipe closed (process killed) — fall through to final flush.
            }
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
        // Closing our read end EOFs the stale reader promptly.
        try? readHandle?.close()
        readHandle = nil
        if !batch.isEmpty {
            continuation?.yield(batch)
            batch.removeAll()
        }
        continuation?.finish()
        continuation = nil
    }

    private func append(_ line: LogLine, epoch: UInt64) {
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
        try? readHandle?.close()
        readHandle = nil
    }
}
