import Foundation

/// Host-side archive commands, per platform. POSIX hosts call the standard
/// `/usr/bin` tools by absolute path (a GUI app's PATH is minimal, and both
/// ship with macOS and every mainstream distro); Windows uses the system
/// bsdtar, which reads *and writes* zip archives too.
enum HostArchive {
    #if os(Windows)
    static var unzipExecutable: String { systemTar }
    static var tarExecutable: String { systemTar }

    private static var systemTar: String {
        let root = ProcessInfo.processInfo.environment["SystemRoot"] ?? #"C:\Windows"#
        return #"\#(root)\System32\tar.exe"#
    }

    static func unzipArguments(archive: String, into dir: String) -> [String] {
        ["-xf", archive, "-C", dir]
    }

    /// Every entry's name, one per line, through `unzipExecutable`.
    static func listArguments(archive: String) -> [String] {
        ["-tf", archive]
    }

    /// One entry, written under `dir` at its archive path. bsdtar reads a
    /// member name as a pattern, which is why callers pass only names
    /// `isPlainEntryName` accepts.
    static func extractArguments(archive: String, entry: String, into dir: String) -> [String] {
        ["-xf", archive, "-C", dir, entry]
    }

    static var zipExecutable: String { systemTar }

    /// bsdtar picks the format from the archive's extension with `-a`, so this
    /// writes a real zip. `-C dir .` archives the directory's contents rather
    /// than the directory itself, which is what `zip -j` achieves on POSIX.
    static func zipArguments(archive: String, from dir: String) -> [String] {
        ["-a", "-c", "-f", archive, "-C", dir, "."]
    }
    #else
    static var unzipExecutable: String { "/usr/bin/unzip" }
    static var tarExecutable: String { "/usr/bin/tar" }

    static func unzipArguments(archive: String, into dir: String) -> [String] {
        ["-q", "-o", archive, "-d", dir]
    }

    /// `-Z1` is zipinfo's names-only mode: one entry per line, nothing else.
    static func listArguments(archive: String) -> [String] {
        ["-Z1", archive]
    }

    /// One entry, written under `dir` at its archive path. unzip reads a member
    /// name as a wildcard pattern, which is why callers pass only names
    /// `isPlainEntryName` accepts.
    static func extractArguments(archive: String, entry: String, into dir: String) -> [String] {
        ["-qq", "-o", archive, entry, "-d", dir]
    }

    static var zipExecutable: String { "/usr/bin/zip" }

    /// `-r -j`: recurse, and junk the paths so the zip is flat. Unchanged from
    /// what the bug report has always run — macOS ships `zip`, and so does
    /// every mainstream distro's `zip` package.
    static func zipArguments(archive: String, from dir: String) -> [String] {
        ["-r", "-j", archive, dir]
    }
    #endif

    /// `.tar.xz`, with the compression left for tar to recognise: bsdtar always
    /// has, and GNU tar has since 1.15, so this needs no `xz` binary of its own.
    static func tarXzArguments(archive: String, into dir: String) -> [String] {
        ["-xf", archive, "-C", dir]
    }

    static func tarGzArguments(archive: String, into dir: String) -> [String] {
        ["-xzf", archive, "-C", dir]
    }

    /// The entry names out of a listing, directories dropped. Split on
    /// `.newlines`: bsdtar on Windows ends its lines with CRLF.
    static func parseListing(_ output: String) -> [String] {
        output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasSuffix("/") }
    }

    /// Whether `entry` can be named to the extractor as itself: a relative path
    /// with no `..` (it becomes a path under the destination, which is then
    /// read) and none of the characters both tools treat as a pattern.
    static func isPlainEntryName(_ entry: String) -> Bool {
        guard AppBundleManifest.safeRelativePath(entry) == entry else { return false }
        return !entry.contains { "*?[]\\".contains($0) }
    }
}
