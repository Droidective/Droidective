import Foundation
import Testing
@testable import ADBKit

@Suite struct MirrorWallTests {
    // MARK: - Auto columns

    @Test func oneTileIsOneColumn() {
        #expect(MirrorWall.columns(paneWidth: 1600, tiles: 1) == 1)
        #expect(MirrorWall.columns(paneWidth: 300, tiles: 1) == 1)
    }

    /// Portrait tiles: three across reads better than 2 + 1, and four want a
    /// 2 × 2 rather than a single row of narrow slivers.
    @Test func autoColumnsPreferSquarishGridsExceptForThree() {
        #expect(MirrorWall.columns(paneWidth: 1600, tiles: 2) == 2)
        #expect(MirrorWall.columns(paneWidth: 1600, tiles: 3) == 3)
        #expect(MirrorWall.columns(paneWidth: 1600, tiles: 4) == 2)
        #expect(MirrorWall.columns(paneWidth: 1600, tiles: 5) == 3)
        #expect(MirrorWall.columns(paneWidth: 1600, tiles: 6) == 3)
    }

    @Test func aNarrowPaneDropsColumnsInsteadOfShrinkingTiles() {
        // 600 fits two 260-wide tiles, not three.
        #expect(MirrorWall.columns(paneWidth: 600, tiles: 6) == 2)
        // A 30% split fits one.
        #expect(MirrorWall.columns(paneWidth: 300, tiles: 6) == 1)
        #expect(MirrorWall.columns(paneWidth: 0, tiles: 4) == 1)
    }

    @Test func autoColumnsSurviveAnUnmeasuredPane() {
        #expect(MirrorWall.columns(paneWidth: .nan, tiles: 4) == 1)
        #expect(MirrorWall.columns(paneWidth: -100, tiles: 4) == 1)
    }

    // MARK: - Manual columns

    @Test func manualColumnsStandEvenInANarrowPane() {
        // The user overruling the auto layout is not second-guessed.
        #expect(MirrorWall.columns(manual: 3, tiles: 6) == 3)
        #expect(MirrorWall.columns(manual: 1, tiles: 6) == 1)
    }

    @Test func manualColumnsNeverExceedTheTileCount() {
        #expect(MirrorWall.columns(manual: 3, tiles: 2) == 2)
        #expect(MirrorWall.columns(manual: 3, tiles: 0) == 1)
        #expect(MirrorWall.columns(manual: 0, tiles: 4) == 1)
        #expect(MirrorWall.columns(manual: -2, tiles: 4) == 1)
    }

    // MARK: - Per-tile quality

    @Test func aOneTileWallLooksLikeTheFullMirror() {
        #expect(MirrorWall.quality(tiles: 1) == MirrorWall.fullQuality)
        #expect(MirrorWall.fullQuality.maxSize == 1280)
        #expect(MirrorWall.fullQuality.maxFps == 0)
    }

    @Test func qualityStepsDownAsTilesAreAdded() {
        #expect(MirrorWall.quality(tiles: 2).maxSize == 1024)
        #expect(MirrorWall.quality(tiles: 4).maxSize == 800)
        #expect(MirrorWall.quality(tiles: 6).maxSize == 640)
        // Frame rate is capped only once several encoders are running.
        #expect(MirrorWall.quality(tiles: 2).maxFps == 0)
        #expect(MirrorWall.quality(tiles: 3).maxFps == 30)
        #expect(MirrorWall.quality(tiles: 6).maxFps == 24)
    }

    @Test func qualityNeverGrowsPastTheCapOrBelowOneTile() {
        #expect(MirrorWall.quality(tiles: 7) == MirrorWall.quality(tiles: 6))
        #expect(MirrorWall.quality(tiles: 0) == MirrorWall.fullQuality)
    }

    // MARK: - Selection

    @Test func aWallNobodyHasPickedForOpensOnTheConnectedDevices() {
        #expect(MirrorWall.reconciled(selection: nil, connected: ["a", "b"]) == ["a", "b"])
    }

