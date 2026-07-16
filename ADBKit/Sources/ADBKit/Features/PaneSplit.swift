import Foundation

/// Pure geometry for the editor's two-pane split (RootView's `panesArea`) —
/// kept out of the view so the clamp rules are tested, and so the drag gesture
/// and the layout can't disagree about the bounds (they used to: the drag
/// allowed 20…80% while the layout floored each pane at a fixed 320pt).
public enum PaneSplit {
    /// The seam between the panes.
    public static let dividerWidth: Double = 8

    /// A pane is never narrower than 30% of the split area — below that no
    /// feature layout survives — and never wider than 70%.
    public static let fractionRange: ClosedRange<Double> = 0.3...0.7

    public static func clampedFraction(_ fraction: Double) -> Double {
        min(fractionRange.upperBound, max(fractionRange.lowerBound, fraction))
    }

    /// True when a drag has pushed past the fraction bounds — the pane the
    /// user is shrinking refuses to go below 30%, which is the moment to free
    /// width elsewhere (the sidebar) instead.
    public static func overshoots(_ rawFraction: Double) -> Bool {
        !fractionRange.contains(rawFraction)
    }

    /// The left pane's width for a stored fraction. The fraction is clamped
    /// to 30…70%, and on top of that each pane keeps an absolute floor
    /// (`min(320, half)`) so a tight window — small screen, high font zoom —
    /// shrinks both panes evenly instead of pushing the right one off-screen.
    public static func leftWidth(total: Double, fraction: Double) -> Double {
        let available = max(0, total - dividerWidth)
        let minPane = min(max(320, available * fractionRange.lowerBound), available / 2)
        let clamped = available * clampedFraction(fraction)
        return min(max(clamped, minPane), available - minPane)
    }
}
