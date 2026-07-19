import Testing
@testable import ADBKit

/// The custom-background derivation: hex parsing, the light/dark decision,
/// and the surface/border contrast steps that mirror the stock asset palette.
@Suite struct BackgroundPaletteTests {
    private func hexByte(_ v: Double) -> Int { Int((v * 255).rounded()) }

    @Test func parsesLongShortAndBareHex() {
        #expect(BackgroundPalette.parse(hex: "#1A1A1A") == BackgroundPalette.RGB(
            red: 26.0 / 255, green: 26.0 / 255, blue: 26.0 / 255))
        #expect(BackgroundPalette.parse(hex: "0D1B2A") != nil)
        // #123 expands to #112233.
        #expect(BackgroundPalette.parse(hex: "#123") == BackgroundPalette.parse(hex: "#112233"))
        #expect(BackgroundPalette.parse(hex: "  #FFFFFF  ") != nil)
    }

    @Test func rejectsMalformedHex() {
        #expect(BackgroundPalette.parse(hex: "") == nil)
        #expect(BackgroundPalette.parse(hex: "#12345") == nil)
        #expect(BackgroundPalette.parse(hex: "#GGGGGG") == nil)
        #expect(BackgroundPalette.parse(hex: "not a color") == nil)
    }

    @Test func lightDecisionMatchesTheContrastHeuristic() {
        #expect(!BackgroundPalette.isLight(BackgroundPalette.parse(hex: "#000000")!))
        #expect(!BackgroundPalette.isLight(BackgroundPalette.parse(hex: "#1A1A1A")!))   // stock dark root
        #expect(!BackgroundPalette.isLight(BackgroundPalette.parse(hex: "#0D1B2A")!))   // midnight blue
        #expect(BackgroundPalette.isLight(BackgroundPalette.parse(hex: "#F5F6F7")!))    // stock light root
        #expect(BackgroundPalette.isLight(BackgroundPalette.parse(hex: "#FFFFFF")!))
    }

    @Test func surfaceStepReproducesTheStockDarkPair() {
        // #1A1A1A → #232323 (+9 per channel).
        let surface = BackgroundPalette.surface(for: BackgroundPalette.parse(hex: "#1A1A1A")!)
        #expect(hexByte(surface.red) == 0x23)
        #expect(hexByte(surface.green) == 0x23)
        #expect(hexByte(surface.blue) == 0x23)
    }

    @Test func surfaceOnALightRootClampsAtWhite() {
        // #F5F6F7 → white-ish, clamped like the stock light pair (surface #FFFFFF).
        let surface = BackgroundPalette.surface(for: BackgroundPalette.parse(hex: "#F5F6F7")!)
        #expect(hexByte(surface.red) >= 0xFE)
        #expect(hexByte(surface.green) == 0xFF)
        #expect(hexByte(surface.blue) == 0xFF)
    }

    @Test func borderStepsFollowTheRootsSide() {
        // Dark root lightens (+25): #1A1A1A → #333333.
        let dark = BackgroundPalette.border(for: BackgroundPalette.parse(hex: "#1A1A1A")!)
        #expect(hexByte(dark.red) == 0x33)
        // Light root darkens (−18): #F5F6F7 → ≈#E3E4E5.
        let light = BackgroundPalette.border(for: BackgroundPalette.parse(hex: "#F5F6F7")!)
        #expect(hexByte(light.red) == 0xE3)
        #expect(hexByte(light.green) == 0xE4)
    }

    @Test func extremesStayInRange() {
        let onWhite = BackgroundPalette.surface(for: BackgroundPalette.parse(hex: "#FFFFFF")!)
        #expect(onWhite.red <= 1 && onWhite.green <= 1 && onWhite.blue <= 1)
        let onBlack = BackgroundPalette.border(for: BackgroundPalette.parse(hex: "#000000")!)
        #expect(onBlack.red >= 0 && hexByte(onBlack.red) == 25)
    }
}
