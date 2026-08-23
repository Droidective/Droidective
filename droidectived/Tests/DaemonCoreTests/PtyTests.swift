import Foundation
import Testing

@testable import DaemonCore

/// The pseudo-terminal, against a real shell.
///
/// These spawn a real shell rather than mocking one: the whole point of the
/// class is the handful of things only a real pty does — echo what you type,
/// report a window size, hand the shell a controlling terminal, tell a program
/// it is interactive, and hang up cleanly. None of that survives a fake.
///
/// Serialized: each test starts a shell, and fourteen at once is a lot of
/// process for no extra coverage.
#if !os(Windows)
@Suite(.serialized) struct PtyTests {
    /// The prompt the test shell is given, and the signal that it is ready.
    ///
    /// A shell calls `tcsetattr` with `TCSAFLUSH` while starting up, which
    /// *discards* anything typed before it was ready — so writing straight after
    /// spawn loses the input on a fast machine and works on a slow one, which is
    /// the worst kind of test. Waiting for the prompt removes the race rather
    /// than papering over it with a sleep. A human types slower than a shell
    /// starts, so the race is the harness's alone.
    private static let prompt = "PTY-READY>"

    /// Everything the pty produced, and a bounded wait for a marker in it.
    ///
    /// Deliberately dull: one reader task and wall-clock polling. An earlier
    /// version raced the reader, the writer and a timeout in a task group, and
    /// every way of getting that wrong hangs — a group waits for *every* child,
    /// so one task parked on something uncancellable never lets the test finish,
    /// and a test that hangs looks exactly like a pty that hangs.
    private actor Collected {
        private(set) var text = ""

        func add(_ chunk: String) { text += chunk }

        /// True once `needle` shows up; false if the deadline passes first.
        ///
        /// Generous, because it is an I/O wait that normally resolves in
        /// milliseconds: the ceiling only matters when the machine is busy
        /// running the rest of the suite in parallel, and a tight one there is a
        /// flake rather than a finding.
        func wait(for needle: String, timeout: Duration = .seconds(45)) async -> Bool {
            let deadline = ContinuousClock.now.advanced(by: timeout)
            while ContinuousClock.now < deadline {
                if text.contains(needle) { return true }
                try? await Task.sleep(for: .milliseconds(20))
            }
            return text.contains(needle)
        }
    }

    /// An interactive shell whose startup this test controls.
    ///
    /// **Not** a login shell: those read whichever profile the host has, so what
    /// they print and when is somebody else's business, and `PS1` from the
    /// environment gets overwritten. Interactive and non-login, `sh` keeps the
    /// prompt it was given — which is what makes the readiness signal above
    /// dependable.
    private func shell(
        serial: String? = nil, directory: String? = nil, size: PtySize = .standard
    ) throws -> Pty {
        var environment = Pty.childEnvironment(serial: serial)
        environment["PS1"] = Self.prompt
        // No $ENV either, so nothing else runs at startup.
        environment["ENV"] = nil
        return try Pty.spawn(
            shell: "/bin/sh", arguments: [], environment: environment,
            directory: directory, size: size)
    }

    /// Starts reading a pty into an accumulator. Cancel by terminating the pty:
    /// closing the descriptor is what unblocks the read and finishes the stream.
    private func reading(_ pty: Pty) -> (Collected, Task<Void, Never>) {
        let collected = Collected()
        let task = Task {
            for await chunk in pty.output() {
                await collected.add(String(decoding: chunk, as: UTF8.self))
            }
        }
        return (collected, task)
    }

    /// Waits for the prompt, runs `command`, and waits for `marker`.
    private func run(_ command: String, in pty: Pty, until marker: String) async -> String {
        let (collected, reader) = reading(pty)
        defer { reader.cancel() }
        guard await collected.wait(for: Self.prompt) else {
            return await collected.text
        }
        pty.write(Data("\(command)\n".utf8))
        _ = await collected.wait(for: marker)
        return await collected.text
    }

