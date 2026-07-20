import Foundation
import Testing
@testable import ADBKit

@Suite struct FileHandleLinesTests {
    /// Chunks arriving mid-line, CRLF endings, an emoji whose UTF-8 bytes
    /// straddle a chunk boundary, and an unterminated tail all assemble into
    /// the right lines.
    @Test(.timeLimit(.minutes(1)))
    func assemblesChunksIntoLines() async throws {
        let pipe = Pipe()
        let reading = UncheckedSendable(pipe.fileHandleForReading)
        let linesTask = Task {
            var lines: [String] = []
            for await line in FileHandleLines.lines(of: reading.value) {
                lines.append(line)
            }
            return lines
        }

        let writer = pipe.fileHandleForWriting
        let payload = "plain\r\nsecond 🐟 line\nunterminated tail"
        let bytes = Array(payload.utf8)
        // 3-byte writes so the CRLF pair and the fish's four UTF-8 bytes land
        // split across chunks.
        for start in stride(from: 0, to: bytes.count, by: 3) {
            let chunk = bytes[start ..< min(start + 3, bytes.count)]
            try writer.write(contentsOf: Data(chunk))
        }
        try writer.close()

        let lines = await linesTask.value
        #expect(lines == ["plain", "second 🐟 line", "unterminated tail"])
    }

    @Test(.timeLimit(.minutes(1)))
    func immediateEOFYieldsNoLines() async throws {
        let pipe = Pipe()
        let reading = UncheckedSendable(pipe.fileHandleForReading)
        let linesTask = Task {
            var lines: [String] = []
            for await line in FileHandleLines.lines(of: reading.value) {
                lines.append(line)
            }
            return lines
        }
        try pipe.fileHandleForWriting.close()
        #expect(await linesTask.value == [])
    }

    /// Blank lines are real lines (logcat's parser decides what to skip) —
    /// and a terminated final line must not re-emit at EOF.
    @Test(.timeLimit(.minutes(1)))
    func keepsBlankLinesAndDoesNotDuplicateTheFinalOne() async throws {
        let pipe = Pipe()
        let reading = UncheckedSendable(pipe.fileHandleForReading)
        let linesTask = Task {
            var lines: [String] = []
            for await line in FileHandleLines.lines(of: reading.value) {
                lines.append(line)
            }
            return lines
        }
        let writer = pipe.fileHandleForWriting
        try writer.write(contentsOf: Data("a\n\nb\n".utf8))
        try writer.close()
        #expect(await linesTask.value == ["a", "", "b"])
    }
}
