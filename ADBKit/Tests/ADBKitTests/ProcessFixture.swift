import Foundation

@testable import ADBKit

/// On-disk record of real process invocations, so parser tests can assert against
/// genuine device output instead of hand-written sample strings.
///
/// The mock suite proves we send the right adb arguments; fixtures prove the
/// parsers survive what a device actually replies — including the CRLF, padding,
/// and truncation quirks nobody writes into a literal by hand.
///
/// Recorded once against a live emulator (see `RecordingProcessRunner`), then
/// replayed offline and in CI (see `FixtureProcessRunner`). The JSON is
/// deliberately plain and flat so a future non-Swift client can consume the same
/// files rather than re-deriving fixtures of its own.
struct ProcessFixture: Codable, Sendable {
    /// One recorded invocation and its result.
    struct Entry: Codable, Sendable {
        var executable: String
        var arguments: [String]
        /// UTF-8 output. `nil` when the payload was binary or over the cap — see
        /// `omittedReason`. Binary payloads (screenshots) are parser-irrelevant
        /// and would bloat the repo, so they are recorded as metadata only.
        var stdout: String?
        var stderr: String?
        var exitCode: Int32?
        var timedOut: Bool
        /// Set when stdout was not captured verbatim, e.g. "binary, 1048576 bytes".
        var omittedReason: String?

        var output: ProcessOutput {
            ProcessOutput(
                stdout: Data((stdout ?? "").utf8),
                stderr: Data((stderr ?? "").utf8),
                exitCode: exitCode,
                timedOut: timedOut
            )
        }
    }

    /// What the recording ran against, for provenance when a fixture looks odd.
    var deviceModel: String?
    var androidSdk: String?
    var entries: [Entry]

    init(deviceModel: String? = nil, androidSdk: String? = nil, entries: [Entry] = []) {
        self.deviceModel = deviceModel
        self.androidSdk = androidSdk
        self.entries = entries
    }
}

// MARK: - Location

extension ProcessFixture {
    /// The committed recording replayed by `RecordedOutputParserTests`.
    static let androidEmulatorName = "android-emulator"

    /// Fixtures live beside the tests, located from `#filePath` rather than an
    /// absolute path or the working directory — the suite has to keep working on
    /// a Linux CI host with a different layout and no Xcode.
    static var directory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
    }

    static func url(named name: String) -> URL {
        directory.appendingPathComponent("\(name).json")
    }

    static func load(named name: String) throws -> ProcessFixture {
        let data = try Data(contentsOf: url(named: name))
        return try JSONDecoder().decode(ProcessFixture.self, from: data)
    }

    func write(named name: String) throws {
        try FileManager.default.createDirectory(
            at: Self.directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        // Sorted keys and indentation keep fixture diffs reviewable — a
        // re-recording should show a real output change, not a key reshuffle.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: Self.url(named: name), options: .atomic)
    }
}

// MARK: - Redaction

/// Scrubs values that must never reach a committed fixture.
///
/// Recording runs against a real device, so raw output can carry Wi-Fi
/// passwords, IPs, and hardware identifiers. Redaction is applied at record
/// time — not read time — so an unredacted value is never written to disk in the
/// first place. gitleaks runs pre-commit, but relying on it would mean depending
/// on a secret scanner to catch our own tooling.
enum FixtureRedaction {
    /// Commands whose output is never recorded at all, matched on an argument
    /// subsequence. Scrubbing patterns out of these is not good enough — the
    /// whole payload is the secret.
    static let deniedArgumentPatterns: [[String]] = [
        ["WifiConfigStore.xml"],
        ["wpa_supplicant.conf"],
        ["shell", "su", "-c"],  // arbitrary root command; contents unknowable
    ]

    static func isDenied(arguments: [String]) -> Bool {
        deniedArgumentPatterns.contains { pattern in
            guard !pattern.isEmpty else { return false }
            // Match a contiguous run, or any single-token pattern appearing
            // inside a joined argument (paths arrive quoted and concatenated).
            if pattern.count == 1 {
                return arguments.contains { $0.contains(pattern[0]) }
            }
            guard arguments.count >= pattern.count else { return false }
            for start in 0...(arguments.count - pattern.count) {
                if Array(arguments[start..<(start + pattern.count)]) == pattern { return true }
            }
            return false
        }
    }

    /// Replace IPv4 addresses, MACs, the recording device's serial, and the
    /// recording host's home directory — fixtures are committed, so a developer's
    /// username must not travel with them (it would also make the fixture
    /// host-specific, which the no-hardcoded-paths rule forbids).
    static func scrub(_ text: String, serial: String?) -> String {
        var out = text
        if let serial, !serial.isEmpty {
            out = out.replacingOccurrences(of: serial, with: "<serial>")
        }
        let home = NSHomeDirectory()
        if !home.isEmpty, home != "/" {
            out = out.replacingOccurrences(of: home, with: "<home>")
        }
        out = replacing(out, pattern: #"\b\d{1,3}(\.\d{1,3}){3}\b"#, with: "<ipv4>")
        out = replacing(out, pattern: #"\b([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\b"#, with: "<mac>")
        return out
    }

    /// Placeholder standing in for whichever device the recording ran against.
    static let serialPlaceholder = "<serial>"

    /// Normalize an argument vector so a fixture is device-independent.
    ///
    /// adb targets a device with `-s <serial>`, so a raw recording bakes in
    /// `emulator-5554` and then fails to match on a host where the emulator
    /// landed on another port. Both the recorder and the replayer run arguments
    /// through this, so matching is unaffected by which device was used.
    static func normalizeArguments(_ arguments: [String], serial: String? = nil) -> [String] {
        var out = arguments
        // Replace the value following `-s`, which is the serial by definition.
        var index = 0
        while index < out.count - 1 {
            if out[index] == "-s" {
                out[index + 1] = serialPlaceholder
                index += 2
                continue
            }
            index += 1
        }
        // A serial can also appear elsewhere (e.g. `adb connect <host:port>`),
        // so scrub any remaining literal occurrences when we know it.
        if let serial, !serial.isEmpty {
            out = out.map { $0 == serial ? serialPlaceholder : $0 }
        }
        return out
    }

    private static func replacing(_ text: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text),
            withTemplate: replacement
        )
    }
}
