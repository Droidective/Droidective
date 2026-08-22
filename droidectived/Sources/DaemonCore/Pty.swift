import CPty
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A pseudo-terminal running a login shell.
///
/// **Why this lives in the daemon rather than ADBKit.** ADBKit is the shared
/// logic layer, and every other service there is shared: the Mac app links it
/// directly. The Mac's terminal is SwiftTerm's `LocalProcessTerminalView`, which
/// owns its own pty — so a pty host here would be a second implementation that
/// nothing on the Mac would ever run. It belongs with the thing that needs it.
///
/// **Why a pty and not a pipe.** A shell behind pipes has no controlling
/// terminal: no job control, no `less`, no colour from anything that checks
/// `isatty`, and `vim` refuses to start. That is a different product, not a
/// simpler version of this one.
public enum PtyError: Error, CustomStringConvertible {
    case unsupportedPlatform
    case openFailed(String)
    case spawnFailed(Int32)

    public var description: String {
        switch self {
        case .unsupportedPlatform:
            return "A terminal needs a pseudo-terminal, which this build does not have on Windows yet."
        case .openFailed(let detail):
            return "Could not open a pseudo-terminal: \(detail)"
        case .spawnFailed(let code):
            return "Could not start the shell: \(String(cString: strerror(code)))"
        }
    }
}

/// How big the terminal is, in character cells.
public struct PtySize: Equatable, Sendable {
    public let columns: Int
    public let rows: Int

    /// Clamped on the way in. A zero or absurd size reaches `TIOCSWINSZ` as a
    /// number the kernel will take and every curses program will then divide
    /// by, so it is corrected here rather than crashing something downstream.
    public init(columns: Int, rows: Int) {
        self.columns = min(max(columns, 1), 2000)
        self.rows = min(max(rows, 1), 2000)
    }

    /// What a client that never told us gets. 80×24 is the terminal default
    /// everything has assumed since VT100.
    public static let standard = PtySize(columns: 80, rows: 24)
}

/// One terminal, as the session layer needs it.
///
/// A protocol for the reason `ProcessRunning` is one: a subscription's whole
/// lifecycle — open, stream, type into, resize, hang up — is then testable
/// without spawning a shell per test. `PtyTests` proves the real implementation
/// against a real shell; this keeps that cost out of every other suite.
///
/// It exists on Windows, where `Pty` does not, so the session layer compiles
/// there and reports the missing terminal at runtime instead of vanishing.
public protocol PtyChannel: Sendable {
    /// Everything the shell writes, until it exits. One consumer only.
    func output() -> AsyncStream<Data>
    func write(_ data: Data)
    func resize(to size: PtySize)
    func terminate()
}

#if os(Windows)

/// Windows needs ConPTY (`CreatePseudoConsole`), which is a different API from
/// the POSIX one below rather than a variation on it. Absent rather than
/// stubbed, so the feature says outright that it is not there — the rule the
/// rest of the port follows for a subsystem a platform genuinely lacks.
public enum Pty {
    public static let isSupported = false
}

#else

/// One running shell and its pseudo-terminal.
///
/// `@unchecked Sendable` because the state it guards is a file descriptor and a
/// pid behind one lock: the read thread and the actor that owns the session
/// touch it from different threads by design, and a lock is the honest way to
/// say so.
public final class Pty: @unchecked Sendable {
    public static let isSupported = true

    private let lock = NSLock()
    private var master: Int32
    private var child: pid_t
    private var closed = false
    /// How `terminate` wakes the reader.
    ///
    /// Closing the descriptor does **not** do it: on Darwin `close` waits for an
    /// outstanding blocking `read` on the same descriptor rather than
    /// interrupting it, and a terminal's reader is blocked in `read` whenever
    /// the shell is idle — which is nearly always. Closing from another thread
    /// therefore hung the caller. The reader waits on this pipe *and* the master
    /// together, and owns closing the master when it leaves.
    private let wakeRead: Int32
    private let wakeWrite: Int32
    /// The parent's own handle on the terminal, for the size ioctl — macOS
    /// rejects `TIOCSWINSZ` on the master. Held for the pty's whole life:
    /// closing the last slave descriptor hangs the master up, so opening one per
    /// resize raced the child's own open and killed the shell before it printed
    /// a prompt. Closing it once the child is gone is what makes the master
    /// report EOF.
    private var slave: Int32
    /// Created once, at spawn. A pty has exactly one reader — two threads
    /// blocking on the same descriptor would split the output between them —
    /// so handing out a fresh stream per call would be handing out a way to
    /// corrupt it.
    private let stream: AsyncStream<Data>

    private init(
        master: Int32, slave: Int32, child: pid_t, wake: (read: Int32, write: Int32),
        stream: AsyncStream<Data>
    ) {
        self.master = master
        self.slave = slave
        self.child = child
        wakeRead = wake.read
        wakeWrite = wake.write
        self.stream = stream
    }

