import Testing
@testable import ADBKit

/// Cap enforcement for the Reactotron timeline ring buffer: appends past
/// either cap trim oldest-first, in batches, and always keep the newest item.
@Suite struct ReactotronTimelineTests {
    @Test func underBothCapsDropsNothing() {
        let drop = ReactotronTimeline.dropCount(
            sizes: Array(repeating: 10, count: 50), count: 50, totalBytes: 500,
            maxCount: 100, maxBytes: 10_000
        )
        #expect(drop == 0)
    }

    @Test func exactlyAtTheCapsDropsNothing() {
        let drop = ReactotronTimeline.dropCount(
            sizes: Array(repeating: 100, count: 100), count: 100, totalBytes: 10_000,
            maxCount: 100, maxBytes: 10_000
        )
        #expect(drop == 0)
    }

    @Test func countOverflowTrimsOldestInABatchNotOneByOne() {
        // One item over the cap trims down to the 7/8 low-water mark in a
        // single batch, so steady-state appends don't shift the buffer every time.
        let count = 101
        let drop = ReactotronTimeline.dropCount(
            sizes: Array(repeating: 1, count: count), count: count, totalBytes: count,
            maxCount: 100, maxBytes: 1_000_000
        )
        #expect(drop == count - (100 - 100 / 8))
        #expect(drop > 1)
    }

    @Test func byteOverflowTrimsOldestUntilUnderBudget() {
        // 10 × 30 bytes = 300 against a 100-byte budget: trim to the 87-byte
        // low-water mark → 8 oldest dropped, 2 newest (60 bytes) kept.
        let sizes = Array(repeating: 30, count: 10)
        let drop = ReactotronTimeline.dropCount(
            sizes: sizes, count: 10, totalBytes: 300, maxCount: 1000, maxBytes: 100
        )
        #expect(drop == 8)
        #expect(300 - sizes.prefix(drop).reduce(0, +) <= 100)
    }

    @Test func oversizedNewestItemIsAlwaysKept() {
        // A single frame bigger than the whole budget evicts everything older
        // but is itself retained — the buffer never trims to empty.
        let twoItems = ReactotronTimeline.dropCount(
            sizes: [500, 900], count: 2, totalBytes: 1400, maxCount: 10, maxBytes: 100
        )
        #expect(twoItems == 1)
        let single = ReactotronTimeline.dropCount(
            sizes: [900], count: 1, totalBytes: 900, maxCount: 10, maxBytes: 100
        )
        #expect(single == 0)
    }

    @Test func appendLoopKeepsBufferWithinCapsAndKeepsNewest() {
        // Drive the session's append/trim loop shape: after every append the
        // buffer honors both caps and the newest element survives.
        var sizes: [Int] = []
        var total = 0
        for value in 0 ..< 5000 {
            sizes.append(value % 100)
            total += value % 100
            let drop = ReactotronTimeline.dropCount(
                sizes: sizes, count: sizes.count, totalBytes: total,
                maxCount: 200, maxBytes: 5000
            )
            if drop > 0 {
                total -= sizes.prefix(drop).reduce(0, +)
                sizes.removeFirst(drop)
            }
            #expect(sizes.count <= 200)
            #expect(total <= 5000)
            #expect(sizes.last == value % 100)
        }
    }
}
