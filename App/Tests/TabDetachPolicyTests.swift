import CoreGraphics
import Foundation
import Testing

/// When releasing a dragged tab means "give this its own window".
@Suite struct TabDetachPolicyTests {
    /// Two windows side by side with a gap of desktop between them.
    private let windows = [
        CGRect(x: 0, y: 0, width: 800, height: 600),
        CGRect(x: 1000, y: 100, width: 600, height: 400),
    ]

    // MARK: - isInsideApp

    @Test func aPointInsideAWindowIsInsideTheApp() {
        #expect(TabDetachPolicy.isInsideApp(point: CGPoint(x: 400, y: 300), windowFrames: windows))
        #expect(TabDetachPolicy.isInsideApp(point: CGPoint(x: 1200, y: 200), windowFrames: windows))
    }

    @Test func aPointInTheGapBetweenTwoWindowsIsOutside() {
        #expect(!TabDetachPolicy.isInsideApp(point: CGPoint(x: 900, y: 300), windowFrames: windows))
    }

    @Test func aPointBeyondEveryWindowIsOutside() {
        #expect(!TabDetachPolicy.isInsideApp(point: CGPoint(x: 3000, y: 1500), windowFrames: windows))
    }

    /// The app with every window closed — background mode, where a drag cannot
    /// be in flight at all, but the arithmetic must not claim the point is
    /// somehow inside.
    @Test func noWindowsMeansEveryPointIsOutside() {
        #expect(!TabDetachPolicy.isInsideApp(point: .zero, windowFrames: []))
    }

    @Test func aPointOnAWindowsEdgeCountsAsInside() {
        // `CGRect.contains` excludes the far edges, so check the near ones —
        // the case that matters is a drop right on the window's own border not
        // being read as "outside the app".
        #expect(TabDetachPolicy.isInsideApp(point: CGPoint(x: 0, y: 0), windowFrames: windows))
    }

    // MARK: - shouldTearOff

    @Test func aRefusedDropAwayFromTheAppTearsOff() {
        #expect(TabDetachPolicy.shouldTearOff(
            accepted: false, cancelled: false,
            point: CGPoint(x: 900, y: 300), windowFrames: windows))
    }

    /// A drop a strip or pane already handled must not *also* open a window,
    /// or every cross-window drag would leave a stray one behind.
    @Test func anAcceptedDropNeverTearsOff() {
        #expect(!TabDetachPolicy.shouldTearOff(
            accepted: true, cancelled: false,
            point: CGPoint(x: 900, y: 300), windowFrames: windows))
    }

    /// Escape reports exactly like a refused drop, so without the flag this
    /// point — out over the desktop — would open a window the user was in the
    /// middle of cancelling.
    @Test func anEscapeCancelNeverTearsOff() {
        #expect(!TabDetachPolicy.shouldTearOff(
            accepted: false, cancelled: true,
            point: CGPoint(x: 900, y: 300), windowFrames: windows))
    }

    /// Released on the app's own dead chrome: a miss, not a request. It snaps
    /// back rather than spawning a window beside the one it came from.
    @Test func aRefusedDropInsideTheAppSnapsBackInstead() {
        #expect(!TabDetachPolicy.shouldTearOff(
            accepted: false, cancelled: false,
            point: CGPoint(x: 400, y: 300), windowFrames: windows))
    }

    @Test func aCancelInsideTheAppAlsoDoesNothing() {
        #expect(!TabDetachPolicy.shouldTearOff(
            accepted: false, cancelled: true,
            point: CGPoint(x: 400, y: 300), windowFrames: windows))
    }
}