    // MARK: - what only a real terminal does

    @Test func runsACommandAndReadsItsOutput() async throws {
        let pty = try shell()
        defer { pty.terminate() }
        // The marker is split in the command so the echoed line cannot contain
        // it: this asserts the shell's own output, not the tty echo.
        let text = await run("echo dro''idective-ran", in: pty, until: "droidective-ran")
        #expect(text.contains("droidective-ran"))
    }

    @Test func echoesWhatIsTyped() async throws {
        // A pty echoes input; a pipe does not. The command *text* only ever
        // appears as that echo.
        let pty = try shell()
        defer { pty.terminate() }
        let text = await run("echo typed''-and-echoed", in: pty, until: "typed-and-echoed")
        #expect(text.contains("echo typed''-and-echoed"))
    }

    @Test func theShellBelievesItIsInteractive() async throws {
        // What `isatty` answers decides whether a program emits colour, pages
        // its output, or refuses to start at all.
        let pty = try shell()
        defer { pty.terminate() }
        let text = await run("test -t 0 && echo IS''-A-TTY", in: pty, until: "IS-A-TTY")
        #expect(text.contains("IS-A-TTY"))
    }

    @Test func theShellHasAControllingTerminal() async throws {
        // Without one the shell reads from a terminal it does not control, takes
        // SIGTTIN and stops — alive, echoing every keystroke back through the
        // tty driver, running nothing. `tty` naming a device is the proof that
        // the `TIOCSCTTY` in the C shim happened.
        let pty = try shell()
        defer { pty.terminate() }
        let text = await run("tty", in: pty, until: "/dev/tty")
        #expect(text.contains("/dev/tty"))
    }

    @Test func reportsTheSizeItWasGiven() async throws {
        let pty = try shell(size: PtySize(columns: 132, rows: 43))
        defer { pty.terminate() }
        // `stty size` reads the kernel's window, not an environment variable —
        // so this asserts the ioctl, not a string passed through.
        let text = await run("stty size", in: pty, until: "43 132")
        #expect(text.contains("43 132"))
    }

    @Test func aResizeReachesTheKernel() async throws {
        let pty = try shell()
        defer { pty.terminate() }
        pty.resize(to: PtySize(columns: 100, rows: 30))
        let text = await run("stty size", in: pty, until: "30 100")
        #expect(text.contains("30 100"))
    }

    @Test func carriesTheDeviceSerialIntoTheShell() async throws {
        // How the Mac scopes a terminal to the device on the bar: every adb
        // command inside it targets that device without `-s`.
        let pty = try shell(serial: "R58M4XYZ")
        defer { pty.terminate() }
        let text = await run("echo seen=$ANDROID_SERIAL", in: pty, until: "seen=R58M4XYZ")
        #expect(text.contains("seen=R58M4XYZ"))
    }

    @Test func startsInTheDirectoryItWasGiven() async throws {
        // Otherwise the shell opens wherever the daemon was launched — in a
        // development build, the build folder — and every session starts with
        // a `cd`.
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pty-cwd-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // Resolved, because /tmp is a symlink to /private/tmp on Darwin and
        // `pwd` in a shell reports what the kernel says.
        let resolved = directory.resolvingSymlinksInPath().path

        let pty = try shell(directory: resolved)
        defer { pty.terminate() }
        let text = await run("pwd", in: pty, until: resolved)
        #expect(text.contains(resolved))
    }

    @Test func aStartDirectoryThatIsGoneDoesNotCostTheTerminal() async throws {
        // A deleted directory must not be the difference between a terminal and
        // no terminal: the shell starts in whatever was inherited instead.
        let pty = try shell(directory: "/nonexistent/\(UUID().uuidString)")
        defer { pty.terminate() }
        let text = await run("echo STILL''-HERE", in: pty, until: "STILL-HERE")
        #expect(text.contains("STILL-HERE"))
    }

    // MARK: - the end of a session

