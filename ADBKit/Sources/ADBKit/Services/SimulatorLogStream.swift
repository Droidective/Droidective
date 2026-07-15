import Foundation

/// Pure parsing for the iOS Simulator's unified log, testable without Xcode.
/// The stream runs `log stream --style ndjson` inside the simulator (via
/// `simctl spawn`), one JSON event per line — far more robust to parse than
/// the human-readable styles.
public enum SimulatorLogParser {
    private struct Event: Decodable {
        let eventMessage: String?
        let messageType: String?
        let timestamp: String?
        let processID: Int?
        let processImagePath: String?
        let subsystem: String?
    }

    /// One ndjson event → a display line, mapped into logcat's `LogLine` so
    /// the log pane, filters, and Find bar are shared between the platforms.
    /// Non-JSON lines (the "Filtering the log data…" preamble) and events
    /// without a message return nil.
    public static func parse(_ raw: String) -> LogLine? {
        guard let event = try? JSONDecoder().decode(Event.self, from: Data(raw.utf8)),
              let message = event.eventMessage, !message.isEmpty
        else { return nil }
        let time = clockTime(event.timestamp)
        let pid = event.processID.map(String.init) ?? ""
        let level = levelLetter(event.messageType)
        let process = (event.processImagePath as NSString?)?.lastPathComponent ?? ""
        let body: String
        if let subsystem = event.subsystem, !subsystem.isEmpty {
            body = "[\(subsystem)] \(message)"
        } else {
            body = message
        }
        return LogLine(
            raw: "\(time)  \(pid)  \(level)/\(process): \(body)",
            time: time, pid: pid, level: level, tag: process, message: body
        )
    }

    /// "2026-07-15 10:11:12.123456+0530" → "10:11:12.123", matching logcat's
    /// clock-only threadtime timestamps.
    private static func clockTime(_ timestamp: String?) -> String {
        guard let clock = timestamp?.split(separator: " ").dropFirst().first else { return "" }
        return String(clock.prefix(12))
    }

    /// Unified-log message types folded onto logcat's level letters so the
    /// shared pane colors them the same way. "Default" reads as info.
    private static func levelLetter(_ type: String?) -> String {
        switch type {
        case "Fault": return "F"
        case "Error": return "E"
        case "Debug": return "D"
        default: return "I"
        }
    }

    /// Arguments for `xcrun`. `level` widens what the simulator emits —
    /// nil/"default" is the OS default; "info" and "debug" include the
    /// chattier levels.
    public static func buildArgs(udid: String, level: String?) -> [String] {
        var args = ["simctl", "spawn", udid, "log", "stream", "--style", "ndjson"]
        if let level {
            args += ["--level", level]
        }
        return args
    }
}

/// Live unified-log streaming for a booted iOS Simulator — `LogcatStreamer`'s
/// simctl twin: spawns `xcrun simctl spawn <udid> log stream`, parses ndjson
/// events, and yields debounced batches. One session per streamer; restarting
/// stops the previous process.
public actor SimulatorLogStreamer {
    static let flushInterval: Duration = .milliseconds(120)
    static let maxBatch = 500

    private let xcrunPath: String
    private var process: Process?
    private var readHandle: FileHandle?
    private var continuation: AsyncStream<[LogLine]>.Continuation?
    private var batch: [LogLine] = []
    private var readerTask: Task<Void, Never>?
    private var flusherTask: Task<Void, Never>?
    /// Session stamp; bumped on every start/stop so stale tasks no-op.
    private var epoch: UInt64 = 0

    public init(xcrunPath: String = "/usr/bin/xcrun") {
        self.xcrunPath = xcrunPath
    }

    /// Start (or restart) streaming. The stream finishes when the process
    /// exits or `stop()` is called.
    ///
    /// Sessions are epoch-stamped: a stale reader from a previous session
    /// (whose EOF arrives after a restart) must not tear down the new one.
    public func start(udid: String, level: String?) throws(SimctlError) -> AsyncStream<[LogLine]> {
        stop()
        guard FileManager.default.isExecutableFile(atPath: xcrunPath) else {
            throw .xcrunNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: xcrunPath)
        process.arguments = SimulatorLogParser.buildArgs(udid: udid, level: level)
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
                    guard let parsed = SimulatorLogParser.parse(line) else { continue }
                    self.append(parsed, epoch: sessionEpoch)
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
