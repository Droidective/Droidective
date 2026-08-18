import ADBKit
import AppKit
import Foundation
import Observation

/// Drives the Mirror Wall: one `MirrorViewModel` per streaming tile, plus the
/// tile state the grid draws (which are paused, which one has focus).
///
/// A wall is a set of *independent* sessions — the encoder it contends for is
/// the device's, so two devices never contend — which makes this bookkeeping
/// rather than a second mirror implementation. Every tile is the same session
/// the full-pane mirror runs, asking for less resolution
/// (`MirrorWall.quality(tiles:)`) because it's drawn a fraction of the size.
@MainActor
@Observable
final class MirrorWallModel {
    /// Live sessions by serial. No entry means not streaming: paused, taken by
    /// another window, or still to be started by the next reconcile.
    private(set) var streams: [String: MirrorViewModel] = [:]
    /// Tiles the user paused. Kept by serial (not by index) so pausing survives
    /// a reorder, and a device that drops and comes back stays paused.
    private(set) var pausedSerials: Set<String> = []
    /// The tile that takes clipboard and audio. Keyboard follows AppKit's own
    /// first responder — clicking a tile makes its view first responder — so
    /// this exists for the focus ring, the audio choice, and the header's
    /// per-device actions.
    private(set) var focused: String?
    /// Whether the focused tile streams device audio. Off by default, like the
    /// single mirror: six audio graphs is not what a wall is for, and moving
    /// focus restarts the session that carries it.
    private(set) var audioOnFocused = false

    private let adb: AdbClient
    private let locator: ToolLocator
    /// Tile order (the picked devices) and the devices another window is
    /// already mirroring — held so the wall's own actions (pause, reconnect,
    /// focus) can reconcile without the view passing them again.
    private var order: [String] = []
    private var blocked: Set<String> = []
    /// One chain of work per serial. Connects and teardowns for a tile must
    /// never interleave — that's what leaves an orphaned session streaming with
    /// nothing holding it (see `ScreenMirrorView.scheduleReconnect`). One entry
    /// per serial the wall has ever streamed — a drained `Task` holds nothing of
    /// its body, and the key set is bounded by the devices the user picked, so
    /// there's nothing here to prune.
    private var work: [String: Task<Void, Never>] = [:]
    /// The pending start pass — see `MirrorWall.startCoalescingDelay`. Stops run
    /// immediately; only starts wait for the device list to settle.
    private var pendingStart: Task<Void, Never>?
    /// Terminal: set by `stopAll()` and never cleared. A wall going away must
    /// not start anything else, and it can be *asked* to during its own
    /// teardown — a mirror tab closing at quit releases its device, which the
    /// still-mounted wall would otherwise pick up and stream past the app's
    /// lifetime (the session outlives the process; see `MirrorViewModel.stopped`
    /// for the same trap one layer down).
    private var stopped = false

    /// Whether this wall has been shut down for good. A view whose `@State`
    /// outlived its own `onDisappear` must build a fresh model rather than hold
    /// an inert one, which would show black tiles with no way back.
    var isShutDown: Bool { stopped }

    init(adb: AdbClient, locator: ToolLocator) {
        self.adb = adb
        self.locator = locator
    }

    // MARK: - Reading

    func stream(_ serial: String) -> MirrorViewModel? { streams[serial] }

    func isPaused(_ serial: String) -> Bool { pausedSerials.contains(serial) }

    /// Devices this wall currently holds a session on — what the window
    /// registers as its claims, so no other window starts a second encoder on
    /// one of them.
    var liveSerials: Set<String> { Set(streams.keys) }

    // MARK: - Driving

    /// Point the wall at a tile order and the set of devices another window is
    /// already mirroring. Starts what's missing, stops what's no longer wanted,
    /// and keeps focus on a tile that still exists.
    func sync(order: [String], blocked: Set<String>) {
        self.order = order
        self.blocked = blocked
        reconcile()
    }

    func togglePause(_ serial: String) {
        if pausedSerials.contains(serial) {
            pausedSerials.remove(serial)
        } else {
            pausedSerials.insert(serial)
        }
        reconcile()
    }

