import Testing

@testable import ADBKit

@Suite struct WindowEffectsTests {
    @Test func clampingPinsOutOfRangeAndNonFiniteValues() {
        #expect(WindowEffects.clamped(0.75) == 0.75)
        #expect(WindowEffects.clamped(0.05) == WindowEffects.minimumOpacity)
        #expect(WindowEffects.clamped(-1) == WindowEffects.minimumOpacity)
        #expect(WindowEffects.clamped(1.4) == 1.0)
        #expect(WindowEffects.clamped(.nan) == 1.0)
        #expect(WindowEffects.clamped(.infinity) == 1.0)
    }

    @Test func amountClampingPinsToUnitRangeAndZerosNonFinite() {
        #expect(WindowEffects.clampedAmount(0.4) == 0.4)
        #expect(WindowEffects.clampedAmount(-0.1) == 0)
        #expect(WindowEffects.clampedAmount(1.5) == 1)
        #expect(WindowEffects.clampedAmount(.nan) == 0)
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
        #expect(WindowEffects.surfaceAlpha(root: 0.1) == 0.25)
        // Out-of-range input follows the clamp, not the raw value.
        #expect(WindowEffects.surfaceAlpha(root: 0.02) == 0.25)
    }

    @Test func blurRadiusScalesWithTheSliderAndDiesWhenOpaque() {
        #expect(WindowEffects.blurRadius(amount: 1, root: 0.5) == 40)
        #expect(WindowEffects.blurRadius(amount: 0.5, root: 0.5) == 20)
        #expect(WindowEffects.blurRadius(amount: 0, root: 0.5) == 0)
        #expect(WindowEffects.blurRadius(amount: 1, root: 1.0) == 0)
        #expect(WindowEffects.blurRadius(amount: 2, root: 0.5) == 40)
    }

    @Test func grainScalesWithTheSliderAndDiesWhenOpaque() {
        #expect(WindowEffects.grainOpacity(root: 0.5, amount: 1) == WindowEffects.maximumGrainAlpha)
        #expect(WindowEffects.grainOpacity(root: 0.5, amount: 0.5) == WindowEffects.maximumGrainAlpha / 2)
        #expect(WindowEffects.grainOpacity(root: 0.5, amount: 0) == 0)
        #expect(WindowEffects.grainOpacity(root: 1.0, amount: 1) == 0)
    }
}
