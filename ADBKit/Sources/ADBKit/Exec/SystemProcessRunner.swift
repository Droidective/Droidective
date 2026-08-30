import Foundation

/// Foundation.Process-backed runner.
///
/// Fully non-blocking: pipes are drained via `readabilityHandler` callbacks
/// and exit is observed via `terminationHandler`, so no Swift-concurrency
/// cooperative thread is ever parked. (A blocking `waitUntilExit`/
/// `availableData` design starves the cooperative pool once a few adb calls
/// overlap — device polling + a feature run is enough — wedging the whole
/// async runtime.) A watchdog escalates SIGTERM → SIGKILL on timeout, except
/// on Windows where `terminate()` is already TerminateProcess.
public struct SystemProcessRunner: ProcessRunning {
    public init() {}

    public func run(
        executable: String,
        arguments: [String],
        timeout: Duration,
        maxOutputBytes: Int
    ) async -> ProcessOutput {
        await Self.run(
            executable: executable,
            arguments: arguments,
            environment: nil,
            timeout: timeout,
            maxOutputBytes: maxOutputBytes
        )
    }

    /// Full-control variant used by tool launchers that need env overrides
    /// (e.g. scrcpy, which resolves `adb` via PATH/ADB).
    public static func run(
        executable: String,
        arguments: [String],
        environment: [String: String]?,
        timeout: Duration,
        maxOutputBytes: Int
    ) async -> ProcessOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }
        process.standardInput = FileHandle.nullDevice
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let stdout = PipeCollector(cap: maxOutputBytes)
        let stderr = PipeCollector(cap: maxOutputBytes)
        stdout.attach(outPipe.fileHandleForReading)
        stderr.attach(errPipe.fileHandleForReading)

        let timedOut = LockedBox(false)
        let cancelled = LockedBox(false)
        // Set once *we* have reaped the child ourselves (see `ExitReaper`,
        // which runs off-Darwin only). After that its pid may be recycled by
        // the kernel, so nothing may signal it again — terminating a stranger
        // is worse than any hang. Never set on Darwin, where the guards below
        // are a constant false.
        let reaped = LockedBox(false)
        let boxed = UncheckedSendable(process)

        return await withTaskCancellationHandler {
            // Started before the exit await so it runs concurrently; Task.sleep
            // parks no thread. `isRunning` is false both before launch and after
            // exit, so terminate() is only ever sent to a live process — and the
            // timedOut flag is only set when termination was actually forced
            // (a process exiting cleanly right at the deadline isn't a timeout).
            let watchdog = Task {
                try await Task.sleep(for: timeout)
                if boxed.value.isRunning, !reaped.get() {
                    timedOut.set(true)
                    boxed.value.terminate()
                }
                // Windows has no SIGKILL, and needs none: Foundation maps
                // `terminate()` to TerminateProcess, which is already the
                // forceful kill rather than a request to exit. POSIX hosts keep
                // the SIGTERM → SIGKILL escalation for a child that ignores the
                // first signal.
                #if !os(Windows)
                try await Task.sleep(for: .seconds(2))
                if boxed.value.isRunning, !reaped.get() {
                    kill(boxed.value.processIdentifier, SIGKILL)
                }
                #endif
            }

            let exitCode: Int32? = await withCheckedContinuation { continuation in
                let resumed = LockedBox(false)
                process.terminationHandler = { finished in
                    guard !resumed.swap(true) else { return }
                    #if os(Windows)
                    // Windows has no signals, so `.uncaughtSignal` is not a
                    // state a child can reach — and corelibs reports a
                    // non-`.exit` reason for an ordinary non-zero exit just as
                    // it does for a TerminateProcess kill, so the reason
                    // cannot tell those apart. (`exit /b 3` came back with no
                    // exit code at all, while its stderr arrived intact.)
                    //
                    // We already know which kills are ours: the watchdog and
                    // the cancellation handler each raise a flag before
                    // terminating. Trust those, and take the status at face
                    // value otherwise.
                    let killed = timedOut.get() || cancelled.get()
                    continuation.resume(returning: killed ? nil : finished.terminationStatus)
                    #else
                    let exited = finished.terminationReason == .exit
                    continuation.resume(returning: exited ? finished.terminationStatus : nil)
                    #endif
                }
                do {
                    try process.run()
                    // Cancelled during launch: tear the child down now so it
                    // doesn't keep running after the caller's Task is gone.
                    if cancelled.get(), boxed.value.isRunning { boxed.value.terminate() }
                    #if !canImport(Darwin) && !os(Windows)
                    ExitReaper.watch(
                        pid: boxed.value.processIdentifier,
                        onExit: { status in
                            guard !resumed.swap(true) else { return }
                            reaped.set(true)
                            continuation.resume(returning: status)
                        })
                    #endif
                } catch {
                    guard !resumed.swap(true) else { return }
                    stdout.cancel(outPipe.fileHandleForReading)
                    stderr.cancel(errPipe.fileHandleForReading)
                    stderr.injectFailure("failed to launch \(executable): \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                }
            }
            watchdog.cancel()

            // Bounded: a grandchild (e.g. a spawned daemon) can inherit the pipe
            // and delay EOF past the parent's exit.
            await stdout.waitUntilEOF(grace: .seconds(3))
            await stderr.waitUntilEOF(grace: .seconds(3))

            return ProcessOutput(
                stdout: stdout.data,
                stderr: stderr.data,
                exitCode: timedOut.get() ? nil : exitCode,
                timedOut: timedOut.get()
            )
        } onCancel: {
            // Cancelling the calling Task (e.g. a SwiftUI .task torn down on
            // navigation, or a .task(id:) re-keying) must kill the child so
            // run() returns promptly and no orphaned adb process lingers until
            // its timeout. SIGTERM first, then SIGKILL for anything ignoring it
            // (POSIX only — Windows' terminate() is already TerminateProcess).
            cancelled.set(true)
            // `reaped` guards every signal: once we have waited on the pid
            // ourselves the kernel may hand that number to someone else, and
            // `Process.isRunning` does not know we did — it is the corelibs
            // bookkeeping that missed the exit in the first place.
            if boxed.value.isRunning, !reaped.get() { boxed.value.terminate() }
            #if !os(Windows)
            Task {
                try? await Task.sleep(for: .seconds(2))
                if boxed.value.isRunning, !reaped.get() {
                    kill(boxed.value.processIdentifier, SIGKILL)
                }
            }
            #endif
        }
    }
}