    @Test func theOutputStreamFinishesWhenTheShellExits() async throws {
        // The case that makes a terminal look hung: the shell is gone and the
        // reader never notices. Linux reports EIO on the master rather than a
        // clean EOF, which is why both are treated as the end.
        let pty = try shell()
        defer { pty.terminate() }
        let (collected, reader) = reading(pty)
        defer { reader.cancel() }
        #expect(await collected.wait(for: Self.prompt))
        pty.write(Data("exit\n".utf8))

        // The reader task completing *is* the stream finishing.
        let ended = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await reader.value
                return true
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(10))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        #expect(ended, "the output stream never ended after the shell exited")
    }

    @Test func aShellThatDoesNotExistEndsRatherThanHanging() async throws {
        // `exec` fails inside the child, so the failure arrives as the pty
        // reaching EOF rather than as a throw — the same shape as a shell that
        // exited, which is what the session layer above has to handle.
        let pty = try Pty.spawn(
            shell: "/nonexistent/shell", environment: Pty.childEnvironment(serial: nil))
        defer { pty.terminate() }
        let (_, reader) = reading(pty)

        let ended = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await reader.value
                return true
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(10))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        #expect(ended, "a shell that could not be exec'd left the stream open")
    }

    @Test func terminateIsIdempotent() async throws {
        // A subscription ending races the socket closing, and both tear down.
        let pty = try shell()
        pty.terminate()
        pty.terminate()
        // Writing to a terminated pty is a no-op rather than a crash on a
        // closed descriptor.
        pty.write(Data("echo nope\n".utf8))
        pty.resize(to: PtySize(columns: 10, rows: 10))
    }

    // MARK: - the pure parts

    @Test func theDefaultShellPrefersWhatTheUserSet() {
        #expect(Pty.defaultShell(environment: ["SHELL": "/opt/bin/fish"]) == "/opt/bin/fish")
        // Empty is not a choice — it is an unset variable that happens to exist.
        #expect(Pty.defaultShell(environment: ["SHELL": ""]).hasPrefix("/bin/"))
        #expect(Pty.defaultShell(environment: [:]).hasPrefix("/bin/"))
    }

    @Test func aSizeIsClampedToSomethingATerminalCanBe() {
        // Zero reaches `TIOCSWINSZ` intact and then every curses program
        // divides by it.
        #expect(PtySize(columns: 0, rows: 0) == PtySize(columns: 1, rows: 1))
        #expect(PtySize(columns: -5, rows: -5) == PtySize(columns: 1, rows: 1))
        #expect(PtySize(columns: 99_999, rows: 99_999) == PtySize(columns: 2000, rows: 2000))
        #expect(PtySize.standard == PtySize(columns: 80, rows: 24))
    }

    @Test func aSerialIsNotInheritedFromTheDaemonsOwnEnvironment() {
        // Otherwise a daemon started with ANDROID_SERIAL set would silently
        // scope every terminal to a device nobody picked.
        let environment = Pty.childEnvironment(serial: nil, base: ["ANDROID_SERIAL": "GHOST"])
        #expect(environment["ANDROID_SERIAL"] == nil)
    }

    @Test func theStartDirectoryIsTheUsersHome() {
        #expect(Pty.defaultDirectory(environment: ["HOME": "/Users/someone"]) == "/Users/someone")
        // Empty is an unset variable that happens to exist, not a choice.
        #expect(Pty.defaultDirectory(environment: ["HOME": ""]) == nil)
        // Windows spells it differently.
        #expect(
            Pty.defaultDirectory(environment: ["USERPROFILE": #"C:\Users\someone"#])
                == #"C:\Users\someone"#)
        // Nothing to go on means "keep the caller's own directory", which is
        // what happened before the argument existed.
        #expect(Pty.defaultDirectory(environment: [:]) == nil)
    }

    @Test func theShellIsToldItIsAColourTerminal() {
        let environment = Pty.childEnvironment(serial: nil, base: [:])
        #expect(environment["TERM"] == "xterm-256color")
    }
}
#endif
