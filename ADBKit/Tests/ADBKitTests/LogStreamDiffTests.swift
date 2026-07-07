import Foundation
import Testing
@testable import ADBKit

@Suite("LogStreamDiff")
struct LogStreamDiffTests {
    private func ids(_ count: Int) -> [UUID] {
        (0..<count).map { _ in UUID() }
    }

    @Test func identicalBuffersAreUnchanged() {
        let lines = ids(3)
        #expect(LogStreamDiff.plan(rendered: lines, incoming: lines) == .unchanged)
    }

    @Test func bothEmptyIsUnchanged() {
        #expect(LogStreamDiff.plan(rendered: [], incoming: []) == .unchanged)
    }

    @Test func pureAppendKeepsTheHead() {
        let rendered = ids(3)
        let incoming = rendered + ids(2)
        #expect(
            LogStreamDiff.plan(rendered: rendered, incoming: incoming)
                == .edit(dropHead: 0, appendFrom: 3)
        )
    }

    @Test func ringTrimDropsTheHead() {
        let rendered = ids(5)
        let incoming = Array(rendered.dropFirst(2))
        #expect(
            LogStreamDiff.plan(rendered: rendered, incoming: incoming)
                == .edit(dropHead: 2, appendFrom: 3)
        )
    }

    @Test func trimAndAppendCombine() {
        let rendered = ids(5)
        let incoming = Array(rendered.dropFirst(2)) + ids(4)
        #expect(
            LogStreamDiff.plan(rendered: rendered, incoming: incoming)
                == .edit(dropHead: 2, appendFrom: 3)
        )
    }

    @Test func clearedBufferRebuilds() {
        #expect(LogStreamDiff.plan(rendered: ids(3), incoming: []) == .rebuild)
    }

    @Test func firstContentRebuilds() {
        #expect(LogStreamDiff.plan(rendered: [], incoming: ids(3)) == .rebuild)
    }

    @Test func disjointBuffersRebuild() {
        #expect(LogStreamDiff.plan(rendered: ids(3), incoming: ids(3)) == .rebuild)
    }

    @Test func interiorGapRebuilds() {
        // A filter change that keeps the head but drops interior lines isn't
        // a trim + append shape — the overlap-count check catches it.
        let rendered = ids(4)
        let incoming = [rendered[0], rendered[1], rendered[3]]
        #expect(LogStreamDiff.plan(rendered: rendered, incoming: incoming) == .rebuild)
    }

    @Test func changedTailRebuilds() {
        // Same head, but the rendered tail was replaced instead of extended.
        let rendered = ids(3)
        let incoming = [rendered[0], rendered[1], UUID(), rendered[2]]
        #expect(LogStreamDiff.plan(rendered: rendered, incoming: incoming) == .rebuild)
    }
}
