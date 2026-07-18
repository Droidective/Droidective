import Foundation
import Testing
@testable import ADBKit

@Suite struct PaneSplitTests {
    @Test func fractionClampsToThirtySeventy() {
        #expect(PaneSplit.clampedFraction(0.5) == 0.5)
        #expect(PaneSplit.clampedFraction(0.1) == 0.3)
        #expect(PaneSplit.clampedFraction(0.95) == 0.7)
        #expect(PaneSplit.clampedFraction(0.3) == 0.3)
        #expect(PaneSplit.clampedFraction(0.7) == 0.7)
    }

    @Test func overshootFiresOnlyPastTheBounds() {
        // Wide window: the 30% fraction floor governs.
        #expect(!PaneSplit.overshoots(0.5, total: 1608))
        #expect(!PaneSplit.overshoots(0.3, total: 1608))
        #expect(!PaneSplit.overshoots(0.7, total: 1608))
        #expect(PaneSplit.overshoots(0.29, total: 1608))
        #expect(PaneSplit.overshoots(0.71, total: 1608))
        #expect(!PaneSplit.overshoots(0.1, total: 0))
    }

    @Test func overshootTracksTheEffectiveFloorOnANarrowWindow() {
        // 908 total → 900 available; the 320pt floor sits at ~35.6%, so the
        // divider freezes there — the hide must fire at that fraction, not
        // after a dead zone down to 30%.
        #expect(PaneSplit.overshoots(0.34, total: 908))
        #expect(!PaneSplit.overshoots(0.36, total: 908))
        #expect(PaneSplit.overshoots(0.66, total: 908))
        #expect(!PaneSplit.overshoots(0.64, total: 908))
    }

    @Test func leftWidthHonoursTheFractionOnAWideWindow() {
        // 1608 total → 1600 available; 30% floor = 480 > 320, so the
        // percentage floor governs.
        #expect(PaneSplit.leftWidth(total: 1608, fraction: 0.5) == 800)
        #expect(PaneSplit.leftWidth(total: 1608, fraction: 0.3) == 480)
        #expect(PaneSplit.leftWidth(total: 1608, fraction: 0.7) == 1120)
        // A stored out-of-range fraction (old builds allowed 20…80) renders
        // clamped, not at its raw value.
        #expect(PaneSplit.leftWidth(total: 1608, fraction: 0.2) == 480)
        #expect(PaneSplit.leftWidth(total: 1608, fraction: 0.8) == 1120)
    }

    @Test func absoluteFloorGovernsOnANarrowWindow() {
        // 908 total → 900 available; 30% = 270 < 320, so the 320pt floor
        // wins on both sides.
        #expect(PaneSplit.leftWidth(total: 908, fraction: 0.3) == 320)
        #expect(PaneSplit.leftWidth(total: 908, fraction: 0.7) == 580)
    }

    @Test func nanFractionClampsInsteadOfPropagating() {
        // Safety rests on min/max returning one of their *arguments* (never
        // synthesizing) and on the current argument order — a NaN reaching a
        // SwiftUI frame width is a crash, so pin it.
        #expect(PaneSplit.clampedFraction(.nan) == 0.3)
        #expect(PaneSplit.leftWidth(total: 1608, fraction: .nan) == 480)
    }

    @Test func tinyWindowSplitsEvenlyInsteadOfOverflowing() {
        // 508 total → 500 available; the 320 floor would cross over, so both
        // panes settle at half.
        #expect(PaneSplit.leftWidth(total: 508, fraction: 0.3) == 250)
        #expect(PaneSplit.leftWidth(total: 508, fraction: 0.7) == 250)
        #expect(PaneSplit.leftWidth(total: 0, fraction: 0.5) == 0)
    }

    @Test func rebasePreservesTheDividersWindowPosition() {
        // Pane area grows 1000 → 1300 (the 300pt sidebar hid at the leading
        // edge): a divider at 27% of 1000 (270pt, window x = 300 + 270 = 570)
        // must land at 570pt of 1300 to stay under the cursor.
        let rebased = PaneSplit.rebasedFraction(raw: 0.27, oldTotal: 1000, newTotal: 1300)
        #expect(abs(rebased * 1300 - 570) < 0.0001)
    }

    @Test func rebaseIsIdentityWhenWidthIsUnchangedAndSafeAtZero() {
        #expect(PaneSplit.rebasedFraction(raw: 0.5, oldTotal: 900, newTotal: 900) == 0.5)
        #expect(PaneSplit.rebasedFraction(raw: 0.4, oldTotal: 900, newTotal: 0) == 0.4)
    }
}
