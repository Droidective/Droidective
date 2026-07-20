import Foundation

/// Pure math for the user-chosen text color (Settings ▸ Appearance ▸ Text):
/// one picked color drives primary text, and the muted/subtitle tone is
/// derived from it by the same primary→muted step as the stock palette, so the
/// text hierarchy holds on whatever color the user picks.
///
/// Reuses `BackgroundPalette.RGB` for the component type.
public enum TextPalette {
    public typealias RGB = BackgroundPalette.RGB

    /// The muted tone is the primary color composited at this opacity over the
    /// surface behind it. It reproduces the stock primary→muted step in both
    /// themes — dark `#ECECEC → #929292` (≈ ×0.62) and light `#181A1C` over
    /// white `→ #6A6E73` (≈ ×0.63) — so the app applies it directly as a
    /// SwiftUI opacity and lets it composite over whatever surface is actually
    /// behind the text (root, card, or a custom background).
    public static let mutedOpacity = 0.62

    /// The muted tone as a concrete color: `main` alpha-composited at
    /// `mutedOpacity` over `background`. The app renders muted text via the
    /// opacity above (background-agnostic); this returns the equivalent solid
    /// color and exists so the ratio is unit-tested against the stock pairs.
    public static func muted(main: RGB, over background: RGB) -> RGB {
        RGB(
            red: main.red * mutedOpacity + background.red * (1 - mutedOpacity),
            green: main.green * mutedOpacity + background.green * (1 - mutedOpacity),
            blue: main.blue * mutedOpacity + background.blue * (1 - mutedOpacity))
    }

    /// A WCAG-style contrast ratio (1…21) between two colors, using the app's
    /// gamma-encoded luminance approximation (`BackgroundPalette.luminance`, the
    /// same one behind `isLight`) rather than a second, linearized model — so
    /// the number lines up with the rest of the palette math.
    public static func contrastRatio(_ a: RGB, _ b: RGB) -> Double {
        let la = BackgroundPalette.luminance(a)
        let lb = BackgroundPalette.luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Below this ratio a custom text color is likely hard to read on its
    /// background, so Settings shows a non-blocking warning (it never prevents
    /// applying the color). 3.0 is WCAG AA for large text / UI components.
    public static let minComfortableContrast = 3.0
}
