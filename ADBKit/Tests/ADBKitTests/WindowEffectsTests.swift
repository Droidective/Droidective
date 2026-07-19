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

    @Test func cardsCarryTheContrastStepNotACompoundedSolid() {
        #expect(WindowEffects.cardAlpha(root: 1.0) == 1.0)
        // 0.15 / (1 - root): the fraction that composites to root + 0.15.
        // Tolerance compares — the subtraction isn't exact in binary.
        #expect(abs(WindowEffects.cardAlpha(root: 0.7) - 0.5) < 0.0001)
        #expect(abs(WindowEffects.cardAlpha(root: 0.5) - 0.3) < 0.0001)
        #expect(abs(WindowEffects.cardAlpha(root: 0.1) - 1.0 / 6.0) < 0.0001)
        // Near-opaque roots pin to opaque cards instead of dividing by ~0.
        #expect(WindowEffects.cardAlpha(root: 0.9) == 1.0)
        // Out-of-range input follows the clamp, not the raw value.
        #expect(abs(WindowEffects.cardAlpha(root: 0.02) - 1.0 / 6.0) < 0.0001)
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