    /// Drop a tile's session and start a fresh one — the failed/stopped card's
    /// button.
    func reconnect(_ serial: String) {
        guard let model = streams.removeValue(forKey: serial) else {
            reconcile()
            return
        }
        schedule(serial) { await model.stop() }
        reconcile()
    }

    /// Move focus. The audio stream follows it when audio is on, which restarts
    /// both sessions involved — the reason it's opt-in.
    func focus(_ serial: String) {
        guard focused != serial else { return }
        let previous = focused
        focused = serial
        guard audioOnFocused else { return }
        if let previous { setAudio(false, on: previous) }
        setAudio(true, on: serial)
    }

    func setAudioOnFocused(_ on: Bool) {
        guard audioOnFocused != on else { return }
        audioOnFocused = on
        guard let focused else { return }
        setAudio(on, on: focused)
    }

    /// Stop every session but stay resumable — the wall has been hidden past
    /// its grace window, and returning to the tab syncs it back up. Teardown
    /// outlives the view, the way the single mirror's does.
    func suspend() {
        pendingStart?.cancel()
        pendingStart = nil
        let leaving = streams
        streams = [:]
        for (serial, model) in leaving {
            schedule(serial) { await model.stop() }
        }
    }

    /// The wall is gone for good (tab closed, window closing, app quitting).
    /// Terminal, so nothing can talk it into starting another session on the way
    /// out — see `stopped`.
    func shutDown() {
        stopped = true
        suspend()
    }

    /// Grab one tile's current frame. The wall owns the Discard/Save/Edit
    /// prompt (a tile has no room for it), so the capture is handed back rather
    /// than left on the tile's own pending slot.
    func captureScreenshot(_ serial: String) async -> NSImage? {
        guard let model = streams[serial] else { return nil }
        await model.takeScreenshot()
        let image = model.pendingScreenshot
        model.pendingScreenshot = nil
        return image
    }

    // MARK: - Internals

    private func reconcile() {
        guard !stopped else { return }
        let wanted = MirrorWall.streamingSerials(
            order: order, paused: pausedSerials, blocked: blocked)
        // Stop at once: a device this wall no longer wants must be released
        // without waiting on anything.
        let wantedSet = Set(wanted)
        for (serial, model) in streams where !wantedSet.contains(serial) {
            streams.removeValue(forKey: serial)
            schedule(serial) { await model.stop() }
        }
        if wanted.contains(where: { streams[$0] == nil }) { scheduleStartPass() }
        if let focused, order.contains(focused) { return }
        focused = wanted.first ?? order.first
    }

    /// Start the tiles that have no session, once the device list has settled.
    /// Coalesced because devices arrive across `adb devices` polls and a tile's
    /// quality is chosen from the tile *count* — starting on the first arrival
    /// gave the first device a one-tile encoder on a six-tile wall.
    private func scheduleStartPass() {
        guard pendingStart == nil else { return }
        pendingStart = Task { [weak self] in
            try? await Task.sleep(for: MirrorWall.startCoalescingDelay)
            guard !Task.isCancelled else { return }
            self?.startPass()
        }
    }

    private func startPass() {
        pendingStart = nil
        guard !stopped else { return }
        let wanted = MirrorWall.streamingSerials(
            order: order, paused: pausedSerials, blocked: blocked)
        // Quality is fixed when a tile starts. Re-deriving it for the tiles
        // already streaming would restart live sessions every time a device was
        // plugged in — the settle delay above is what keeps a wall's tiles
        // matched in practice.
        let quality = MirrorWall.quality(tiles: order.count)
        for serial in wanted where streams[serial] == nil {
            let model = MirrorViewModel(
                adb: adb, locator: locator, serial: serial,
                includeAudio: audioOnFocused && serial == focused,
                showTouches: false,
                quality: quality)
            streams[serial] = model
            schedule(serial) { await model.start() }
        }
    }

    private func setAudio(_ on: Bool, on serial: String) {
        guard let model = streams[serial] else { return }
        schedule(serial) { await model.setAudio(on) }
    }

    /// Queue work behind whatever this serial is already doing, so a stop can't
    /// land in the middle of a connect.
    private func schedule(_ serial: String, _ body: @escaping @Sendable () async -> Void) {
        let previous = work[serial]
        work[serial] = Task {
            await previous?.value
            await body()
        }
    }
}
