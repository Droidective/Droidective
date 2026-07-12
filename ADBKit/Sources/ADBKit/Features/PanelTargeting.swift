import Foundation

/// Pure device-target resolution for the Quick Actions panel. The panel must
/// resolve its own targets from an explicit pick, an approved "All devices"
/// set, the device-bar selection, and the currently-ready devices — never the
/// app's `targetSerials`, whose run-on-all state belongs to the hidden main
/// window. Kept here as plain serials (no `Device`, no app state) so these
/// rules — the source of several panel targeting bugs — are tested directly.
public enum PanelTargeting {
    /// The single device a panel action targets: the most recent pick (dropped
    /// when that device is no longer ready), else the device-bar selection
    /// (when ready), else the first ready device — nil when nothing is ready.
    public static func singleTarget(
        picked: String?, selected: String?, ready: [String]
    ) -> String? {
        if let picked, ready.contains(picked) { return picked }
        if let selected, ready.contains(selected) { return selected }
        return ready.first
    }

    /// The serials an "All devices" approval still covers: approved ∩ ready, in
    /// the approved order; nil when the approval covers nothing live. A device
    /// attached *after* the approval isn't in `approved`, so it's never
    /// targeted — the approval can only shrink as devices drop, never grow.
    public static func approvedTargets(
        approved: [String]?, ready: [String]
    ) -> [String]? {
        guard let approved else { return nil }
        let readySet = Set(ready)
        let live = approved.filter(readySet.contains)
        return live.isEmpty ? nil : live
    }

    /// The concrete serials a run hits: for a feature that supports run-all,
    /// the approved fan-out when more than one approved device is still ready;
    /// otherwise the single target as a one-element list ([] when nothing is
    /// ready). An approval that has shrunk to one live device collapses to it —
    /// no spurious single-device fan-out. A feature without `supportsRunAll`
    /// never fans out, matching the main window (whose run-on-all toggle is
    /// gated on the same flag) — an "All devices" approval then falls through
    /// to the single-target rule.
    public static func fanOut(
        picked: String?, selected: String?, approved: [String]?, ready: [String],
        supportsRunAll: Bool
    ) -> [String] {
        if supportsRunAll,
           let live = approvedTargets(approved: approved, ready: ready), live.count > 1 {
            return live
        }
        return singleTarget(picked: picked, selected: selected, ready: ready).map { [$0] } ?? []
    }

    /// Explicit run targets for a feature: nil when it needs no device (passed
    /// straight through to `run`, which then targets none), else `fanOut`.
    /// Returning the panel's own targets — never the device bar's — is what
    /// keeps the hidden window's run-on-all state from fanning a single pick
    /// out, and a guard-deferred device switch from retargeting the run.
    public static func runTargets(
        needsDevice: Bool, supportsRunAll: Bool, picked: String?, selected: String?,
        approved: [String]?, ready: [String]
    ) -> [String]? {
        guard needsDevice else { return nil }
        return fanOut(
            picked: picked, selected: selected, approved: approved, ready: ready,
            supportsRunAll: supportsRunAll
        )
    }
}
