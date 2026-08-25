import Foundation

/// Command-line options, parsed purely so the rules are testable without
/// launching anything.
public struct DaemonOptions: Equatable, Sendable {
    /// 0 means "let the OS choose", which is the default and the point: port 0
    /// plus a printed port line means two daemons never collide, so no lockfile
    /// and no single-instance rule that can go stale.
    public var port: Int = 0
    /// Where to write the shared secret. Absent means generate one and print
    /// it — useful by hand, not how the UI drives it.
    public var tokenFile: String?
    /// Exit when this process disappears. Without it, a crashed UI leaves a
    /// daemon holding adb children — the failure users experience as "adb is
    /// stuck".
    public var parentPID: Int32?
    /// Where the app keeps its bundled `scrcpy-server`.
    ///
    /// The Mac ships the jar inside its own bundle and promises no separate
    /// scrcpy install; off Apple the app bundles the same file — it is a Java
    /// jar, so one copy suits every platform — and tells the daemon where it
    /// put it. Absent falls back to an installed scrcpy, which is what a
    /// developer running the daemon by hand has.
    public var scrcpyServer: String?

    public init(
        port: Int = 0, tokenFile: String? = nil, parentPID: Int32? = nil,
        scrcpyServer: String? = nil
    ) {
        self.port = port
        self.tokenFile = tokenFile
        self.parentPID = parentPID
        self.scrcpyServer = scrcpyServer
    }

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case missingValue(String)
        case notANumber(flag: String, value: String)
        case portOutOfRange(Int)
        case unknownFlag(String)

        public var description: String {
            switch self {
            case .missingValue(let flag): return "\(flag) needs a value"
            case .notANumber(let flag, let value): return "\(flag) expects a number, got '\(value)'"
            case .portOutOfRange(let port): return "--port must be 0…65535, got \(port)"
            case .unknownFlag(let flag): return "unknown flag '\(flag)'"
            }
        }
    }

    /// Parses argv (without the executable name). Unknown flags are an error
    /// rather than ignored — a typo in the UI's spawn arguments should fail
    /// loudly at startup, not silently run with a default.
    public static func parse(_ arguments: [String]) throws -> DaemonOptions {
        var options = DaemonOptions()
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let flag = arguments[index]
            func value() throws -> String {
                let next = arguments.index(after: index)
                guard next < arguments.endIndex else { throw ParseError.missingValue(flag) }
                index = next
                return arguments[next]
            }
            switch flag {
            case "--port":
                let raw = try value()
                guard let port = Int(raw) else {
                    throw ParseError.notANumber(flag: flag, value: raw)
                }
                guard (0...65535).contains(port) else { throw ParseError.portOutOfRange(port) }
                options.port = port
            case "--token-file":
                options.tokenFile = try value()
            case "--scrcpy-server":
                options.scrcpyServer = try value()
            case "--parent-pid":
                let raw = try value()
                guard let pid = Int32(raw) else {
                    throw ParseError.notANumber(flag: flag, value: raw)
                }
                options.parentPID = pid
            default:
                throw ParseError.unknownFlag(flag)
            }
            index = arguments.index(after: index)
        }
        return options
    }
}

/// The shared secret.
public enum DaemonToken {
    /// 32 random bytes, hex encoded.
    ///
    /// Written to a file rather than passed in argv, because argv is
    /// world-readable through `ps` — the same reasoning `ApkSigningService`
    /// already applies to keystore passwords.
    public static func generate() -> String {
        (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }

    /// Writes the token owner-only. Returns false when the mode could not be
    /// applied, so the caller can refuse to start rather than serve with a
    /// world-readable secret.
    @discardableResult
    public static func write(_ token: String, to path: String) throws -> Bool {
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(token.utf8).write(to: url, options: [.atomic])
        #if os(Windows)
        // NTFS ACLs, not POSIX modes; the file lands under the caller's own
        // directory. Reported honestly rather than pretending 0600 was applied.
        return false
        #else
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: url.path)
        return true
        #endif
    }
}
