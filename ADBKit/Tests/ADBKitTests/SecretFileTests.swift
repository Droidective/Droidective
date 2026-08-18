import Foundation
import Testing
@testable import ADBKit

@Suite struct SecretFileTests {
    @Test func writesTheSecretAndReturnsItsPath() throws {
        let path = try SecretFile.write("s3cret", prefix: "test-secret-")
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "s3cret")
    }

    @Test func namesTheFileByItsPrefixInsideTheTempDirectory() throws {
        let path = try SecretFile.write("x", prefix: "test-prefix-")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let name = URL(fileURLWithPath: path).lastPathComponent
        #expect(name.hasPrefix("test-prefix-"))
        // Same directory the caller's cleanup and the tool both expect.
        #expect(URL(fileURLWithPath: path).deletingLastPathComponent().standardizedFileURL
            == FileManager.default.temporaryDirectory.standardizedFileURL)
    }

    /// Two signing runs at once must not hand the same path to two tools —
    /// one would delete the other's password file mid-run.
    @Test func everyCallGetsItsOwnFile() throws {
        let first = try SecretFile.write("a", prefix: "test-unique-")
        let second = try SecretFile.write("b", prefix: "test-unique-")
        defer {
            try? FileManager.default.removeItem(atPath: first)
            try? FileManager.default.removeItem(atPath: second)
        }
        #expect(first != second)
        #expect(try String(contentsOfFile: first, encoding: .utf8) == "a")
        #expect(try String(contentsOfFile: second, encoding: .utf8) == "b")
    }

    /// The whole point of the file: the password is unreadable to anyone else.
    /// Windows doesn't enforce POSIX modes (the temp directory's ACL does), and
    /// `restrictToOwner` is best-effort there, so this asserts where it means
    /// something.
    #if !os(Windows)
    @Test func theFileIsReadableOnlyByItsOwner() throws {
        let path = try SecretFile.write("s3cret", prefix: "test-mode-")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let mode = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber
        #expect(mode?.int16Value == 0o600)
    }
    #endif

    @Test func anEmptySecretStillProducesAFile() throws {
        let path = try SecretFile.write("", prefix: "test-empty-")
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "")
    }

    /// A failure has to name the path and carry the underlying reason — the
    /// Bool-returning API it replaced is why a Windows CI failure arrived with
    /// nothing to diagnose.
    @Test func aFailureSaysWhereAndWhy() {
        #expect(throws: SecretFile.Failure.self) {
            try SecretFile.write("x", prefix: "no/such/directory/test-")
        }
        let failure = SecretFile.Failure.writeFailed("Couldn't write the secret file at /x: nope")
        #expect(failure.errorDescription?.contains("/x") == true)
        #expect(failure.errorDescription?.contains("nope") == true)
    }
}
