import Foundation

/// Decides how many tabs fit on one row and which spill into an overflow menu.
///
/// The request editor used `ViewThatFits` over a segmented and a menu picker,
/// which is all-or-nothing: seven tabs never fit a half-width pane, so the whole
/// row collapsed to a single centred dropdown even with room for most of them.
/// This keeps as many real tabs as the width allows and hands only the remainder
/// to a menu — and never renders a tab that would be clipped.
public enum TabOverflow {

    public struct Layout: Equatable, Sendable {
        /// Indices to draw as tabs, in display order.
        public let visible: [Int]
        /// Indices for the overflow menu, in display order.
        public let overflow: [Int]

        public init(visible: [Int], overflow: [Int]) {
            self.visible = visible
            self.overflow = overflow
        }
    }

    /// Later tabs give way first, so the ones people reach for most keep their
    /// place. The selection is always drawn — a tab you are looking at must not
    /// vanish into a menu — so when it would have overflowed it takes the last
    /// visible slot and that tab moves into the menu instead.
    ///
    /// - Parameters:
    ///   - widths: each tab's rendered width, in display order.
    ///   - available: width the row has to spend.
    ///   - spacing: gap between adjacent tabs.
    ///   - overflowWidth: width of the overflow button, counted only when one is needed.
    ///   - selected: index of the selected tab, or nil when nothing is selected.
    public static func layout(
        widths: [Double],
        available: Double,
        spacing: Double,
        overflowWidth: Double,
        selected: Int?
    ) -> Layout {
        let all = Array(widths.indices)
        guard !all.isEmpty else { return Layout(visible: [], overflow: []) }
        if total(of: all, widths: widths, spacing: spacing) <= available {
            return Layout(visible: all, overflow: [])
        }

        // Room for the overflow button has to come out of the same budget.
        let budget = available - overflowWidth - spacing
        var fitting = 0
        while fitting < all.count {
            let candidate = Array(0...fitting)
            if total(of: candidate, widths: widths, spacing: spacing) <= budget {
                fitting += 1
            } else {
                break
            }
        }

        var visible = Array(0..<fitting)
        var overflow = Array(fitting..<all.count)

        if let selected, overflow.contains(selected) {
            if let displaced = visible.popLast() {
                overflow.removeAll { $0 == selected }
                overflow.append(displaced)
                overflow.sort()
                visible.append(selected)
            } else if widths[selected] <= budget {
                // Nothing fit at all, but the selection alone does — show it
                // rather than an anonymous menu button. Measured against the
                // same budget: a tab that only fits by pushing the overflow
                // button off the row is a tab that doesn't fit.
                overflow.removeAll { $0 == selected }
                visible = [selected]
            }
        }
        return Layout(visible: visible, overflow: overflow)
    }

    private static func total(of indices: [Int], widths: [Double], spacing: Double) -> Double {
        guard !indices.isEmpty else { return 0 }
        let content = indices.reduce(0.0) { $0 + widths[$1] }
        return content + spacing * Double(indices.count - 1)
    }
}
