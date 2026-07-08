import AppKit
import SwiftUI
import Testing

/// `Color(hex:)` and `hexString` back the Settings ▸ Appearance accent field,
/// which validates and normalizes user input on ⏎. The parse/format rules are
/// pure and finicky (shorthand expansion, casing, length), so they're pinned
/// here rather than eyeballed in the color well.
@Suite struct HexColorTests {
    private func rgb(_ color: Color) -> (Int, Int, Int)? {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return (
            Int(round(c.redComponent * 255)),
            Int(round(c.greenComponent * 255)),
            Int(round(c.blueComponent * 255))
        )
    }

    @Test func parsesSixDigitHexWithHash() {
        #expect(rgb(Color(hex: "#34C759")!)! == (0x34, 0xC7, 0x59))
    }

    @Test func parsesWithoutTheLeadingHash() {
        #expect(rgb(Color(hex: "34C759")!)! == (0x34, 0xC7, 0x59))
    }

    @Test func expandsThreeDigitShorthand() {
        #expect(rgb(Color(hex: "#3C5")!)! == (0x33, 0xCC, 0x55))
    }

    @Test func acceptsLowercase() {
        #expect(rgb(Color(hex: "#34c759")!)! == (0x34, 0xC7, 0x59))
    }

    @Test func rejectsMalformedInput() {
        #expect(Color(hex: "") == nil)
        #expect(Color(hex: "#") == nil)
        #expect(Color(hex: "#GGGGGG") == nil)   // right length, non-hex digits
        #expect(Color(hex: "#12345") == nil)    // too short
        #expect(Color(hex: "#1234567") == nil)  // too long
        #expect(Color(hex: "#XYZ") == nil)      // shorthand length, non-hex
    }

    @Test func hexStringNormalizesToUppercaseSixDigits() {
        #expect(Color(hex: "#3c5")?.hexString == "#33CC55")
        #expect(Color(hex: "34c759")?.hexString == "#34C759")
    }
}
