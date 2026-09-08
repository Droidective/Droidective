import Foundation
import Testing
@testable import ADBKit

/// The retained-memory budget for a streaming feed. The regression these guard
/// is a *machine-wide* one: a wire-byte cap that ignored both the decoded cost
/// and the size of the machine put 8 GB Macs into swap, at which point the
/// report is "the whole Mac stopped responding" rather than "this app is slow".
@Suite struct FeedMemoryBudgetTests {
    private static let gigabyte: UInt64 = 1 << 30

    // MARK: - The regression

    /// The old cap was a flat 128 MB of wire bytes, which at the measured
    /// decode multiple is about a gigabyte resident. No machine may reach that
    /// again — not even a very large one, where the count cap bites first
    /// anyway.
    @Test func noMachineGetsTheOldGigabyteBudget() {
        for gigabytes: UInt64 in [2, 4, 8, 16, 32, 64, 128] {
            let decoded = FeedMemoryBudget.decodedBudget(
                physicalMemory: gigabytes * Self.gigabyte)
            #expect(decoded <= FeedMemoryBudget.maximumDecodedBytes)
            #expect(decoded < 512 << 20, "\(gigabytes) GB machine budgeted \(decoded) bytes")
        }
    }

    /// The machine the incidents happened on: 8 GB, with under 200 MB free.
    /// Two feeds streaming at once is the shape that was reported (a
    /// Reactotron tab and a JS Console tab), so what matters is that *both*
    /// together stay a modest share of the machine.
    @Test func twoFeedsOnAnEightGigMachineStayWellUnderASixth() {
        let physical = 8 * Self.gigabyte
        let bothFeeds = 2 * FeedMemoryBudget.decodedBudget(physicalMemory: physical)
        #expect(Double(bothFeeds) < Double(physical) / 6)
    }

    // MARK: - Shape

    @Test func theBudgetGrowsWithTheMachineUntilItCaps() {
        let small = FeedMemoryBudget.decodedBudget(physicalMemory: 4 * Self.gigabyte)
        let medium = FeedMemoryBudget.decodedBudget(physicalMemory: 8 * Self.gigabyte)
        #expect(small < medium)
        #expect(medium == FeedMemoryBudget.maximumDecodedBytes)
    }

    /// A tiny machine still keeps a usable amount of history: a feed that
    /// evicted what it had just received would be worse than a slow one.
    @Test func aTinyMachineGetsTheFloorNotAScrap() {
        let decoded = FeedMemoryBudget.decodedBudget(physicalMemory: 1 * Self.gigabyte)
        #expect(decoded == FeedMemoryBudget.minimumDecodedBytes)
        #expect(FeedMemoryBudget.wireBudget(physicalMemory: 1 * Self.gigabyte) > 0)
    }

    @Test func zeroPhysicalMemoryStillYieldsTheFloor() {
        // `physicalMemory` should never be zero, but a budget that came back
        // as zero would evict every row the moment it arrived.
        #expect(FeedMemoryBudget.decodedBudget(physicalMemory: 0)
            == FeedMemoryBudget.minimumDecodedBytes)
    }

    @Test func theBudgetIsMonotonicInMachineSize() {
        var previous = 0
        for gigabytes: UInt64 in [1, 2, 4, 8, 16, 32, 64] {
            let decoded = FeedMemoryBudget.decodedBudget(
                physicalMemory: gigabytes * Self.gigabyte)
            #expect(decoded >= previous)
            previous = decoded
        }
    }

    // MARK: - Wire vs resident

    /// The whole point of the type: what a feed caps is wire bytes, and what
    /// the machine feels is the decoded graph. The wire budget must be the
    /// resident one divided by the multiple, never the resident one itself.
    @Test func theWireBudgetIsTheResidentOneDividedByTheDecodeMultiple() {
        let physical = 16 * Self.gigabyte
        let decoded = FeedMemoryBudget.decodedBudget(physicalMemory: physical)
        let wire = FeedMemoryBudget.wireBudget(physicalMemory: physical)
        #expect(wire == decoded / FeedMemoryBudget.decodedGraphMultiplier)
        #expect(wire < decoded)
    }

    /// Measured between 5x and 9x on the two field incidents; anything at or
    /// below 1 would mean the type had stopped distinguishing the two costs at
    /// all, which is exactly the bug.
    @Test func theDecodeMultipleIsAMultiple() {
        #expect(FeedMemoryBudget.decodedGraphMultiplier >= 5)
    }

    // MARK: - The feeds' use of it

    /// `ReactotronTimeline` reads the budget rather than carrying its own
    /// constant, so the two feeds cannot drift apart again — the JS Console
    /// copied Reactotron's 128 MB figure by hand, and that is how one of them
    /// missed the flush pacing for two releases.
    @Test func theReactotronTimelineTakesItsCapFromTheBudget() {
        #expect(ReactotronTimeline.maxTotalBytes == FeedMemoryBudget.wireBudget)
        #expect(ReactotronTimeline.maxTotalBytes > 0)
    }

    /// The eviction arithmetic has to work at the new size: a buffer over the
    /// byte cap must still trim, and must still keep the newest row even when
    /// that row alone is bigger than the whole budget.
    @Test func evictionStillWorksAtTheNewBudget() {
        let wire = FeedMemoryBudget.wireBudget
        let oversized = wire * 2
        let drop = ReactotronTimeline.dropCount(
            sizes: [oversized], count: 1, totalBytes: oversized)
        #expect(drop == 0, "the newest row must survive even when it alone exceeds the budget")

        // Ten rows each a fifth of the budget: over by half, so it trims.
        let size = wire / 5
        let sizes = Array(repeating: size, count: 10)
        let trimmed = ReactotronTimeline.dropCount(
            sizes: sizes, count: 10, totalBytes: size * 10)
        #expect(trimmed > 0)
        #expect(trimmed < 10)
    }
}