#if !canImport(Darwin) && !os(Windows)
/// A second way to notice a child has exited, because the first one can miss.
///
/// `Process.terminationHandler` is the primary path and normally fires within
/// milliseconds. It does not always: on Linux, `adb devices` run on a machine
/// where the adb *server* is not yet up forks that server, exits, and is left a
/// **zombie** — corelibs never reaps it and never calls the handler, so the
/// continuation waiting on it is suspended for the life of the process. The
/// watchdog is no escape either: its only recovery is terminating a process
/// that is still running, and this one is already gone.
///
/// That is not a hypothetical. It is what the first launch of the Linux app
/// did: `list_features` answered with all 61 features while `list_devices`
/// never returned, so the window came up with an empty sidebar, "0 features",
/// and no error to explain it — the client was still awaiting a promise that
/// would never settle.
///
/// So this polls `waitpid(WNOHANG)` and reports the exit itself. Racing
/// corelibs for the reap is safe in both directions: whoever wins resumes the
/// continuation exactly once (`resumed`), and the loser's `waitpid` answers
/// -1/ECHILD and does nothing. What is *not* safe is signalling a pid after it
/// has been reaped — the number can be recycled — which is why a win here
/// raises `reaped` and the watchdog checks it.
///
/// **Off-Darwin only, deliberately.** This is a corelibs gap: Darwin's
/// `Process` reaps and reports reliably, and the Mac app is the shipping one —
/// racing Foundation for a `waitpid` there would be a change to a proven path
/// in exchange for fixing nothing. The pipe collectors are split the same way
/// and for the same kind of reason.
///
/// One thread for every child in flight, parked in `nanosleep`, which is a
/// thread the cooperative pool does not own — the same reason the pipe
/// collectors get their own.
enum ExitReaper {
    /// How often to ask. Short enough that a missed handler costs no visible
    /// delay, long enough that a hundred concurrent children are not a hundred
    /// busy loops.
    private static let interval = 0.05

