import Foundation

/// Host-side archive extraction commands, per platform. POSIX hosts call the
/// standard `/usr/bin` tools by absolute path (a GUI app's PATH is minimal, and
/// both ship with macOS and every mainstream distro); Windows uses the system
/// bsdtar, which reads zip archives too.
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
    #else
    static var unzipExecutable: String { "/usr/bin/unzip" }
    static var tarExecutable: String { "/usr/bin/tar" }

    static func unzipArguments(archive: String, into dir: String) -> [String] {
        ["-q", "-o", archive, "-d", dir]
    }
    #endif

    static func tarGzArguments(archive: String, into dir: String) -> [String] {
        ["-xzf", archive, "-C", dir]
    }
}
