import Foundation

/// Async line iteration over a `FileHandle`, portable across Foundations.
///
/// `FileHandle.bytes` is Darwin-only, so the streaming readers (logcat, the
/// simulator log) assemble lines here instead: split on `\n` with a trailing
/// `\r` dropped (CRLF-tolerant), decode as lossy UTF-8 (safe to split at
/// `\n`: 0x0A never occurs inside a multi-byte scalar), and flush an
/// unterminated tail at EOF.
///
/// Darwin rides `readabilityHandler` (the same non-blocking pattern as
/// `SystemProcessRunner`). corelibs never delivers that handler's empty EOF
/// callback when the final data and the writer's close arrive together
/// (verified on 6.2), so off-Darwin a dedicated blocking-read thread reads
/// until `read()` returns empty — the reliable EOF signal.
enum FileHandleLines {
    static func lines(of handle: FileHandle) -> AsyncStream<String> {
        let boxed = UncheckedSendable(handle)
        let assembler = LineAssembler()
        return AsyncStream { continuation in
            #if canImport(Darwin)
            boxed.value.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    // EOF. Without clearing the handler the callback refires
                    // in a tight loop forever (see SystemProcessRunner).
                    handle.readabilityHandler = nil
                    if let tail = assembler.drain() {
                        continuation.yield(tail)
                    }
                    continuation.finish()
                    return
                }
                for line in assembler.split(appending: data) {
                    continuation.yield(line)
                }
            }
            continuation.onTermination = { _ in
                boxed.value.readabilityHandler = nil
            }
            #else
            // The thread retains the handle, so the fd can't be closed and
            // reused under its blocked read; it closes with the handle after
            // the stream's writer (the child process) goes away.
            let thread = Thread {
                while true {
                    let data = boxed.value.availableData
                    if data.isEmpty { break }
                    for line in assembler.split(appending: data) {
                        continuation.yield(line)
                    }
                }
                if let tail = assembler.drain() {
                    continuation.yield(tail)
                }
                continuation.finish()
            }
            thread.name = "adbkit-line-reader"
            thread.stackSize = 512 * 1024
            thread.start()
            #endif
        }
    }
}

/// Chunk-to-line assembly for `FileHandleLines`. Readability callbacks arrive
/// serially on the handle's dispatch source, so single-threaded access is the
/// contract — `@unchecked Sendable` only to ride the `@Sendable` callback.
private final class LineAssembler: @unchecked Sendable {
    private var buffer = Data()

    /// Append a chunk and return every full line now available.
    func split(appending data: Data) -> [String] {
        buffer.append(data)
        var lines: [String] = []
        var start = buffer.startIndex
        while let newline = buffer[start...].firstIndex(of: 0x0A) {
            var end = newline
            if end > start, buffer[buffer.index(before: end)] == 0x0D {
                end = buffer.index(before: end)
            }
            lines.append(String(decoding: buffer[start ..< end], as: UTF8.self))
            start = buffer.index(after: newline)
        }
        if start != buffer.startIndex {
            buffer = Data(buffer[start...])
        }
        return lines
    }

    /// The unterminated final line at EOF, if any.
    func drain() -> String? {
        guard !buffer.isEmpty else { return nil }
        defer { buffer.removeAll() }
        return String(decoding: buffer, as: UTF8.self)
    }
}
