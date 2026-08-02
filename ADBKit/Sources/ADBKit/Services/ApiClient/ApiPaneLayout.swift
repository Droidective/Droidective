import Foundation

/// Geometry for the API client's two draggable seams — the sidebar edge and the
/// request/response split. Kept out of the view for the same reason `PaneSplit`
/// is: the drag gesture and the layout must agree about the bounds, and they
/// only reliably do that when one tested function decides them.
///
/// The sidebar is stored as a width (it should not grow with the window) and the
/// split as a fraction (it should), which is why they clamp differently.
public enum ApiPaneLayout {

    /// The sidebar holds a search field, a segmented picker and a tree with
    /// indented rows; below ~200pt those stop being usable.
    public static let sidebarRange: ClosedRange<Double> = 200...460

    /// Neither the editor nor the response pane drops below a quarter of the
    /// split area — past that the request tabs start truncating.
    public static let fractionRange: ClosedRange<Double> = 0.25...0.75

    /// An absolute floor on top of the fraction, so a tight window shrinks both
    /// panes evenly instead of squeezing one to nothing.
    public static let minPane: Double = 240

    /// The sidebar never takes more than a third of the pane, so the request and
    /// response columns keep the room they need on a narrow window.
    public static func sidebarWidth(stored: Double, total: Double) -> Double {
        let clamped = min(sidebarRange.upperBound, max(sidebarRange.lowerBound, stored))
        guard total > 0 else { return clamped }
        return min(clamped, max(sidebarRange.lowerBound, total / 3))
    }

    public static func clampedFraction(_ fraction: Double) -> Double {
        min(fractionRange.upperBound, max(fractionRange.lowerBound, fraction))
    }

    /// The leading pane's length for a stored fraction, with the absolute floor
    /// applied on both sides.
    public static func leadingLength(total: Double, fraction: Double) -> Double {
        guard total > 0 else { return 0 }
        let floor = paneFloor(total: total)
        let wanted = total * clampedFraction(fraction)
        return min(max(wanted, floor), total - floor)
    }

    /// The drag range in points for a given total, matching `leadingLength`
    /// exactly so the seam stops where the layout stops rather than freezing
    /// after a dead zone.
    public static func pointRange(total: Double) -> ClosedRange<Double> {
        guard total > 0 else { return 0...0 }
        let floor = paneFloor(total: total)
        let low = max(total * fractionRange.lowerBound, floor)
        let high = min(total * fractionRange.upperBound, total - floor)
        return low...max(low, high)
    }

    /// The fraction a drag lands on: where it started, plus how far it moved as
    /// a share of the current total. Both halves come from the same `total`, so
    /// the seam can't be converted through one width and back through another.
    public static func fraction(from start: Double, movedBy delta: Double, total: Double) -> Double {
        guard total > 0 else { return clampedFraction(start) }
        return clampedFraction(start + delta / total)
    }

    private static func paneFloor(total: Double) -> Double {
        min(minPane, total / 2)
    }
}
