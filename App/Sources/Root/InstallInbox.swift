import Foundation

/// Buffers APKs opened from Finder until the UI is ready to receive them — a
/// double-clicked APK can reach the app delegate before `RootView` appears on a
/// cold launch. Drained to `onReceive` (set by RootView), which routes them to
/// the Install App feature.
@MainActor
final class InstallInbox {
    static let shared = InstallInbox()
    private var pending: [URL] = []
    var onReceive: (([URL]) -> Void)? { didSet { drain() } }

    /// True while APKs wait for the UI. On a cold launch this means the app
    /// was launched *to open an APK* (the open event precedes window
    /// creation) — RootView uses it to keep that launch panel-only.
    var hasPending: Bool { !pending.isEmpty }

    func receive(_ urls: [URL]) {
        pending.append(contentsOf: urls)
        drain()
    }

    private func drain() {
        guard let onReceive, !pending.isEmpty else { return }
        let urls = pending
        pending = []
        onReceive(urls)
    }
}
