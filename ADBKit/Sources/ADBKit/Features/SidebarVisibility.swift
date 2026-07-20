import Foundation

/// Pure reconciliation of the sidebar's visibility, kept out of the view so the
/// rules are tested and the call sites (the device-bar button, the Settings ▸
/// Appearance toggle) can't drift.
///
/// The fixed (pinned) sidebar and the Dock-style auto-hide overlay have separate
/// visibility flags, and only one is active per mode. A split-resize eviction
/// (`hideSidebarForSplitRoom`) can leave the pinned sidebar hidden
/// (`fixedVisible == false`) while still in fixed mode — the state that made the
/// device-bar button's first click a dead no-op.
public enum SidebarVisibility {
    /// Visibility after a plain mode switch to `autoHide` (the Settings ▸
    /// Appearance toggle). Entering auto-hide leaves the sidebar at rest —
    /// hidden until a hover/⌘B peek — so the overlay stays down; leaving it
    /// always restores the pinned sidebar. Neither direction strands the user
    /// with both hidden.
    public static func afterModeChange(autoHide: Bool, fixedVisible: Bool)
        -> (fixedVisible: Bool, overlayShown: Bool)
    {
        (fixedVisible: autoHide ? fixedVisible : true, overlayShown: false)
    }

    /// The next state after the device-bar sidebar button is pressed. When the
    /// pinned sidebar is hidden in fixed mode (a split-resize evicted it), the
    /// click just brings it back — no mode change — so it's never a dead click.
    /// Otherwise it flips the mode, reconciled for the new mode.
    public static func afterButtonPress(autoHide: Bool, fixedVisible: Bool)
        -> (autoHide: Bool, fixedVisible: Bool, overlayShown: Bool)
    {
        if !autoHide, !fixedVisible {
            return (autoHide: false, fixedVisible: true, overlayShown: false)
        }
        let flipped = !autoHide
        let next = afterModeChange(autoHide: flipped, fixedVisible: fixedVisible)
        return (autoHide: flipped, fixedVisible: next.fixedVisible, overlayShown: next.overlayShown)
    }
}
