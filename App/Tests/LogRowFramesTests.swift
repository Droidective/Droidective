import AppKit
import Testing

/// Which row a click or a sweep lands on. The feeds hand this a y in the feed's
/// coordinate space and every *visible* row's frame; a wrong answer here reads as
/// a selection that starts somewhere the pointer never was.
@MainActor
@Suite struct LogRowFramesTests {
    /// Four 20pt rows stacked from the top, as a feed lays them out.
    private func feed() -> (LogRowFrames<String>, [String]) {
        let frames = LogRowFrames<String>()
        let ids = ["a", "b", "c", "d"]
        for (index, id) in ids.enumerated() {
            frames.frames[id] = CGRect(x: 0, y: CGFloat(index) * 20, width: 400, height: 20)
        }
        return (frames, ids)
    }

    @Test func aYInsideARowPicksThatRow() {
        let (frames, ids) = feed()
        #expect(frames.row(at: 0, among: ids) == "a")
        #expect(frames.row(at: 19.9, among: ids) == "a")
        #expect(frames.row(at: 20, among: ids) == "b")
        #expect(frames.row(at: 50, among: ids) == "c")
        #expect(frames.row(at: 79, among: ids) == "d")
    }

    @Test func draggingPastAnEdgePicksTheNearestRow() {
        let (frames, ids) = feed()
        // Sweeping off the top or the bottom selects to the end rather than
        // stopping where the pointer left the rows.
        #expect(frames.row(at: -500, among: ids) == "a")
        #expect(frames.row(at: 5_000, among: ids) == "d")
    }

    @Test func aRowThatScrolledAwayIsNotConsidered() {
        let (frames, ids) = feed()
        // What a `LazyVStack` does when a row leaves: the row stops reporting and
        // its frame is dropped. Without the drop, its last frame would still
        // answer for clicks — which is how a sweep could begin on a row nowhere
        // near the pointer.
        frames.frames["a"] = nil
        frames.frames["b"] = nil
        #expect(frames.row(at: 5, among: ids) == "c")
        #expect(frames.row(at: 45, among: ids) == "c")
    }

    @Test func anEmptyFeedAnswersNothing() {
        let frames = LogRowFrames<String>()
        #expect(frames.row(at: 10, among: ["a", "b"]) == nil)
        let (populated, _) = feed()
        // Ids the feed no longer lists are never returned, even with a frame.
        #expect(populated.row(at: 10, among: []) == nil)
    }

    @Test func onlyTheRowsTheFeedListsAreCandidates() {
        let (frames, _) = feed()
        // A filter narrowed the feed to two rows: a click in the gap between them
        // resolves within that subset, never to a row that is filtered out.
        #expect(frames.row(at: 25, among: ["a", "d"]) == "a")
        #expect(frames.row(at: 65, among: ["a", "d"]) == "d")
    }

    @Test func modifiersMapToWhatAClickMeans() {
        #expect(LogRowClick(modifiers: []) == .plain)
        #expect(LogRowClick(modifiers: .command) == .toggle)
        #expect(LogRowClick(modifiers: .shift) == .extend)
        // ⌘ wins: a ⌘⇧-click adds one row rather than sweeping a range.
        #expect(LogRowClick(modifiers: [.command, .shift]) == .toggle)
        // Modifiers the feeds don't claim leave the click plain.
        #expect(LogRowClick(modifiers: .control) == .plain)
    }
}
