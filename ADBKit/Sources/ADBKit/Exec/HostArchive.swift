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

    static var zipExecutable: String { "/usr/bin/zip" }

    /// `-r -j`: recurse, and junk the paths so the zip is flat. Unchanged from
    /// what the bug report has always run — macOS ships `zip`, and so does
    /// every mainstream distro's `zip` package.
    static func zipArguments(archive: String, from dir: String) -> [String] {
        ["-r", "-j", archive, dir]
    }
    #endif

    static func tarGzArguments(archive: String, into dir: String) -> [String] {
        ["-xzf", archive, "-C", dir]
    }
}
