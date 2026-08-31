import Foundation

/// One ffmpeg process being fed video over its standard input.
///
/// `ProcessRunning` cannot do this: it runs a command to completion and hands
/// back what it printed, where a recording writes for as long as someone is
/// recording. So this is the one place in the daemon that drives `Process`
/// directly, and it is deliberately small — spawn, write, close, wait.
///
/// **Backpressure rather than dropping.** A dropped frame in an H.264 stream is
/// not a missing moment, it is every following frame referring to something
/// that never arrived. If ffmpeg falls behind, writes queue; past `maxBacklog`
/// the recording *fails* and says so, because a file that decodes into garbage
/// is worse than one that was never made.
actor FfmpegPipe {
    enum PipeError: Error, LocalizedError, Equatable {
        case launchFailed(String)
        case backlogExceeded
        case exited(code: Int32, stderrTail: String)

        var errorDescription: String? {
            switch self {
            case .launchFailed(let reason):
                return "Couldn't start ffmpeg: \(reason)"
            case .backlogExceeded:
                return "ffmpeg couldn't keep up with the device's stream."
            case .exited(let code, let tail):
                return tail.isEmpty
                    ? "ffmpeg exited with code \(code)."
                    : "ffmpeg exited with code \(code):\n\(tail)"
            }
        }
    }

    /// Bytes allowed to sit unwritten. About two seconds of a high-bitrate
    /// stream — enough to ride out a scheduling hiccup, far short of a leak.
    static let maxBacklog = 8 << 20

    private let executable: String
    private let arguments: [String]
    private let process = Process()
    private let input = Pipe()
    private let errors = Pipe()
    /// Writes happen off the actor: a pipe write blocks when the reader is
    /// behind, and blocking an actor would stall the frame pump that feeds it.
    private let writer: DispatchQueue
    private let state = PipeState()
    private var launched = false

    init(executable: String, arguments: [String], label: String) {
        self.executable = executable
        self.arguments = arguments
        writer = DispatchQueue(label: "droidectived.ffmpeg.\(label)")
    }

    func start() throws {
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        // ffmpeg is chatty on stderr and only the tail is ever useful, so it is
        // read as it arrives rather than left to fill the pipe — a full stderr
        // pipe deadlocks the process it belongs to.
        errors.fileHandleForReading.readabilityHandler = { [state] handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            state.appendError(chunk)
        }
        do {
            try process.run()
            launched = true
        } catch {
            throw PipeError.launchFailed("\(error)")
        }
    }

    /// Queue bytes for ffmpeg. Throws once the backlog says it cannot keep up.
    func write(_ data: Data) throws {
        guard launched else { return }
        guard state.reserve(data.count, limit: Self.maxBacklog) else {
            throw PipeError.backlogExceeded
        }
        let handle = input.fileHandleForWriting
        writer.async { [state] in
            defer { state.release(data.count) }
            // A broken pipe means ffmpeg has already gone; the exit code from
            // `finish` is the useful report, not a signal raised here.
            try? handle.write(contentsOf: data)
        }
    }

    /// Close the input and wait. Answers ffmpeg's exit status and its last words.
    func finish() async -> Result<Void, PipeError> {
        guard launched else { return .success(()) }
        await drainWrites()
        try? input.fileHandleForWriting.close()
        await waitForExit()
        let tail = state.errorTail()
        let code = process.terminationStatus
        return code == 0 ? .success(()) : .failure(.exited(code: code, stderrTail: tail))
    }

    /// Give up on this file: kill ffmpeg rather than let it finish writing one
    /// nobody asked for.
    func cancel() {
        guard launched, process.isRunning else { return }
        process.terminate()
        try? input.fileHandleForWriting.close()
    }

    /// Everything already queued has reached the pipe.
    private func drainWrites() async {
        await withCheckedContinuation { continuation in
            writer.async { continuation.resume() }
        }
    }

    private func waitForExit() async {
        await withCheckedContinuation { continuation in
            // `waitUntilExit` blocks, so it goes on a thread of its own rather
            // than a cooperative one — the rule `SystemProcessRunner` follows
            // for the same reason.
            Thread.detachNewThread { [process] in
                process.waitUntilExit()
                continuation.resume()
            }
        }
    }
}

/// The bits of a pipe's state that two queues touch: how much is waiting to be
/// written, and what ffmpeg has said. A lock rather than an actor because the
/// writer queue and the readability handler are not async contexts.
private final class PipeState: @unchecked Sendable {
    private let lock = NSLock()
    private var queued = 0
    private var errorBytes = Data()

    /// The last of what ffmpeg printed. A cap, because a failing ffmpeg can
    /// print a line per frame.
    static let maxErrorBytes = 64 << 10

    func reserve(_ bytes: Int, limit: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard queued + bytes <= limit else { return false }
        queued += bytes
        return true
    }

    func release(_ bytes: Int) {
        lock.lock()
        queued -= bytes
        lock.unlock()
    }

    func appendError(_ chunk: Data) {
        lock.lock()
        errorBytes.append(chunk)
        if errorBytes.count > Self.maxErrorBytes {
            errorBytes = errorBytes.suffix(Self.maxErrorBytes)
        }
        lock.unlock()
    }

    func errorTail() -> String {
        lock.lock()
        defer { lock.unlock() }
        let text = String(decoding: errorBytes, as: UTF8.self)
        // The last few lines are the ones that name the problem; everything
        // above is ffmpeg's banner and its per-frame progress.
        return text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .suffix(6)
            .joined(separator: "\n")
    }
}
