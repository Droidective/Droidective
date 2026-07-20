import Foundation

/// Pure math for the user-chosen window background (Settings ▸ Appearance):
/// parses the stored hex and derives the lifted surface, the hairline border,
/// and the light/dark treatment from that one root color — mirroring the
/// contrast steps between the stock `BgRoot`/`BgSurface`/`BorderSubtle`
/// assets, so a custom palette keeps the same visual hierarchy.
public enum BackgroundPalette {
    /// sRGB components in 0…1.
    public struct RGB: Equatable, Sendable {
        public var red: Double
        public var green: Double
        public var blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    /// Parse "#RRGGBB" / "RRGGBB" (or the "#RGB" shorthand). nil on malformed
    /// input, so a corrupt stored value falls back to the stock assets.
    public static func parse(hex: String) -> RGB? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        return RGB(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }

    /// Rec. 709 weights on gamma-encoded sRGB — the same perceptual-luminance
    /// heuristic the app's `contrastingForeground` uses.
    public static func luminance(_ color: RGB) -> Double {
        0.2126 * color.red + 0.7152 * color.green + 0.0722 * color.blue
    }

    /// Light backgrounds get dark text and the light (aqua) appearance — the
    /// 0.35 threshold matches `contrastingForeground`.
    public static func isLight(_ color: RGB) -> Bool {
        luminance(color) > 0.35
    }

    /// One step lifted (sidebar, cards, bars): +9/255 per channel, clamped —
    /// the stock dark step (#1A1A1A → #232323); a light root lands at white
    /// just like the stock pair (#F5F6F7 → #FFFFFF).
    public static func surface(for root: RGB) -> RGB {
        shifted(root, by: 9.0 / 255)
    }

    /// Hairline dividers: dark roots go lighter (+25/255, the stock
    /// #1A1A1A → #333333 step), light roots darker (−18/255, ≈the stock
    /// #F5F6F7 → #E3E5E8 step).
    public static func border(for root: RGB) -> RGB {
        shifted(root, by: isLight(root) ? -18.0 / 255 : 25.0 / 255)
    }

    private static func shifted(_ color: RGB, by delta: Double) -> RGB {
        RGB(
            red: min(1, max(0, color.red + delta)),
            green: min(1, max(0, color.green + delta)),
            blue: min(1, max(0, color.blue + delta)))
    }
}
