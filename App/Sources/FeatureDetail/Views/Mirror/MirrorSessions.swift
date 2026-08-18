import Foundation

/// Every live mirror session in the app, so quit can tear them down instead of
/// dying with them half-open.
///
/// A session's teardown is asynchronous — it terminates the `adb shell` child
/// *and* removes the `adb forward` tunnel it opened (`MirrorTransport.stop`).
/// At quit the process exits long before a fire-and-forget teardown gets there,
/// so the tunnel stays registered in the long-lived adb server: one leaked
/// listening socket per session, per quit, until `adb kill-server`. One mirror
/// tab leaked one; a six-tile wall leaks six.
///
/// `AppCore.finishQuitNow` already defers termination for the MCP server, the
/// Reactotron relay and the layout flush — this rides the same deferral.
/// References are weak, so a view model the UI has let go of is never kept
/// alive here, and `forget` on `stop()` keeps the table from growing.
@MainActor
final class MirrorSessions {
    static let shared = MirrorSessions()

    private var live: [WeakSession] = []

    private struct WeakSession {
        weak var model: MirrorViewModel?
    }

    private init() {}

    /// A session started streaming. Compacts released entries as it goes, so
    /// nothing has to sweep the table separately.
    func note(_ model: MirrorViewModel) {
        live.removeAll { $0.model == nil || $0.model === model }
        live.append(WeakSession(model: model))
    }

    func forget(_ model: MirrorViewModel) {
        live.removeAll { $0.model == nil || $0.model === model }
    }

    var liveCount: Int {
        live.compactMap(\.model).count
    }

    /// Stop every live session and wait for it. Concurrently, because six
    /// sequential teardowns would show as a visibly slow quit — and each is
    /// independent (one device's tunnel and encoder per session).
    func stopAllForQuit() async {
        let models = live.compactMap(\.model)
        live = []
        guard !models.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            for model in models {
                group.addTask { await model.stop() }
            }
        }
    }
}
