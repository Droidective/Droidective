import Testing
@testable import ADBKit

/// The rate limit standing between a pathological session and the project's
/// whole log quota. One user produced 1931 hang reports from one session
/// (DROIDECTIVE-MAC-B); the feeds breach their slow-operation threshold many
/// times a second under load.
@Suite struct LogBudgetTests {
    @Test func admitsUpToTheLimitThenStops() {
        var budget = LogBudget(limit: 3, windowSeconds: 60)
        #expect(budget.admit("feed", at: 0).allowed)
        #expect(budget.admit("feed", at: 1).allowed)
        #expect(budget.admit("feed", at: 2).allowed)
        #expect(!budget.admit("feed", at: 3).allowed)
        #expect(!budget.admit("feed", at: 4).allowed)
    }

    @Test func reopensAfterTheWindow() {
        var budget = LogBudget(limit: 1, windowSeconds: 10)
        #expect(budget.admit("feed", at: 0).allowed)
        #expect(!budget.admit("feed", at: 9.9).allowed)
        #expect(budget.admit("feed", at: 10).allowed)
    }

    /// The magnitude is the diagnostic: "took 300 ms" is ambiguous, "took
    /// 300 ms, 412 suppressed" is the bug. So the count rides out on the next
    /// log that gets through, not on the ones that are dropped.
    @Test func theNextAdmittedLogCarriesWhatWasSwallowed() {
        var budget = LogBudget(limit: 1, windowSeconds: 10)
        #expect(budget.admit("feed", at: 0) == .init(allowed: true, suppressed: 0))
        for _ in 0 ..< 412 {
            #expect(budget.admit("feed", at: 1) == .init(allowed: false, suppressed: 0))
        }
        #expect(budget.admit("feed", at: 10) == .init(allowed: true, suppressed: 412))
    }

    /// And it resets, so the following log doesn't re-report the same burst.
    @Test func theSuppressedCountIsReportedOnce() {
        var budget = LogBudget(limit: 2, windowSeconds: 10)
        _ = budget.admit("feed", at: 0)
        _ = budget.admit("feed", at: 0)
        _ = budget.admit("feed", at: 1)
        #expect(budget.admit("feed", at: 10).suppressed == 1)
        #expect(budget.admit("feed", at: 10).suppressed == 0)
    }

    /// Keyed, so a chatty feed can't hide the one log the updater emits all
    /// day — the whole reason this isn't a single global counter.
    @Test func oneKeyRunningOutDoesNotStarveAnother() {
        var budget = LogBudget(limit: 1, windowSeconds: 60)
        #expect(budget.admit("reactotron", at: 0).allowed)
        #expect(!budget.admit("reactotron", at: 1).allowed)
        #expect(budget.admit("updater", at: 1).allowed)
    }

    /// A limit of zero would silence the sink entirely, which is never what a
    /// caller means — it reads as "off" while looking like a number.
    @Test func aLimitBelowOneIsRaisedRatherThanSilencing() {
        var budget = LogBudget(limit: 0, windowSeconds: 60)
        #expect(budget.limit == 1)
        #expect(budget.admit("feed", at: 0).allowed)
    }

    /// A zero window degrades to "always allow" rather than dividing by it.
    @Test func aZeroWindowAdmitsEveryTime() {
        var budget = LogBudget(limit: 1, windowSeconds: 0)
        #expect(budget.admit("feed", at: 0).allowed)
        #expect(budget.admit("feed", at: 0).allowed)
    }

    /// Time going backwards (a clock reading that regresses) must not admit
    /// everything by making the elapsed comparison negative.
    @Test func aBackwardClockDoesNotOpenTheGate() {
        var budget = LogBudget(limit: 1, windowSeconds: 10)
        #expect(budget.admit("feed", at: 100).allowed)
        #expect(!budget.admit("feed", at: 95).allowed)
    }

    @Test func keysAreTrackedPerCallSiteNotPerEvent() {
        var budget = LogBudget(limit: 1, windowSeconds: 60)
        for _ in 0 ..< 50 { _ = budget.admit("feed", at: 0) }
        _ = budget.admit("updater", at: 0)
        #expect(budget.trackedKeys == 2)
    }
}
