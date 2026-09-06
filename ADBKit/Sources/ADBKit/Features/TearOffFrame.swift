import Foundation

/// Where a window torn off by a drag lands on screen.
///
/// Pure geometry, like `MirrorWall.windowFrames` — the App layer measures the
/// drag and the screen, this decides the rectangle, so the fiddly part
/// (clamping a window bigger than the screen it was dropped on) is tested
/// without a display. Deliberately no `CGRect`/`CGSize`: this is portable
/// ADBKit and the App layer converts, exactly as it does for `TileFrame`.
///
/// `Rect` and `Point` are AppKit screen coordinates — origin bottom-left, y
/// **up**. The two *inset* inputs are view coordinates instead, y **down** from
/// the window's top-left, because that is how the tab strip is laid out and
/// measured. The two conventions meeting is the whole reason this is worth
/// testing rather than inlining.
public enum TearOffFrame {
    /// A size in points.
    public struct Size: Sendable, Equatable {
        public var width: Double
        public var height: Double

        public init(width: Double, height: Double) {
            self.width = width
            self.height = height
        }
    }

    /// A position in points.
    public struct Point: Sendable, Equatable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    /// A rectangle in screen coordinates.
    public struct Rect: Sendable, Equatable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        public var minX: Double { x }
        public var maxX: Double { x + width }
        public var minY: Double { y }
        public var maxY: Double { y + height }
    }

    /// The new window's frame.
    ///
    /// The rule is that **the dragged chip lands under the cursor**, so the
    /// window reads as growing out of the tab you were holding rather than
    /// appearing at some unrelated spot. The moved tab is the only one in the
    /// new window, so it will be the strip's *first* chip — `stripOrigin` says
    /// where that sits, and `grabOffset` says where inside the chip the pointer
    /// was.
    ///
    /// - Parameters:
    ///   - dropPoint: Where the drag was released, in screen coordinates.
    ///   - grabOffset: The pointer's position inside the dragged chip, from the
    ///     chip's top-left, y down.
    ///   - stripOrigin: Where the first chip's top-left sits inside the window,
    ///     from the window's top-left, y down.
    ///   - sourceSize: The size of the window the tab came from — a torn-off
    ///     window inherits it, so the feature gets the room it already had.
    ///   - screen: The visible frame of the screen the drop landed on (i.e.
    ///     excluding the menu bar and Dock).
    ///   - minimum: The app's minimum window size.
    public static func frame(
        dropPoint: Point,
        grabOffset: Size,
        stripOrigin: Point,
        sourceSize: Size,
        screen: Rect,
        minimum: Size
    ) -> Rect {
        // Fit the screen, but never below the app's floor: a screen smaller
        // than the minimum yields an oversized window, which the origin clamp
        // below then pins by its top-left rather than letting the title bar
        // fall off.
        let width = max(minimum.width, min(sourceSize.width, screen.width))
        let height = max(minimum.height, min(sourceSize.height, screen.height))

        let left = dropPoint.x - grabOffset.width - stripOrigin.x
        // `grabOffset` and `stripOrigin` measure downward, so both raise the
        // window's top edge above the cursor; the origin is that top minus the
        // height.
        let top = dropPoint.y + grabOffset.height + stripOrigin.y

        // Deliberately asymmetric clamps. A window wider than the screen keeps
        // its *left* edge on screen (that is where the strip and its chips
        // are), and one taller keeps its *top* (that is where the title bar and
        // the strip are). Clamping both the same way would push one of them
        // off, which is how a window ends up unusable on a small display.
        let x = max(min(left, screen.maxX - width), screen.minX)
        let y = min(max(top - height, screen.minY), screen.maxY - height)

        return Rect(x: x, y: y, width: width, height: height)
    }
}
