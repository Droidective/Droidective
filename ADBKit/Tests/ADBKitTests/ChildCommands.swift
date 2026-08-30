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

    private static var systemRoot: String {
        ProcessInfo.processInfo.environment["SystemRoot"] ?? #"C:\Windows"#
    }

    /// Writes a one-shot batch file and returns `cmd /c <path>`.
    ///
    /// Anything with `&`, `|` or a redirect has to arrive this way rather than
    /// inline: Foundation quotes each argument for `CreateProcess`, and cmd's
    /// own parsing of the result mangles metacharacters badly enough that the
    /// child fails to launch at all. A lone script path has none. (The script
    /// cannot be the executable directly — `CreateProcess` does not run
    /// `.cmd` files, only real images.)
    private static func script(
        _ name: String, _ body: String
    ) -> (executable: String, arguments: [String]) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("adbkit-child-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(name).cmd")
        try? Data(("@echo off\r\n" + body).utf8).write(to: url)
        return (shell, ["/c", url.path])
    }

    static let echo = (executable: shell, arguments: ["/c", "echo hello"])
    // `>&2 echo oops`, not `echo oops 1>&2`: the latter binds the `1` to the
    // redirect and emits a trailing space.
    static let stderrAndExit3 = script("stderr3", ">&2 echo oops\r\nexit /b 3\r\n")
    // `ping` spawned directly, with no `cmd /c` wrapper. Terminating the
    // wrapper would leave the ping grandchild running, so the timeout and
    // cancellation tests would wait out the full sleep instead of observing a
    // prompt kill — which is the behaviour they exist to prove.
    static let sleepForever = (
        executable: #"\#(systemRoot)\System32\ping.exe"#,
        arguments: ["-n", "31", "127.0.0.1"]
    )
    static let spewForever = (executable: shell, arguments: ["/c", "for /l %i in () do @echo y"])
    static let sleepThenPrint = script(
        "sleepprint", "ping -n 2 127.0.0.1 > nul\r\necho done\r\n")

    /// A child that leaves a grandchild holding the pipes and exits at once —
    /// the shape `adb` has when it starts its own server. See the POSIX twin.
    static let forksAndExits = script(
        "forkexit", "start /b ping -n 31 127.0.0.1 > nul\r\necho started\r\n")

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
        executable: "/bin/sh", arguments: ["-c", "sleep 1; echo done"]
    )

    /// A child that leaves a grandchild holding its stdout and exits at once.
    ///
    /// This is `adb`'s shape on a machine whose adb server is not yet running:
    /// it forks the server, prints a line, and exits — and the server inherits
    /// the pipe. On Linux that child is then left a **zombie** that corelibs
    /// never reaps, so `Process.terminationHandler` never fires. Nothing else
    /// in this suite produces that, which is why it was the one failure the
    /// whole desktop app fell over: the first `adb devices` on a fresh machine
    /// never returned.
    static let forksAndExits = (
        executable: "/bin/sh", arguments: ["-c", "sleep 30 & echo started"]
    )

    static let echoOutput = "hello\n"
    static let stderrOutput = "oops\n"
    #endif
}