    static func watch(pid: pid_t, onExit: @escaping @Sendable (Int32) -> Void) {
        let thread = Thread {
            var status: Int32 = 0
            while true {
                let answer = waitpid(pid, &status, WNOHANG)
                if answer == pid {
                    // The exit status the way the shell reports it: the low
                    // byte for a signal, the high byte for a plain exit.
                    let code: Int32
                    if status & 0x7F == 0 {
                        code = (status >> 8) & 0xFF
                    } else {
                        // Killed. `Process` reports these as a non-`.exit`
                        // reason, which `run` turns into a nil exit code, so
                        // the shell's 128+signal is the closest honest answer.
                        code = 128 + (status & 0x7F)
                    }
                    onExit(code)
                    return
                }
                // -1 means somebody else reaped it (corelibs, normally) or it
                // was never ours; either way there is nothing left to watch.
                if answer == -1 { return }
                Thread.sleep(forTimeInterval: interval)
            }
        }
        thread.name = "adbkit-exit-reaper"
        thread.stackSize = 128 * 1024
        thread.start()
    }
}
#endif

/// Accumulates one pipe's output via readabilityHandler (no blocked thread)
/// and lets a waiter await EOF.
final class PipeCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var finished = false
    private var waiter: CheckedContinuation<Void, Never>?
    private let cap: Int

    init(cap: Int) {
        self.cap = cap
    }

    private weak var handle: FileHandle?

    func attach(_ handle: FileHandle) {
        lock.lock()
        self.handle = handle
        lock.unlock()
        #if canImport(Darwin)
        handle.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                try? handle.close()
                self?.finish()
            } else {
                self?.append(chunk)
            }
        }
        #else
        // corelibs never delivers the empty EOF callback when the last data
        // and the writer's close arrive together (verified on 6.2), so the
        // handler-based spelling hangs. A dedicated blocking-read thread is
        // the reliable one: read() returns empty exactly at EOF. The thread
        // retains the handle, so the fd can't be closed-and-reused under a
        // read; it closes with the handle after the thread ends.
        let boxed = UncheckedSendable(handle)
        let thread = Thread { [weak self] in
            while true {
                let chunk = boxed.value.availableData
                if chunk.isEmpty { break }
                self?.append(chunk)
            }
            self?.finish()
        }
        thread.name = "adbkit-pipe-collector"
        thread.stackSize = 512 * 1024
        thread.start()
        #endif
    }

    /// Detach the handler, close the FD, and mark finished. Off-Darwin the
    /// reader thread owns the fd (closing here could re-issue the fd number
    /// under its blocked read); the child's termination EOFs it instead.
    func cancel(_ handle: FileHandle) {
        #if canImport(Darwin)
        handle.readabilityHandler = nil
        try? handle.close()
        #endif
        finish()
    }

    func injectFailure(_ message: String) {
        lock.lock()
        buffer = Data(message.utf8)
        lock.unlock()
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    private func currentHandle() -> FileHandle? {
        lock.lock()
        defer { lock.unlock() }
        return handle
    }

    func waitUntilEOF(grace: Duration) async {
        // On expiry, also tear down the read source — a grandchild holding
        // the pipe's write end would otherwise keep the FD and handler alive
        // (and collecting) long after run() has returned.
        let deadline = Task { [weak self] in
            try await Task.sleep(for: grace)
            guard let self else { return }
            if let handle = self.currentHandle() {
                self.cancel(handle)
            } else {
                self.finish()
            }
        }
        await withCheckedContinuation { continuation in
            lock.lock()
            if finished {
                lock.unlock()
                continuation.resume()
                return
            }
            waiter = continuation
            lock.unlock()
        }
        deadline.cancel()
    }

    private func append(_ chunk: Data) {
        lock.lock()
        if buffer.count < cap {
            buffer.append(chunk.prefix(cap - buffer.count))
        }
        lock.unlock()
    }

    private func finish() {
        lock.lock()
        finished = true
        let waiting = waiter
        waiter = nil
        lock.unlock()
        waiting?.resume()
    }
}

/// Confines a non-Sendable value we know is used safely across one task hop.
struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

final class LockedBox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T

    init(_ value: T) { self.value = value }

    func get() -> T {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: T) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    /// Swap in a new value, returning the previous one (atomic test-and-set).
    @discardableResult
    func swap(_ newValue: T) -> T {
        lock.lock()
        defer { lock.unlock() }
        let old = value
        value = newValue
        return old
    }
}
