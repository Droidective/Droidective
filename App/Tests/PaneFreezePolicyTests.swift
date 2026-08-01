import CoreGraphics
import Testing

/// The v3.7.1 resize beachball (Sentry DROIDECTIVE-MAC-54/-27): every open
/// tab stays mounted, so a seam drag re-laid-out heavyweight hidden content
/// on every tick. The policy pins hidden tabs (and the visible crash trace)
/// to their resting size mid-resize and must never pin what the user is
/// actively watching or anything not yet measured.
@Suite struct PaneFreezePolicyTests {
    private let resting = CGSize(width: 760, height: 640)

    @Test func hiddenTabPinsToTheRestingSizeMidResize() {
        #expect(
            PaneFreezePolicy.pinnedSize(isActive: false, isResizing: true, resting: resting)
                == resting)
    }

    @Test func activeTabAlwaysTracksTheLiveSize() {
        #expect(
            PaneFreezePolicy.pinnedSize(isActive: true, isResizing: true, resting: resting) == nil)
    }

    @Test func nothingPinsAtRest() {
        #expect(
            PaneFreezePolicy.pinnedSize(isActive: false, isResizing: false, resting: resting)
                == nil)
    }

    /// Before the first geometry pass there is no resting size — pinning to
    /// nothing (or a zero size) would collapse the tab instead of freezing it.
    @Test func unmeasuredPanesNeverPin() {
        #expect(PaneFreezePolicy.pinnedSize(isActive: false, isResizing: true, resting: nil) == nil)
        #expect(
            PaneFreezePolicy.pinnedSize(isActive: false, isResizing: true, resting: .zero) == nil)
        #expect(
            PaneFreezePolicy.pinnedSize(
                isActive: false, isResizing: true, resting: CGSize(width: 760, height: 0)) == nil)
    }

    @Test func visibleTraceWidthPinsOnlyMidResize() {
        #expect(PaneFreezePolicy.pinnedWidth(isResizing: true, resting: 520) == 520)
        #expect(PaneFreezePolicy.pinnedWidth(isResizing: false, resting: 520) == nil)
        #expect(PaneFreezePolicy.pinnedWidth(isResizing: true, resting: nil) == nil)
        #expect(PaneFreezePolicy.pinnedWidth(isResizing: true, resting: 0) == nil)
    }
}
