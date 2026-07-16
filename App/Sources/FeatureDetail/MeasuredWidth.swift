import SwiftUI

/// Reports the view's laid-out width into a binding — the measured-reflow
/// pattern narrow toolbars use to pick a one- or two-row layout
/// (`ViewThatFits` can't: flexible fields report tiny ideal widths, so the
/// wide variant always "fits"). Width only, deliberately: reflowing changes a
/// bar's height, not its width, so the measurement can't feed back into the
/// decision it drives.
private struct WidthMeasurer: ViewModifier {
    @Binding var width: CGFloat

    func body(content: Content) -> some View {
        content.background(GeometryReader { geo in
            Color.clear.onChange(of: geo.size.width, initial: true) { _, new in
                width = new
            }
        })
    }
}

extension View {
    func measuringWidth(into width: Binding<CGFloat>) -> some View {
        modifier(WidthMeasurer(width: width))
    }
}
