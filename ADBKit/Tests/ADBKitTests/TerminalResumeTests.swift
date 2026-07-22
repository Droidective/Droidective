import Testing
@testable import ADBKit

@Suite("TerminalResume")
struct TerminalResumeTests {
    @Test func keepsDirectoriesInDisplayOrder() {
        #expect(TerminalResume.snapshot(["/a", "/b", "/c"]) == ["/a", "/b", "/c"])
    }

    /// Duplicate directories are legitimate — two shells in one project — so
    /// the snapshot must not dedupe.
    @Test func keepsDuplicates() {
        #expect(TerminalResume.snapshot(["/a", "/a"]) == ["/a", "/a"])
    }

    @Test func dropsBlankEntries() {
        #expect(TerminalResume.snapshot(["/a", "", "/b"]) == ["/a", "/b"])
    }

    @Test func capsAtMaxKeepingTheFirst() {
        let many = (1...20).map { "/dir\($0)" }
        let snapshot = TerminalResume.snapshot(many)
        #expect(snapshot.count == TerminalResume.maxRemembered)
        #expect(snapshot.first == "/dir1")
        #expect(snapshot.last == "/dir\(TerminalResume.maxRemembered)")
    }

    @Test func emptyInEmptyOut() {
        #expect(TerminalResume.snapshot([]) == [])
    }
}
