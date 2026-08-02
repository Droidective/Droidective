import ADBKit
import AppKit
import SwiftUI

/// The draggable seam between the request editor and the response pane.
///
/// Fraction-native on purpose. Driving it through `ResizeHandle` meant storing
/// a fraction but dragging in points, so the conversion needed the pane's width
/// on the way in and again on the way out — and SwiftUI hands the gesture a
/// `Binding` captured at whichever render created it. When the two widths
/// disagreed the split jumped on a gesture nobody meant to make. Here the drag
/// distance is divided by the *current* total and nothing else is converted.
struct ApiSplitHandle: View {
    @Binding var fraction: Double
    /// The in-flight fraction, so the layout can follow the drag without
    /// writing to storage on every tick.
    @Binding var live: Double?
    let total: CGFloat
    var axis: Axis = .horizontal

    @State private var startFraction: Double?

    var body: some View {
        Divider()
            .overlay {
                Rectangle()
                    .fill(Color.clear)
                    .frame(
                        width: axis == .horizontal ? 8 : nil,
                        height: axis == .vertical ? 8 : nil
                    )
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside {
                            (axis == .horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown)
                                .set()
                        } else {
                            NSCursor.arrow.set()
                        }
                    }
                    .gesture(
                        DragGesture(coordinateSpace: .named(ResizeHandle.dragSpace))
                            .onChanged { gesture in
                                if startFraction == nil {
                                    // A gesture can end without `onEnded` (focus
                                    // loss, ⌘-Tab mid-drag); commit what it left
                                    // behind before starting a fresh one.
                                    if let stale = live { fraction = stale }
                                    startFraction = fraction
                                }
                                let delta = axis == .horizontal
                                    ? gesture.translation.width
                                    : gesture.translation.height
                                live = ApiPaneLayout.fraction(
                                    from: startFraction ?? fraction, movedBy: delta, total: total
                                )
                            }
                            .onEnded { _ in
                                // A press that never moved is not a resize. Without
                                // this, a click anywhere that AppKit reports as a
                                // zero-distance drag rewrote the split.
                                if let live, live != startFraction { fraction = live }
                                live = nil
                                startFraction = nil
                            }
                    )
            }
    }
}
