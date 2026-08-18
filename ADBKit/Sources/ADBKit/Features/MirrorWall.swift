import Foundation

/// Pure layout and selection math for the Mirror Wall — several devices
/// mirrored side by side in one pane, each on its own scrcpy session.
///
/// UI-free so the grid shape, the per-tile stream quality, the selection cap
/// and the pop-out window tiling are unit-tested without a device or a view.
public enum MirrorWall {
    /// How many devices one wall streams at once. Every tile is a separate
    /// device-side H.264 encoder and a separate decoder on the Mac, so the cap
    /// is a real ceiling rather than a UI convenience.
    public static let maximumDevices = 6

    /// Narrowest tile that still shows a usable phone screen. Below this the
    /// auto grid drops a column instead of shrinking further.
    public static let minimumTileWidth = 260.0

    // MARK: - Grid

    /// Columns the auto layout uses for `tiles` tiles in a pane `paneWidth`
    /// wide.
    ///
    /// The preferred shape is picked per count rather than from a square root:
    /// phone tiles are portrait, so three across reads better than 2 + 1 for
    /// three devices, while four want a 2 × 2. The pane then clamps it — a
    /// narrow split drops columns rather than squeezing tiles below
    /// `minimumTileWidth`.
    public static func columns(paneWidth: Double, tiles: Int) -> Int {
        guard tiles > 1 else { return 1 }
        let preferred = switch min(tiles, maximumDevices) {
        case 2: 2
        case 3: 3
        case 4: 2
        default: 3
        }
        return min(preferred, max(1, fittingColumns(paneWidth: paneWidth)))
    }

    /// Columns for an explicit user choice, clamped to something drawable: at
    /// least one, never more than there are tiles. Deliberately *not* clamped
    /// by pane width — a manual choice is the user overruling the auto layout,
    /// so it stands even when the tiles get small.
    public static func columns(manual: Int, tiles: Int) -> Int {
        min(max(manual, 1), max(tiles, 1))
    }

    private static func fittingColumns(paneWidth: Double) -> Int {
        guard paneWidth.isFinite, paneWidth > 0 else { return 1 }
        return Int(paneWidth / minimumTileWidth)
    }

    // MARK: - Per-tile stream quality

    /// What one tile asks the device-side server for. A tile is a fraction of
    /// the pane, so full-mirror resolution is decode work nobody can see.
    public struct Quality: Sendable, Equatable {
        /// scrcpy `max_size` — longest side in px.
        public var maxSize: Int
        /// scrcpy `max_fps` — 0 leaves the device uncapped.
        public var maxFps: Int

        public init(maxSize: Int, maxFps: Int) {
            self.maxSize = maxSize
            self.maxFps = maxFps
        }
    }

    /// The single mirror's quality — what one tile gets, so a one-device wall
    /// looks exactly like the Mirror Screen tab.
    public static let fullQuality = Quality(maxSize: 1280, maxFps: 0)

    /// Quality for each tile of a `tiles`-tile wall. Frame rate is capped only
    /// once several encoders are running: it costs the least of what's on
    /// offer, and mirroring six devices is triage, not video review.
    public static func quality(tiles: Int) -> Quality {
        switch max(tiles, 1) {
        case 1: fullQuality
        case 2: Quality(maxSize: 1024, maxFps: 0)
        case 3, 4: Quality(maxSize: 800, maxFps: 30)
        default: Quality(maxSize: 640, maxFps: 24)
        }
    }

    // MARK: - Selection

    /// Reconcile a stored selection against what's connected: keep the chosen
    /// order and drop devices that left.
    ///
    /// `nil` means nobody has picked yet — a wall opened for the first time —
    /// which fills with the first `maximumDevices` connected devices so the
    /// feature shows something immediately. An *explicitly emptied* selection
    /// (`[]`) stays empty: refilling it would undo the unchecking that emptied
    /// it.
    public static func reconciled(selection: [String]?, connected: [String]) -> [String] {
        guard let selection else { return capped(connected) }
        let live = Set(connected)
        return capped(selection.filter { live.contains($0) })
    }

    /// Add or remove one device, keeping selection order and the cap. Adding
    /// past the cap is refused rather than evicting someone else's tile — the
    /// checkbox that would exceed it is disabled, and this is the guard behind
    /// that.
    public static func toggled(_ serial: String, in selection: [String]) -> [String] {
        if let index = selection.firstIndex(of: serial) {
            var result = selection
            result.remove(at: index)
            return result
        }
        guard selection.count < maximumDevices else { return selection }
        return selection + [serial]
    }

    /// Whether one more device can join.
    public static func canAdd(to selection: [String]) -> Bool {
        selection.count < maximumDevices
    }

    private static func capped(_ serials: [String]) -> [String] {
        Array(serials.prefix(maximumDevices))
    }

    // MARK: - Pop-out window tiling

    /// A rectangle in screen coordinates. Deliberately not `CGRect`: this math
    /// is portable ADBKit, and the App layer converts.
    public struct TileFrame: Sendable, Equatable {
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
    }

    /// Frames that tile `count` pop-out mirror windows across `area` (a
    /// screen's visible frame), left to right then top to bottom — what
    /// "Arrange Windows" applies. The user can drag them anywhere afterwards;
    /// this only supplies the starting grid.
    ///
    /// `area` is in screen coordinates, whose origin is bottom-left, so the
    /// first row is laid out at the *top* of the area. Rows come from the same
    /// column shape the in-pane grid uses, so a wall broken out into windows
    /// keeps its arrangement.
    public static func windowFrames(in area: TileFrame, count: Int) -> [TileFrame] {
        guard count > 0, area.width > 0, area.height > 0 else { return [] }
        let columnCount = max(1, min(columns(paneWidth: area.width, tiles: count), count))
        let rowCount = Int((Double(count) / Double(columnCount)).rounded(.up))
        let width = area.width / Double(columnCount)
        let height = area.height / Double(rowCount)
        var frames: [TileFrame] = []
        for index in 0 ..< count {
            let column = index % columnCount
            let row = index / columnCount
            frames.append(TileFrame(
                x: area.x + Double(column) * width,
                y: area.y + area.height - Double(row + 1) * height,
                width: width,
                height: height))
        }
        return frames
    }
}
