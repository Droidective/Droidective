import Foundation

/// Real child processes for the `SystemProcessRunner` suite, per host.
///
/// Those tests need genuine processes — the suite is the starvation regression
/// net for a runner that must never park a cooperative thread, so mocking the
/// spawn would remove the only thing under test. The commands themselves are
/// incidental; only their observable behaviour matters: print a line, write to
/// stderr and exit non-zero, sleep past a timeout, spew without stopping.
///
/// **POSIX keeps exactly the commands the suite has always used**, so macOS and
/// Linux stay byte-identical; Windows gets `cmd.exe` equivalents.
///
/// Members, all `(executable, arguments)` unless noted:
/// - `echo` / `echoOutput` — prints one line, exits 0
/// - `stderrAndExit3` / `stderrOutput` — one stderr line, exit 3
/// - `sleepForever` — outlasts any test timeout, so the runner must kill it
/// - `spewForever` — unbounded stdout, to exercise the output cap
/// - `sleepThenPrint` — brief sleep, then a line, then exit 0
enum ChildCommands {
    #if os(Windows)
    /// `cmd.exe`, via ComSpec so a non-standard Windows directory still works.
    private static let shell =
        ProcessInfo.processInfo.environment["ComSpec"] ?? #"C:\Windows\System32\cmd.exe"#

    static let echo = (executable: shell, arguments: ["/c", "echo hello"])
    // `(echo oops)1>&2` rather than `echo oops 1>&2`: in cmd the bare form
    // binds the `1` to the redirect and emits a trailing space.
    static let stderrAndExit3 = (executable: shell, arguments: ["/c", "(echo oops)1>&2 & exit 3"])
    // No `sleep` on Windows, and `timeout` wants a console it does not have
    // once stdio is redirected; pinging loopback is the portable idle.
    static let sleepForever = (executable: shell, arguments: ["/c", "ping -n 31 127.0.0.1 > nul"])
    static let spewForever = (executable: shell, arguments: ["/c", "for /l %i in () do @echo y"])
    static let sleepThenPrint = (
        executable: shell, arguments: ["/c", "ping -n 2 127.0.0.1 > nul & echo done"]
    )

    /// The host's own line ending, so the assertions stay exact.
    static let echoOutput = "hello\r\n"
    static let stderrOutput = "oops\r\n"
    #else
    static let echo = (executable: "/bin/echo", arguments: ["hello"])
    static let stderrAndExit3 = (
        executable: "/bin/sh", arguments: ["-c", "echo oops >&2; exit 3"]
    )
    static let sleepForever = (executable: "/bin/sleep", arguments: ["30"])
    static let spewForever = (executable: "/usr/bin/yes", arguments: [String]())
    static let sleepThenPrint = (
        executable: "/bin/sh", arguments: ["-c", "sleep 0.3; echo done"]
    )

    static let echoOutput = "hello\n"
    static let stderrOutput = "oops\n"
    #endif
}
