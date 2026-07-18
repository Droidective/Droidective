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

    /// True when a drag has pushed past the floor that's actually in effect
    /// for this width — the moment the divider freezes and the drag turns
    /// into a request to free width elsewhere (the sidebar). Keyed off the
    /// same floor `leftWidth` enforces (the 320pt absolute floor can sit
    /// above 30% on a tight window), so the hide fires the instant the
    /// divider stops, never after a dead zone.
    public static func overshoots(_ rawFraction: Double, total: Double) -> Bool {
        let available = max(0, total - dividerWidth)
        guard available > 0 else { return false }
        let floor = minPane(available: available) / available
        return rawFraction < floor || rawFraction > 1 - floor
    }

    /// The left pane's width for a stored fraction. The fraction is clamped
    /// to 30…70%, and on top of that each pane keeps an absolute floor
    /// (`min(320, half)`) so a tight window — small screen, high font zoom —
    /// shrinks both panes evenly instead of pushing the right one off-screen.
    public static func leftWidth(total: Double, fraction: Double) -> Double {
        let available = max(0, total - dividerWidth)
        let minPane = minPane(available: available)
        let clamped = available * clampedFraction(fraction)
        return min(max(clamped, minPane), available - minPane)
    }

    private static func minPane(available: Double) -> Double {
        min(max(320, available * fractionRange.lowerBound), available / 2)
    }

    /// Rebase a drag's raw fraction across a mid-drag width change — the
    /// sidebar hiding to free split room grows the pane area at its LEADING
    /// edge, so preserving the divider's window-anchored position means its
    /// pixel offset inside the area grows by exactly the freed width. Without
    /// this the divider teleports away from the cursor the moment the
    /// sidebar goes.
    public static func rebasedFraction(raw: Double, oldTotal: Double, newTotal: Double) -> Double {
        guard newTotal > 0 else { return raw }
        return (raw * oldTotal + (newTotal - oldTotal)) / newTotal
    }
}
