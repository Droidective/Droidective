import Observation

/// Observable progress for a managed-tool download. Main-actor isolated, so it's
/// safe to capture in the `@Sendable` progress callback `ManagedToolStore` calls
/// from a background queue (the callback hops back to the main actor to update).
@MainActor
@Observable
final class DownloadState {
    /// 0…1 once the total size is known; nil means indeterminate.
    private(set) var fraction: Double?
    private(set) var active = false
    private(set) var label: String?

    func begin(_ label: String) {
        active = true
        fraction = nil
        self.label = label
    }

    func update(_ value: Double) {
        if value >= 0, value <= 1 { fraction = value }
    }

    func finish() {
        active = false
        fraction = nil
        label = nil
    }
}
