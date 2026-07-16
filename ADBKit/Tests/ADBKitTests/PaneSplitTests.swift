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
        #expect(!PaneSplit.overshoots(0.5))
        #expect(!PaneSplit.overshoots(0.3))
        #expect(!PaneSplit.overshoots(0.7))
        #expect(PaneSplit.overshoots(0.29))
        #expect(PaneSplit.overshoots(0.71))
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

    @Test func tinyWindowSplitsEvenlyInsteadOfOverflowing() {
        // 508 total → 500 available; the 320 floor would cross over, so both
        // panes settle at half.
        #expect(PaneSplit.leftWidth(total: 508, fraction: 0.3) == 250)
        #expect(PaneSplit.leftWidth(total: 508, fraction: 0.7) == 250)
        #expect(PaneSplit.leftWidth(total: 0, fraction: 0.5) == 0)
    }
}
