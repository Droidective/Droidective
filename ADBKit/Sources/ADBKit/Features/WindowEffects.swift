import Foundation

/// Pure math behind the translucent-window appearance: the Settings slider
/// ranges, when the effect engages, and the value each layer derives from the
/// stored opacity / blur / grain amounts. UI-free so the layering rules are
/// unit-tested.
public enum WindowEffects {
    /// Opacity slider floor — near-invisible but never fully gone, so the
    /// window stays findable over any desktop.
    public static let minimumOpacity = 0.1

    /// The opacity slider's span. 1.0 is fully opaque (the effect is off).
    public static let opacityRange: ClosedRange<Double> = minimumOpacity...1.0

    /// What a full blur slider maps to, in window-server blur radius points.
    /// Past ~40 the extra radius costs compositing time without looking any
    /// softer.
    public static let maximumBlurRadius = 40.0

    /// What a full grain slider maps to, as the noise film's alpha. Beyond
    /// this the speckle starts eating text contrast.
    public static let maximumGrainAlpha = 0.2

    /// Stored values from older builds or hand-edited defaults may be out of
    /// range — everything downstream reads through this.
    public static func clamped(_ opacity: Double) -> Double {
        guard opacity.isFinite else { return 1.0 }
        return min(max(opacity, minimumOpacity), 1.0)
    }

    /// A 0…1 slider amount (blur, grain), pinned; non-finite reads as 0.
    public static func clampedAmount(_ amount: Double) -> Double {
        guard amount.isFinite else { return 0 }
        return min(max(amount, 0), 1)
    }

    /// The effect engages only below full opacity, so 1.0 keeps the exact
    /// pre-feature rendering: opaque window, zero blur, no grain film.
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

    /// The window-server blur radius for a slider amount — zero whenever the
    /// window is opaque (nothing shows through to blur).
    public static func blurRadius(amount: Double, root opacity: Double) -> Int {
        guard isTranslucent(opacity) else { return 0 }
        return Int((clampedAmount(amount) * maximumBlurRadius).rounded())
    }

    /// The grain film's alpha for a slider amount — zero whenever the window
    /// is opaque, so the film never sits over a solid background.
    public static func grainOpacity(root opacity: Double, amount: Double) -> Double {
        guard isTranslucent(opacity) else { return 0 }
        return clampedAmount(amount) * maximumGrainAlpha
    }
}
