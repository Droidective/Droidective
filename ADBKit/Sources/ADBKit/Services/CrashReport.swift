import Foundation

/// One crash pulled from the device, split out of a logcat buffer dump.
public struct CrashReport: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable {
        case java
        case native
        case reactNative
        case anr
        case unknown

        public var label: String {
            switch self {
            case .java: return "Java exception"
            case .native: return "Native crash"
            case .reactNative: return "React Native"
            case .anr: return "ANR"
            case .unknown: return "Crash"
            }
        }
    }

    /// Stable across refetches of the same buffer (timestamp + pid + title),
    /// so list selection survives a refresh / watch poll.
    public let id: String
    public let kind: Kind
    /// Raw logcat timestamp ("06-12 10:00:02.123"); nil when the dump had no
    /// threadtime prefix. Logcat dates carry no year, so this stays a string.
    public let timestamp: String?
    public let process: String?
    public let pid: Int?
    /// One-line summary: the exception line, signal line, or ANR line.
    public let title: String
    /// The block exactly as logcat printed it (bounded).
    public let raw: String
    /// The block with threadtime prefixes stripped — just the messages (bounded).
    public let body: String

    public init(
        id: String, kind: Kind, timestamp: String?, process: String?, pid: Int?,
        title: String, raw: String, body: String
    ) {
        self.id = id
        self.kind = kind
        self.timestamp = timestamp
        self.process = process
        self.pid = pid
        self.title = title
        self.raw = raw
        self.body = body
    }
}

/// Pure splitting of a logcat dump into individual crashes. No I/O.
public enum CrashParser {
    public enum Source: Sendable {
        /// `-b crash`: every line belongs to some crash — append freely.
        case crashBuffer
        /// `-b main`: crash lines are interleaved with app noise — only lines
        /// from the known crash tags (and the crashing pid) join a block.
        case mainBuffer
    }

    /// Tags that carry crash output in the main buffer. Trailing-space
    /// insensitive (threadtime pads tags before the colon).
    static let crashTags: Set<String> = [
        "AndroidRuntime", "ReactNativeJS", "DEBUG", "libc", "ActivityManager",
    ]

    /// Hoisted like `LogcatLineParser.threadtime`: `Regex` isn't `Sendable`,
    /// but matching is read-only, so concurrent `parse` calls are safe.
    nonisolated(unsafe) static let loosePrefix = /^([VDIWEFS])\s+([^:]+?)\s*:\s?(.*)$/
    nonisolated(unsafe) static let nativeProcess = />>> (\S+)(?::\S+)? <<</
    nonisolated(unsafe) static let javaProcess = /Process: (\S+), PID: (\d+)/
    nonisolated(unsafe) static let anrProcess = /^ANR in (\S+)/

    struct Line {
        let raw: String
        let time: String?
        let pid: Int?
        let level: String?
        let tag: String?
        let message: String
    }

