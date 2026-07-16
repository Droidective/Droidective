import Foundation

public enum CrashFormat: String, Sendable, CaseIterable {
    case plain
    case slack
    case jira

    public var label: String {
        switch self {
        case .plain: return "Plain"
        case .slack: return "Slack"
        case .jira: return "Jira"
        }
    }
}

/// Crash extraction: pulls the device's crash buffer (falling back to
/// FATAL/AndroidRuntime/ReactNativeJS lines in the main buffer), splits it
/// into individual `CrashReport`s via `CrashParser`, and formats a crash for
/// pasting into Slack, Jira, or plain text.
public struct CrashExtractor: Sendable {
    /// Cap the logcat dump we pull. The crash/main buffers can hold very large
    /// lines (RN apps log big payloads), and the default 10 MB ceiling is far
    /// more than the UI can render; 512 KB is plenty to find recent crashes.
    static let maxLogcatBytes = 512 * 1024

    let client: AdbClient

    public init(client: AdbClient) {
        self.client = client
    }

    /// Keep a rendered crash small without dropping its diagnostic header. A
    /// fatal log line can be huge (RN payload logging) and the crash buffer
    /// isn't otherwise trimmed, so a crash can balloon into a multi-megabyte
    /// string that freezes the UI when shown as a selectable Text. Android
    /// traces lead with the most useful lines (FATAL EXCEPTION, the exception
    /// type and message) and trail with framework frames. Keep both ends —
    /// the head so the exception is never silently lost, the tail so the
    /// newest lines survive — and elide the middle, under a character ceiling.
    static func boundedBlock(_ block: String, maxLines: Int = 200, maxChars: Int = 64 * 1024) -> String {
        let lines = block.split(separator: "\n", omittingEmptySubsequences: false)
        var result = block
        if lines.count > maxLines {
            let (head, tail) = headTailSplit(count: lines.count, keep: maxLines)
            let elided = lines.count - head - tail
            result = (lines.prefix(head) + ["… \(elided) lines elided …"] + lines.suffix(tail))
                .joined(separator: "\n")
        }
        guard result.count > maxChars else { return result }
        let chars = Array(result)
        let (head, tail) = headTailSplit(count: chars.count, keep: maxChars)
        let elided = chars.count - head - tail
        return String(chars.prefix(head)) + "\n… \(elided) characters elided …\n" + String(chars.suffix(tail))
    }

    /// Head/tail counts for keeping the first ~2/3 and last ~1/3 of `count`
    /// items within `keep`, reserving one slot for the elision marker.
    private static func headTailSplit(count: Int, keep: Int) -> (head: Int, tail: Int) {
        let budget = max(keep - 1, 0)
        let head = budget * 2 / 3
        return (head, budget - head)
    }

    public static func format(_ block: String, as format: CrashFormat) -> String {
        switch format {
        case .slack: return "```\n\(block)\n```"
        case .jira: return "{code}\n\(block)\n{code}"
        case .plain: return block
        }
    }

    /// Every crash on the device, newest first. Reads the crash buffer; when
    /// that's empty (cleared, or an RN error that never crashed the process),
    /// scans the tail of the main buffer instead.
    public func crashes(serial: String) async throws(AdbError) -> [CrashReport] {
        let crashBuffer = try await client.run(
            on: serial, ["logcat", "-d", "-b", "crash", "-v", "threadtime", "-t", "1000"],
            maxOutputBytes: Self.maxLogcatBytes
        )
        var reports = CrashParser.parse(crashBuffer.stdout, source: .crashBuffer)

        if reports.isEmpty {
            let mainBuffer = try await client.run(
                on: serial, ["logcat", "-d", "-b", "main", "-v", "threadtime", "-t", "2000"],
                maxOutputBytes: Self.maxLogcatBytes
            )
            reports = CrashParser.parse(mainBuffer.stdout, source: .mainBuffer)
        }
        return reports.reversed()
    }

    /// Empty the device's crash buffer.
    public func clearCrashBuffer(serial: String) async throws(AdbError) {
        _ = try await client.run(on: serial, ["logcat", "-c", "-b", "crash"])
    }
}