    @Test func openingOnConnectedDevicesStopsAtTheCap() {
        let connected = ["a", "b", "c", "d", "e", "f", "g", "h"]
        #expect(MirrorWall.reconciled(selection: nil, connected: connected).count
            == MirrorWall.maximumDevices)
    }

    @Test func reconcilingKeepsTheChosenOrderAndDropsDevicesThatLeft() {
        #expect(MirrorWall.reconciled(selection: ["c", "a"], connected: ["a", "b", "c"])
            == ["c", "a"])
        #expect(MirrorWall.reconciled(selection: ["c", "a"], connected: ["a", "b"]) == ["a"])
    }

    /// An emptied wall stays empty: refilling it from the connected devices
    /// would undo the unchecking that emptied it, and every uncheck would
    /// re-add the device it just removed.
    @Test func anExplicitlyEmptiedSelectionIsNotRefilled() {
        #expect(MirrorWall.reconciled(selection: [], connected: ["a", "b"]) == [])
        #expect(MirrorWall.reconciled(selection: ["x", "y"], connected: ["a"]) == [])
    }

    @Test func togglingAddsAtTheEndAndRemovesInPlace() {
        #expect(MirrorWall.toggled("b", in: ["a"]) == ["a", "b"])
        #expect(MirrorWall.toggled("a", in: ["a", "b"]) == ["b"])
    }

    @Test func togglingRefusesToPassTheCap() {
        let full = ["a", "b", "c", "d", "e", "f"]
        #expect(full.count == MirrorWall.maximumDevices)
        #expect(MirrorWall.toggled("g", in: full) == full)
        #expect(!MirrorWall.canAdd(to: full))
        #expect(MirrorWall.canAdd(to: Array(full.dropLast())))
        // Removing still works at the cap — that's how you make room.
        #expect(MirrorWall.toggled("a", in: full) == ["b", "c", "d", "e", "f"])
    }

    // MARK: - Pop-out window tiling

    private let screen = MirrorWall.TileFrame(x: 0, y: 0, width: 1600, height: 1000)

    @Test func nothingToArrangeYieldsNoFrames() {
        #expect(MirrorWall.windowFrames(in: screen, count: 0).isEmpty)
        #expect(MirrorWall.windowFrames(
            in: MirrorWall.TileFrame(x: 0, y: 0, width: 0, height: 0), count: 3).isEmpty)
    }

    @Test func fourWindowsTileTwoByTwoFillingTheScreen() {
        let frames = MirrorWall.windowFrames(in: screen, count: 4)
        #expect(frames.count == 4)
        #expect(frames.allSatisfy { $0.width == 800 && $0.height == 500 })
        // Screen coordinates are bottom-left, so the first row sits at the top.
        #expect(frames[0] == MirrorWall.TileFrame(x: 0, y: 500, width: 800, height: 500))
        #expect(frames[1] == MirrorWall.TileFrame(x: 800, y: 500, width: 800, height: 500))
        #expect(frames[2] == MirrorWall.TileFrame(x: 0, y: 0, width: 800, height: 500))
        #expect(frames[3] == MirrorWall.TileFrame(x: 800, y: 0, width: 800, height: 500))
    }

    @Test func windowFramesNeverOverlap() {
        for count in 1 ... MirrorWall.maximumDevices {
            let frames = MirrorWall.windowFrames(in: screen, count: count)
            #expect(frames.count == count)
            for (index, frame) in frames.enumerated() {
                for other in frames[(index + 1)...] {
                    let separated = frame.x + frame.width <= other.x
                        || other.x + other.width <= frame.x
                        || frame.y + frame.height <= other.y
                        || other.y + other.height <= frame.y
                    #expect(separated, "\(count) windows overlap at \(index)")
                }
            }
        }
    }

    @Test func windowFramesStayInsideTheGivenArea() {
        let area = MirrorWall.TileFrame(x: 120, y: 60, width: 1200, height: 800)
        for frame in MirrorWall.windowFrames(in: area, count: 5) {
            #expect(frame.x >= area.x)
            #expect(frame.y >= area.y)
            #expect(frame.x + frame.width <= area.x + area.width)
            #expect(frame.y + frame.height <= area.y + area.height)
        }
    }
}