    public static func parse(_ text: String, source: Source) -> [CrashReport] {
        var reports: [CrashReport] = []
        var current: Block?
        var seenIDs: [String: Int] = [:]

        func flush() {
            guard let block = current else { return }
            reports.append(block.report(dedupe: &seenIDs))
            current = nil
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = normalize(rawLine)
            if line.message.hasPrefix("--------- beginning of") { continue }

            if let kind = startKind(of: line, current: current) {
                flush()
                current = Block(kind: kind, first: line)
                continue
            }
            guard var block = current else { continue }
            if source == .mainBuffer && !belongsToBlock(line, block: block) {
                // Foreign noise between crash lines ends the block.
                if !line.message.trimmingCharacters(in: .whitespaces).isEmpty { flush() }
                continue
            }
            block.append(line)
            current = block
        }
        flush()

        // A crash buffer with content but no recognizable marker (some native
        // traces) must still surface — as one whole-buffer report.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if reports.isEmpty, source == .crashBuffer, !trimmed.isEmpty {
            var block = Block(kind: .unknown, first: normalize(""))
            block.lines = trimmed.components(separatedBy: .newlines).map(normalize)
            reports.append(block.report(dedupe: &seenIDs))
        }
        return reports
    }

    /// The kind of crash `line` starts, or nil when it's a continuation.
    private static func startKind(of line: Line, current: Block?) -> CrashReport.Kind? {
        let message = line.message
        if message.contains("FATAL EXCEPTION") { return .java }
        if message.range(of: "fatal signal", options: .caseInsensitive) != nil { return .native }
        if message.contains("*** *** ***") {
            // The tombstone header follows its "Fatal signal" line — same crash.
            return current?.kind == .native ? nil : .native
        }
        if message.hasPrefix("ANR in ") { return .anr }
        if line.tag == "ReactNativeJS", line.level == "E" || line.level == "F" {
            // Consecutive ReactNativeJS error lines are one error + its stack.
            return current?.kind == .reactNative && current?.lastTag == "ReactNativeJS"
                ? nil : .reactNative
        }
        return nil
    }

    private static func belongsToBlock(_ line: Line, block: Block) -> Bool {
        guard let tag = line.tag, crashTags.contains(tag) else { return false }
        guard let linePid = line.pid, let blockPid = block.pid else { return true }
        return linePid == blockPid
    }

    /// Threadtime parse first; a loose "E Tag: message" prefix as fallback so
    /// pasted / non-threadtime dumps still split correctly.
    private static func normalize(_ raw: String) -> Line {
        let parsed = LogcatLineParser.parse(raw)
        if !parsed.tag.isEmpty {
            return Line(
                raw: raw, time: parsed.time.isEmpty ? nil : parsed.time,
                pid: Int(parsed.pid), level: parsed.level.isEmpty ? nil : parsed.level,
                tag: parsed.tag.trimmingCharacters(in: .whitespaces), message: parsed.message
            )
        }
        if let match = raw.wholeMatch(of: loosePrefix) {
            return Line(
                raw: raw, time: nil, pid: nil, level: String(match.1),
                tag: String(match.2).trimmingCharacters(in: .whitespaces),
                message: String(match.3)
            )
        }
        return Line(raw: raw, time: nil, pid: nil, level: nil, tag: nil, message: raw)
    }

    struct Block {
        let kind: CrashReport.Kind
        var lines: [Line]

        init(kind: CrashReport.Kind, first: Line) {
            self.kind = kind
            lines = first.raw.isEmpty && first.message.isEmpty ? [] : [first]
        }

        mutating func append(_ line: Line) { lines.append(line) }

        var pid: Int? { lines.first(where: { $0.pid != nil })?.pid }
        var lastTag: String? { lines.last?.tag }

        func report(dedupe seenIDs: inout [String: Int]) -> CrashReport {
            let messages = lines.map(\.message)
            let title = Self.title(kind: kind, messages: messages)
            let (process, javaPid) = Self.processAndPid(kind: kind, messages: messages)
            let timestamp = lines.first(where: { $0.time != nil })?.time
            let pid = javaPid ?? self.pid

            var id = [
                timestamp ?? "?", pid.map(String.init) ?? "?", kind.rawValue, String(title.prefix(80)),
            ].joined(separator: "|")
            let occurrence = seenIDs[id, default: 0]
            seenIDs[id] = occurrence + 1
            if occurrence > 0 { id += "#\(occurrence)" }

            return CrashReport(
                id: id, kind: kind, timestamp: timestamp, process: process, pid: pid,
                title: title,
                raw: CrashExtractor.boundedBlock(
                    lines.map(\.raw).joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)),
                body: CrashExtractor.boundedBlock(
                    messages.joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines))
            )
        }

        private static func title(kind: CrashReport.Kind, messages: [String]) -> String {
            let fallback = messages
                .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?
                .trimmingCharacters(in: .whitespaces) ?? "Crash"
            switch kind {
            case .java:
                // The exception line follows "FATAL EXCEPTION: <thread>" and
                // the optional "Process: …" line.
                let exception = messages.dropFirst().first {
                    let t = $0.trimmingCharacters(in: .whitespaces)
                    return !t.isEmpty && !t.hasPrefix("Process:") && !t.contains("FATAL EXCEPTION")
                }
                return exception?.trimmingCharacters(in: .whitespaces) ?? fallback
            case .native:
                let signal = messages.first {
                    $0.range(of: "fatal signal", options: .caseInsensitive) != nil
                        || $0.firstMatch(of: /^\s*signal \d+ \(/) != nil
                } ?? fallback
                // Drop the "…, fault addr … in tid …" tail — the list row
                // only needs "Fatal signal 11 (SIGSEGV), code 1 (SEGV_MAPERR)".
                let trimmed = signal.trimmingCharacters(in: .whitespaces)
                if let range = trimmed.range(of: ", fault addr") {
                    return String(trimmed[..<range.lowerBound])
                }
                return trimmed
            case .anr, .reactNative, .unknown:
                return fallback
            }
        }

        private static func processAndPid(
            kind: CrashReport.Kind, messages: [String]
        ) -> (process: String?, pid: Int?) {
            for message in messages {
                if let match = message.firstMatch(of: CrashParser.javaProcess) {
                    return (String(match.1), Int(match.2))
                }
                if let match = message.firstMatch(of: CrashParser.nativeProcess) {
                    return (String(match.1), nil)
                }
                if kind == .anr, let match = message.firstMatch(of: CrashParser.anrProcess) {
                    return (String(match.1), nil)
                }
            }
            return (nil, nil)
        }
    }
}
