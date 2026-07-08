import Foundation
import Testing
@testable import ADBKit

@Suite struct UsageStatsTests {
    private func date(_ seconds: Double) -> Date { Date(timeIntervalSince1970: seconds) }

    @Test func recordIncrementsCountAndStampsLastUsed() {
        var stats = UsageStats()
        stats.record("logcat", at: date(100))
        stats.record("logcat", at: date(200))
        #expect(stats.count(for: "logcat") == 2)
        #expect(stats.byFeature["logcat"]?.lastUsed == date(200))
        #expect(stats.count(for: "screenshot") == 0)
    }

    @Test func rankPutsMostUsedFirstThenRecencyThenCuratedOrder() {
        var stats = UsageStats()
        // screenshot used most; logcat and apps tie on count, apps more recent.
        for t in [10.0, 20, 30] { stats.record("screenshot", at: date(t)) }
        stats.record("logcat", at: date(40))
        stats.record("apps", at: date(50))
        let curated = ["send-text", "logcat", "apps", "screenshot", "device-info"]
        #expect(stats.rank(curated) == ["screenshot", "apps", "logcat", "send-text", "device-info"])
    }

    @Test func rankPreservesCuratedOrderWhenUnused() {
        let stats = UsageStats()
        let curated = ["a", "b", "c", "d"]
        #expect(stats.rank(curated) == curated)
    }

    @Test func frequentKeepsOnlyIdsAtOrAboveTheThresholdOrderedByCount() {
        var stats = UsageStats()
        for t in [1.0, 2] { stats.record("a", at: date(t)) }        // count 2
        for t in [1.0, 2, 3, 4] { stats.record("b", at: date(t)) }  // count 4
        stats.record("c", at: date(9))                              // count 1, excluded
        #expect(stats.frequent(among: ["a", "b", "c", "d"], minUses: 2) == ["b", "a"])
    }

    @Test func frequentBreaksTiesByInputOrderNotRecency() {
        var stats = UsageStats()
        for _ in 0..<2 { stats.record("later", at: date(100)) }   // count 2, used most recently
        for _ in 0..<2 { stats.record("earlier", at: date(10)) }  // count 2, used long ago
        // Input order puts "earlier" first; recency must not reorder them —
        // this is the "count, not last-used" invariant the strip depends on.
        #expect(stats.frequent(among: ["earlier", "later"], minUses: 2) == ["earlier", "later"])
    }

    @Test func frequentIsEmptyWhenNothingMeetsTheThreshold() {
        var stats = UsageStats()
        stats.record("a", at: date(1))
        #expect(stats.frequent(among: ["a", "b"], minUses: 2).isEmpty)
    }
}
