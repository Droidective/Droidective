import Testing
@testable import ADBKit

/// The custom-text derivation: the muted tone derived from one chosen color
/// must reproduce the stock primary→muted step in both themes.
@Suite struct TextPaletteTests {
    private func byte(_ v: Double) -> Int { Int((v * 255).rounded()) }

    private func rgb(_ hex: String) -> TextPalette.RGB {
        BackgroundPalette.parse(hex: hex)!
    }

    @Test func mutedReproducesStockDarkStep() {
        // Dark: TextMain #ECECEC over the near-black root → TextMuted #929292.
        let muted = TextPalette.muted(main: rgb("#ECECEC"), over: rgb("#000000"))
        #expect(abs(byte(muted.red) - 0x92) <= 4)
        #expect(abs(byte(muted.green) - 0x92) <= 4)
        #expect(abs(byte(muted.blue) - 0x92) <= 4)
    }

    @Test func mutedReproducesStockLightStep() {
        // Light: TextMain #181A1C over the white root → TextMuted #6A6E73.
        let muted = TextPalette.muted(main: rgb("#181A1C"), over: rgb("#FFFFFF"))
        #expect(abs(byte(muted.red) - 0x6A) <= 6)
        #expect(abs(byte(muted.green) - 0x6E) <= 6)
        #expect(abs(byte(muted.blue) - 0x73) <= 6)
    }

    @Test func mutedStaysBetweenMainAndBackground() {
        // A blend never leaves the segment between the two endpoints, in
        // whichever direction each channel runs.
        let main = rgb("#FF8800")
        let bg = rgb("#101010")
        let muted = TextPalette.muted(main: main, over: bg)
        #expect(muted.red >= min(main.red, bg.red) && muted.red <= max(main.red, bg.red))
        #expect(muted.green >= min(main.green, bg.green) && muted.green <= max(main.green, bg.green))
        #expect(muted.blue >= min(main.blue, bg.blue) && muted.blue <= max(main.blue, bg.blue))
    }

    @Test func mutedOpacityIsInUnitRange() {
        #expect(TextPalette.mutedOpacity > 0 && TextPalette.mutedOpacity < 1)
    }
}
