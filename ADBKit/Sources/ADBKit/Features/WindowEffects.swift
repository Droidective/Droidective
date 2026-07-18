import Foundation

/// Pure math behind the translucent-window appearance: the Settings slider
/// range, when the effect engages, and the alpha each layer derives from the
/// one stored opacity value. UI-free so the layering rules are unit-tested.
public enum WindowEffects {
    /// Slider floor — below this the UI stops being readable over a busy
    /// desktop, even with the blur behind it.
    public static let minimumOpacity = 0.5

    /// The Settings slider's span. 1.0 is fully opaque (the effect is off).
    public static let opacityRange: ClosedRange<Double> = minimumOpacity...1.0

    /// Stored values from older builds or hand-edited defaults may be out of
    /// range — everything downstream reads through this.
    public static func clamped(_ opacity: Double) -> Double {
        guard opacity.isFinite else { return 1.0 }
        return min(max(opacity, minimumOpacity), 1.0)
    }

    /// The effect engages only below full opacity, so 1.0 keeps the exact
    /// pre-feature rendering: opaque window, no backdrop view, no extra
    /// compositing layers.
    public static func isTranslucent(_ opacity: Double) -> Bool {
        clamped(opacity) < 0.999
    }

    /// Lifted surfaces (cards, bars, the sidebar) stay a step more opaque
    /// than the root wash so the content on them keeps its contrast; capped
    /// at fully opaque.
    public static func surfaceAlpha(root opacity: Double) -> Double {
        let root = clamped(opacity)
        guard isTranslucent(root) else { return 1.0 }
        return min(root + 0.15, 1.0)
    }

    /// The grain film's strength: strongest at the opacity floor, fading to
    /// nothing as the window approaches opaque, and zero when the film is
    /// disabled or the window is opaque.
    public static func grainOpacity(root opacity: Double, enabled: Bool) -> Double {
        let root = clamped(opacity)
        guard enabled, isTranslucent(root) else { return 0 }
        let translucency = (1.0 - root) / (1.0 - minimumOpacity)
        return 0.03 + 0.05 * translucency
    }
}
