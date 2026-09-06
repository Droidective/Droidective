import Foundation
import Testing
@testable import ADBKit

/// Where a torn-off window lands. Screen coordinates are y-**up**; the chip and
/// strip insets are y-**down** from the window's top-left.
@Suite struct TearOffFrameTests {
    /// A 1920×1080 screen at the origin, with 25 pt of menu bar taken off the
    /// top — the shape `NSScreen.visibleFrame` actually has.
    private let screen = TearOffFrame.Rect(x: 0, y: 0, width: 1920, height: 1055)
    private let sourceSize = TearOffFrame.Size(width: 1200, height: 800)
    private let minimum = TearOffFrame.Size(width: 760, height: 480)
    /// The first chip sits past the Home button and its divider.
    private let stripOrigin = TearOffFrame.Point(x: 52, y: 28)

    private func frame(
        droppedAt point: TearOffFrame.Point,
        grab: TearOffFrame.Size = TearOffFrame.Size(width: 40, height: 14),
        source: TearOffFrame.Size? = nil,
        screen: TearOffFrame.Rect? = nil
    ) -> TearOffFrame.Rect {
        TearOffFrame.frame(
            dropPoint: point,
            grabOffset: grab,
            stripOrigin: stripOrigin,
            sourceSize: source ?? sourceSize,
            screen: screen ?? self.screen,
            minimum: minimum
        )
    }

    // MARK: - The chip lands under the cursor

    /// Drop points here are chosen so nothing clamps — an 800 pt window dropped
    /// low on the screen gets pushed up, and then the chip deliberately *isn't*
    /// under the cursor any more (`aDropNearTheBottomEdgeClampsInside` covers
    /// that case).
    @Test func theDraggedChipLandsUnderTheCursor() {
        let drop = TearOffFrame.Point(x: 800, y: 900)
        let result = frame(droppedAt: drop)
        // Where the chip will be in the new window, converted back to screen
        // coordinates — the cursor should be exactly there.
        let chipLeft = result.minX + stripOrigin.x
        let chipTop = result.maxY - stripOrigin.y
        #expect(chipLeft + 40 == drop.x)
        #expect(chipTop - 14 == drop.y)
    }

    @Test func aDifferentGrabOffsetShiftsTheWindowWithIt() {
        let drop = TearOffFrame.Point(x: 700, y: 900)
        let near = frame(droppedAt: drop, grab: TearOffFrame.Size(width: 10, height: 4))
        let far = frame(droppedAt: drop, grab: TearOffFrame.Size(width: 90, height: 4))
        // Grabbing further right in the chip puts the window further left, so
        // that point of the chip still ends up under the cursor.
        #expect(far.minX == near.minX - 80)
    }

    @Test func theWindowInheritsTheSourceWindowsSize() {
        let result = frame(droppedAt: TearOffFrame.Point(x: 800, y: 900))
        #expect(result.width == 1200)
        #expect(result.height == 800)
    }

    // MARK: - Clamping into the screen

    @Test func aDropNearTheRightEdgeClampsInside() {
        let result = frame(droppedAt: TearOffFrame.Point(x: 1900, y: 600))
        #expect(result.maxX == screen.maxX)
        #expect(result.minX >= screen.minX)
    }

    @Test func aDropNearTheBottomEdgeClampsInside() {
        let result = frame(droppedAt: TearOffFrame.Point(x: 800, y: 10))
        #expect(result.minY == screen.minY)
        #expect(result.maxY <= screen.maxY)
    }

    @Test func aDropNearTheTopEdgeClampsInside() {
        let result = frame(droppedAt: TearOffFrame.Point(x: 800, y: 1050))
        #expect(result.maxY == screen.maxY)
    }

    @Test func aDropInTheBottomRightCornerClampsOnBothAxes() {
        let result = frame(droppedAt: TearOffFrame.Point(x: 1915, y: 5))
        #expect(result.maxX == screen.maxX)
        #expect(result.minY == screen.minY)
    }

    @Test func aDropOnAScreenWithANonZeroOriginStaysOnThatScreen() {
        // A second display sitting to the right of the main one.
        let second = TearOffFrame.Rect(x: 1920, y: 0, width: 1280, height: 800)
        let result = frame(
            droppedAt: TearOffFrame.Point(x: 3100, y: 400), screen: second)
        #expect(result.minX >= second.minX)
        #expect(result.maxX <= second.maxX)
        #expect(result.minY >= second.minY)
        #expect(result.maxY <= second.maxY)
    }

    // MARK: - Size limits

    @Test func aSourceWindowBiggerThanTheScreenShrinksToFit() {
        let huge = TearOffFrame.Size(width: 4000, height: 3000)
        let result = frame(droppedAt: TearOffFrame.Point(x: 800, y: 600), source: huge)
        #expect(result.width == screen.width)
        #expect(result.height == screen.height)
    }

    @Test func neverGoesBelowTheMinimumSize() {
        let tiny = TearOffFrame.Size(width: 100, height: 100)
        let result = frame(droppedAt: TearOffFrame.Point(x: 800, y: 600), source: tiny)
        #expect(result.width == minimum.width)
        #expect(result.height == minimum.height)
    }

    /// A window that cannot fit keeps its top-left corner reachable: the title
    /// bar and the tab strip live there, so pinning the other corners would
    /// leave the window undraggable and the tabs unreachable.
    @Test func aScreenSmallerThanTheMinimumStillYieldsTheMinimumPinnedTopLeft() {
        let cramped = TearOffFrame.Rect(x: 0, y: 0, width: 500, height: 400)
        let result = frame(droppedAt: TearOffFrame.Point(x: 250, y: 200), screen: cramped)
        #expect(result.width == minimum.width)
        #expect(result.height == minimum.height)
        #expect(result.minX == cramped.minX)
        #expect(result.maxY == cramped.maxY)
    }

    // MARK: - Invariant

    @Test(arguments: [
        TearOffFrame.Point(x: 0, y: 0),
        TearOffFrame.Point(x: 1920, y: 1055),
        TearOffFrame.Point(x: -400, y: 500),
        TearOffFrame.Point(x: 5000, y: -500),
        TearOffFrame.Point(x: 960, y: 527),
    ])
    func theResultIsAlwaysFullyOnScreenWhenTheScreenAllowsIt(drop: TearOffFrame.Point) {
        let result = frame(droppedAt: drop)
        #expect(result.minX >= screen.minX)
        #expect(result.maxX <= screen.maxX)
        #expect(result.minY >= screen.minY)
        #expect(result.maxY <= screen.maxY)
    }

    @Test func anEmptyScreenRectDoesNotCrashAndYieldsTheMinimum() {
        let empty = TearOffFrame.Rect(x: 0, y: 0, width: 0, height: 0)
        let result = frame(droppedAt: TearOffFrame.Point(x: 0, y: 0), screen: empty)
        #expect(result.width == minimum.width)
        #expect(result.height == minimum.height)
    }
}
