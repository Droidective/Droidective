import Foundation

/// Moving one tab out of a window: what the receiving window opens with.
///
/// A tab that leaves its window has to take its *context* with it, or the move
/// silently changes what the user is looking at. The context is exactly what a
/// window persists, so the seed is a `WindowState` and the receiving window
/// restores from it through the same path a relaunch uses — no second restore
/// code, and no way for the two to drift.
///
/// Pure and value-typed so the rules below are tested without a window.
public enum TabHandoff {
    /// Per-feature state the source window holds on the moving tab's behalf.
    ///
    /// A window keeps a few pieces of state *for* a feature rather than inside
    /// it, because they outlive the view: the terminal's working directories
    /// (snapshotted when its shells are killed) and the Mirror Wall's chosen
    /// devices. Those have to travel with the tab; nothing else does. Handing
    /// a torn-off Logcat the source's terminal directories would resurrect
    /// them in a window that has no Terminal tab.
    public struct Carry: Sendable, Equatable {
        /// Working directories of the source's terminal shells, snapshotted as
        /// they were killed for the move. Only meaningful for `terminal`.
        public var terminalResumeDirs: [String]?
        /// Devices the source's Mirror Wall showed, in tile order. Only
        /// meaningful for `mirror-wall`.
        public var mirrorWallSerials: [String]?

        public init(terminalResumeDirs: [String]? = nil, mirrorWallSerials: [String]? = nil) {
            self.terminalResumeDirs = terminalResumeDirs
            self.mirrorWallSerials = mirrorWallSerials
        }

        public static let none = Carry()
    }

    /// The feature id whose tab owns `Carry.terminalResumeDirs`.
    public static let terminalFeatureID = "terminal"
    /// The feature id whose tab owns `Carry.mirrorWallSerials`.
    public static let mirrorWallFeatureID = "mirror-wall"

    /// The receiving window's opening state.
    ///
    /// - The device and app bundle are **inherited**, never re-picked: a window
    ///   opened by any other route deliberately lands on a device no other
    ///   window holds (`firstFreeSerial`), which for a moved tab would swap the
    ///   device out from under it — you tore off one phone's logcat and got
    ///   another's.
    /// - Exactly one tab, in one pane. Home is not seeded: the strip's
    ///   permanent house button is always one click away, and a moved tab
    ///   arriving beside a Home tab it didn't ask for reads as clutter.
    /// - Carried state is filtered to the feature that owns it (see `Carry`).
    public static func seed(
        featureID: String,
        from source: WindowState,
        newID: WorkspaceID,
        carrying carry: Carry = .none
    ) -> WindowState {
        WindowState(
            id: newID,
            serial: source.serial,
            bundleId: source.bundleId,
            tabGroups: [TabGroupState(tabs: [featureID], activeTab: featureID)],
            focusedGroup: 0,
            terminalResumeDirs: featureID == terminalFeatureID ? carry.terminalResumeDirs : nil,
            mirrorWallSerials: featureID == mirrorWallFeatureID ? carry.mirrorWallSerials : nil
        )
    }
}
