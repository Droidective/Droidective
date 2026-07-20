@testable import ADBKit
import Testing

struct TargetStabilityTests {
    @Test func firstSightingIsNotStable() {
        var tracker = TargetStabilityTracker()
        tracker.recordPass(ids: ["a"])
        #expect(!tracker.isStable("a"))
    }

    @Test func secondConsecutiveSightingBecomesStable() {
        var tracker = TargetStabilityTracker()
        tracker.recordPass(ids: ["a"])
        tracker.recordPass(ids: ["a"])
        #expect(tracker.isStable("a"))
    }

    @Test func stayingListedKeepsStability() {
        var tracker = TargetStabilityTracker()
        for _ in 0 ..< 5 { tracker.recordPass(ids: ["a"]) }
        #expect(tracker.isStable("a"))
    }

    @Test func vanishingResetsAndReappearanceIsRegated() {
        var tracker = TargetStabilityTracker()
        tracker.recordPass(ids: ["a"])
        tracker.recordPass(ids: ["a"])
        // App relaunch: gone for a pass (even if the id were reused).
        tracker.recordPass(ids: [])
        #expect(!tracker.isStable("a"))
        tracker.recordPass(ids: ["a"])
        #expect(!tracker.isStable("a"))
        tracker.recordPass(ids: ["a"])
        #expect(tracker.isStable("a"))
    }

    @Test func targetsAreTrackedIndependently() {
        var tracker = TargetStabilityTracker()
        tracker.recordPass(ids: ["old"])
        tracker.recordPass(ids: ["old", "new"])
        #expect(tracker.isStable("old"))
        #expect(!tracker.isStable("new"))
        tracker.recordPass(ids: ["old", "new"])
        #expect(tracker.isStable("new"))
    }

    @Test func unknownIdIsNeverStable() {
        var tracker = TargetStabilityTracker()
        tracker.recordPass(ids: ["a"])
        tracker.recordPass(ids: ["a"])
        #expect(!tracker.isStable("b"))
    }
}
