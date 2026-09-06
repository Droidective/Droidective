import ADBKit
import Foundation

/// A tab's live mirror session, kept per window by `FeatureStateStore` rather
/// than as view `@State`.
///
/// A mirror is the most expensive thing a tab can hold: a scrcpy server on the
/// device, a video encoder, an `adb forward` tunnel and a decoder on this side.
/// Rebuilding the view — which a tab does whenever it moves to the other split
/// pane or to another window — used to tear all of that down and start it
/// again, so a move flashed "Connecting…" and cost a second or two of black
/// while the device re-primed. Worse, a recording in progress went with it.
///
/// The session survives instead. The display layer it feeds is adopted by the
/// receiving window's view (`MirrorLayerNSView.adopt(displayLayer:)`), which is
/// the whole reason that method exists; nothing about the stream is touched.
///
/// Everything here is about the *session*, not the view — including the
/// in-flight connect, which must be allowed to finish rather than be cancelled
/// half-way by a window change and leave a started-but-dead model behind.
@MainActor
@Observable
final class MirrorTabModel {
    /// The live session, nil when nothing is connected.
    var session: MirrorViewModel?
    /// The in-flight (re)connect, so a newer one can cancel and supersede it.
    var connectTask: Task<Void, Never>?
    /// Identifies the recording leave guard, so a stale clear can't wipe
    /// another's — and so the window this tab moves to re-registers the same one.
    let exitGuardID = UUID()

    /// Give the device up for good — the tab closed, or its window did.
    func shutDown() {
        connectTask?.cancel()
        connectTask = nil
        let leaving = session
        session = nil
        Task { await leaving?.stop() }
    }
}

/// The Mirror Wall's live sessions, kept the same way and for the same reasons —
/// six of them at once, which is six encoders a move used to stop and restart.
@MainActor
@Observable
final class MirrorWallTabModel {
    var wall: MirrorWallModel?

    /// Terminal, unlike `suspend()`: a wall that has been shut down refuses to
    /// start anything else, which is what stops a tab closing during quit from
    /// resurrecting a session that then outlives the process.
    func shutDown() {
        wall?.shutDown()
        wall = nil
    }
}
