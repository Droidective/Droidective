import Testing

@testable import ADBKit

@Suite struct WindowEffectsTests {
    @Test func clampingPinsOutOfRangeAndNonFiniteValues() {
        #expect(WindowEffects.clamped(0.75) == 0.75)
        #expect(WindowEffects.clamped(0.2) == WindowEffects.minimumOpacity)
        #expect(WindowEffects.clamped(-1) == WindowEffects.minimumOpacity)
        #expect(WindowEffects.clamped(1.4) == 1.0)
        #expect(WindowEffects.clamped(.nan) == 1.0)
        #expect(WindowEffects.clamped(.infinity) == 1.0)
    }

    @Test func translucencyEngagesOnlyBelowFullOpacity() {
        #expect(!WindowEffects.isTranslucent(1.0))
        #expect(!WindowEffects.isTranslucent(0.9995))
        #expect(!WindowEffects.isTranslucent(1.4))
        #expect(WindowEffects.isTranslucent(0.99))
        #expect(WindowEffects.isTranslucent(WindowEffects.minimumOpacity))
        #expect(WindowEffects.isTranslucent(0))
    }

    @Test func surfacesStayAStepMoreOpaqueThanTheRootAndCapAtOne() {
        #expect(WindowEffects.surfaceAlpha(root: 1.0) == 1.0)
        #expect(WindowEffects.surfaceAlpha(root: 0.6) == 0.75)
        #expect(WindowEffects.surfaceAlpha(root: 0.95) == 1.0)
        #expect(WindowEffects.surfaceAlpha(root: 0.5) == 0.65)
        // Out-of-range input follows the clamp, not the raw value.
        #expect(WindowEffects.surfaceAlpha(root: 0.1) == 0.65)
    }

    @Test func grainIsZeroWhenDisabledOrOpaqueAndScalesWithTranslucency() {
        #expect(WindowEffects.grainOpacity(root: 0.6, enabled: false) == 0)
        #expect(WindowEffects.grainOpacity(root: 1.0, enabled: true) == 0)
        let atFloor = WindowEffects.grainOpacity(root: WindowEffects.minimumOpacity, enabled: true)
        let nearOpaque = WindowEffects.grainOpacity(root: 0.95, enabled: true)
        #expect(atFloor > nearOpaque)
        #expect(nearOpaque > 0)
        #expect(atFloor <= 0.08)
    }
}
