import Foundation

/// Gates the JS console's auto-connect on target *stability*: a target must be
/// listed in two consecutive discovery passes before it's attached to.
///
/// Attaching the instant a target first appears crashed the app under debug —
/// the runtime was still booting when the debugger connected and Hermes's
/// attach-time replay hit it mid-init (its debugger serialization is fragile
/// on 0.84–0.86; see the upstream crash notes). One extra ~2s pass lets the
/// app settle. A *relaunched* app registers with a fresh target id, so it is
/// re-gated automatically; a target that merely reconnects (JS reload, socket
/// drop) has been listed all along and passes immediately. The user's manual
/// pick never goes through this gate.
public struct TargetStabilityTracker: Sendable, Equatable {
    private var seenLastPass: Set<String> = []
    private var stable: Set<String> = []

    public init() {}

    /// Record one discovery pass's target ids. A target becomes stable on its
    /// second consecutive sighting and stays stable while it remains listed;
    /// vanishing from a pass resets it (the next appearance is a fresh boot).
    public mutating func recordPass(ids: some Sequence<String>) {
        let current = Set(ids)
        stable = current.intersection(seenLastPass.union(stable))
        seenLastPass = current
    }

    /// Whether this target has been listed in at least the last two passes.
    public func isStable(_ id: String) -> Bool {
        stable.contains(id)
    }
}