    /// The shell a terminal opens.
    ///
    /// `$SHELL` first, because someone who set it meant it — and it is what the
    /// Mac's terminal runs. The fallbacks are each platform's own default rather
    /// than a single guess: `/bin/zsh` has been macOS's since Catalina, and
    /// `/bin/bash` is present on every mainstream distro.
    public static func defaultShell(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let shell = environment["SHELL"], !shell.isEmpty { return shell }
        #if canImport(Darwin)
        return "/bin/zsh"
        #else
        return "/bin/bash"
        #endif
    }

    /// What a terminal opens a shell as: `-l`, a **login** shell.
    ///
    /// Login, so the rc files that define someone's aliases and PATH are read.
    /// The Mac's terminal does the same, and it is the difference between a
    /// terminal you can use and one where half your muscle memory fails.
    public static let loginArguments = ["-l"]

    /// Where a shell starts.
    ///
    /// The user's home, not the daemon's own working directory — which is
    /// wherever the app that spawned the sidecar happened to be, and in a
    /// development build that is the build folder. A terminal that opens
    /// somewhere the user did not choose is a terminal whose first command is
    /// always `cd`.
    ///
    /// (The Mac's terminal reopens each tab's *last* directory via
    /// `TerminalResume`. That needs the shell's live cwd read out of the
    /// kernel, which has no Windows equivalent, so home is the honest default
    /// until that lands.)
    public static func defaultDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        if let home = environment["HOME"], !home.isEmpty { return home }
        // Windows spells it differently, and this is the one place off-POSIX
        // that matters before ConPTY exists.
        if let profile = environment["USERPROFILE"], !profile.isEmpty { return profile }
        return nil
    }

    /// Starts a shell on a new pseudo-terminal.
    ///
    /// `arguments` is a parameter rather than a constant because a login shell
    /// reads whichever profile the host has, which makes what it prints and when
    /// somebody else's business — the tests need a shell whose startup they
    /// control.
    public static func spawn(
        shell: String = Pty.defaultShell(),
        arguments: [String] = Pty.loginArguments,
        environment: [String: String] = [:],
        directory: String? = Pty.defaultDirectory(),
        size: PtySize = .standard
    ) throws -> Pty {
        var strings = CStrings()
        defer { strings.free() }
        guard let executable = strings.duplicate(shell),
              let argv = strings.array([shell] + arguments),
              let envp = strings.array(environment.map { "\($0.key)=\($0.value)" })
        else { throw PtyError.spawnFailed(ENOMEM) }
        var start: UnsafeMutablePointer<CChar>?
        if let directory {
            guard let copy = strings.duplicate(directory) else {
                throw PtyError.spawnFailed(ENOMEM)
            }
            start = copy
        }

        var master: Int32 = -1
        var slave: Int32 = -1
        let child = droidective_pty_spawn(
            executable, argv, envp, start,
            UInt16(size.columns), UInt16(size.rows), &master, &slave)
        guard child > 0, master >= 0 else { throw PtyError.spawnFailed(errno) }

        var wake: [Int32] = [-1, -1]
        guard pipe(&wake) == 0 else {
            close(master)
            if slave >= 0 { close(slave) }
            kill(child, SIGKILL)
            throw PtyError.openFailed(String(cString: strerror(errno)))
        }

        let (stream, continuation) = AsyncStream<Data>.makeStream()
        let pty = Pty(
            master: master, slave: slave, child: child,
            wake: (read: wake[0], write: wake[1]), stream: stream)
        pty.startReading(into: continuation)
        pty.startReaping()
        return pty
    }

    /// Everything the shell should see in its environment.
    ///
    /// `TERM` because a shell with none assumes a dumb terminal and stops
    /// emitting colour; `ANDROID_SERIAL` because that is how the Mac scopes a
    /// terminal to the device on the bar — every adb command in the shell then
    /// targets it without `-s`.
    public static func childEnvironment(
        serial: String?,
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = base
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        if let serial, !serial.isEmpty {
            environment["ANDROID_SERIAL"] = serial
        } else {
            // Inherited from the daemon's own environment otherwise, which
            // would silently scope the shell to a device nobody chose.
            environment["ANDROID_SERIAL"] = nil
        }
        return environment
    }

    /// Everything the shell writes, until it exits. One `Data` per read,
    /// unparsed — a read can split a multi-byte character, so decoding here
    /// would corrupt output that is fine once reassembled.
    ///
    /// One consumer. Iterating it twice splits the output between the two.
    public func output() -> AsyncStream<Data> { stream }

    /// A dedicated thread reading the master, for the reason `FileHandleLines`
    /// uses one: corelibs' `readabilityHandler` is not dependable at EOF, and a
    /// terminal that misses the end of its output is a terminal that looks hung.
    ///
    /// It waits on the master **and** the wakeup pipe, so `terminate` can stop
    /// it from another thread — and it owns closing the master, which is what
    /// makes that safe. Reading only after `poll` says there is something keeps
    /// the descriptor blocking, so there is no EAGAIN to handle.
    private func startReading(into continuation: AsyncStream<Data>.Continuation) {
        let thread = Thread { [self] in
            var buffer = [UInt8](repeating: 0, count: 16 * 1024)
            loop: while true {
                var fds = [
                    pollfd(fd: master, events: Int16(POLLIN), revents: 0),
                    pollfd(fd: wakeRead, events: Int16(POLLIN), revents: 0),
                ]
                let ready = poll(&fds, 2, -1)
                if ready < 0 {
                    if errno == EINTR { continue }
                    break
                }
                // Asked to stop. Checked first, so a shell producing output
                // forever cannot keep the terminal open past its teardown.
                if fds[1].revents != 0 { break }
                guard fds[0].revents != 0 else { continue }

                let count = read(master, &buffer, buffer.count)
                if count > 0 {
                    continuation.yield(Data(buffer[0 ..< count]))
                    continue
                }
                // 0 is EOF. EIO is *also* EOF here: Linux reports it on the
                // master once every slave is closed, which is exactly what the
                // shell exiting looks like. EINTR is neither.
                if count == 0 || errno != EINTR { break loop }
            }
            closeDescriptors()
            continuation.finish()
        }
        thread.name = "droidectived.pty"
        thread.start()
    }

    /// Closes the master and the wakeup pipe. Only the reader calls this, once
    /// it has stopped using them — which is what makes closing safe at all.
    private func closeDescriptors() {
        lock.lock()
        let fd = master
        master = -1
        lock.unlock()
        if fd >= 0 { close(fd) }
        close(wakeRead)
        close(wakeWrite)
    }

    /// Waits for the shell and then releases the terminal.
    ///
    /// Closing the parent's slave descriptor is what makes the master report
    /// EOF, and it must not happen before the shell is actually gone — so the
    /// reap and the close are the same step. Without this the reader would sit
    /// on a terminal nobody is attached to and the tab would never close itself.
    private func startReaping() {
        let thread = Thread { [self] in
            var status: Int32 = 0
            waitpid(child, &status, 0)
            closeSlave()
        }
        thread.name = "droidectived.pty.reap"
        thread.start()
    }

    private func closeSlave() {
        lock.lock()
        let fd = slave
        slave = -1
        lock.unlock()
        if fd >= 0 { close(fd) }
    }

    /// Sends keystrokes. Partial writes are looped, because a pty's buffer is
    /// small and a paste is bigger than it.
    ///
    /// The lock is held for the whole write, not just to read the descriptor:
    /// the reader closes the master when it stops, and a write that had already
    /// captured the number would otherwise be writing to whatever the OS handed
    /// out next.
    public func write(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        let fd = closed ? -1 : master
        guard fd >= 0 else { return }
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = Foundation.write(fd, raw.baseAddress?.advanced(by: offset), raw.count - offset)
                if written > 0 {
                    offset += written
                    continue
                }
                if written < 0, errno == EINTR { continue }
                break
            }
        }
    }

    /// Tells the shell the window changed, which is what makes a resized pane
    /// re-wrap instead of drawing to the old width.
    public func resize(to size: PtySize) {
        lock.lock()
        defer { lock.unlock() }
        guard !closed, slave >= 0 else { return }
        _ = droidective_pty_resize(slave, UInt16(size.columns), UInt16(size.rows))
    }

    /// Hangs the shell up.
    ///
    /// SIGHUP rather than SIGKILL: it is what closing a terminal window sends,
    /// so a shell gets to run its exit traps and write its history. The reaping
    /// and the descriptor closes happen on their own threads — a stopped
    /// subscription must not hold up the socket it was on. Idempotent.
    public func terminate() {
        lock.lock()
        guard !closed else {
            lock.unlock()
            return
        }
        closed = true
        let pid = child
        let wake = wakeWrite
        child = 0
        lock.unlock()

        if pid > 0 {
            // The whole process group: a shell with a foreground job has
            // children of its own, and signalling only the shell leaves them.
            kill(-pid, SIGHUP)
            kill(pid, SIGHUP)
        }
        // Wake the reader rather than closing under it. It closes the master
        // itself once it has stopped reading — see `wakeRead`. The slave is
        // closed by the reaper started at spawn, once the shell is really gone.
        var byte: UInt8 = 0
        _ = Foundation.write(wake, &byte, 1)
    }
}

extension Pty: PtyChannel {}

/// Duplicated argv/envp strings, freed together.
///
/// Copied rather than borrowed for the reason `EmulatorService.spawnDetached`
/// copies them: a nil in the middle of the array makes `posix_spawn` silently
/// truncate rather than fail, so an allocation that did not happen has to be
/// caught here.
private struct CStrings {
    private var allocations: [UnsafeMutablePointer<CChar>] = []

    mutating func duplicate(_ value: String) -> UnsafeMutablePointer<CChar>? {
        guard let copy = strdup(value) else { return nil }
        allocations.append(copy)
        return copy
    }

    mutating func array(_ values: [String]) -> [UnsafeMutablePointer<CChar>?]? {
        var pointers: [UnsafeMutablePointer<CChar>?] = []
        for value in values {
            guard let copy = strdup(value) else { return nil }
            allocations.append(copy)
            pointers.append(copy)
        }
        pointers.append(nil)
        return pointers
    }

    mutating func free() {
        for pointer in allocations { Foundation.free(pointer) }
        allocations = []
    }
}

#endif
