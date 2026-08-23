/**
 * Whether the sidebar is pinned or Dock-style auto-hiding, ported from ADBKit's
 * `SidebarVisibility` — the same two transitions, so the two apps cannot
 * disagree about what the sidebar button does.
 *
 * Three flags rather than one, because "hidden" means two different things: in
 * fixed mode the sidebar is pinned and `visible` says whether it is there at
 * all; in auto-hide mode it is out of the layout entirely and `overlayShown`
 * says whether it is currently peeked over the content.
 */

export interface SidebarMode {
  autoHide: boolean
  /** Whether the pinned sidebar is in the layout. Only read in fixed mode. */
  visible: boolean
  /** Whether the auto-hiding sidebar is peeked. Only read in auto-hide mode. */
  overlayShown: boolean
}

export function pinnedSidebar(): SidebarMode {
  return { autoHide: false, visible: true, overlayShown: false }
}

/**
 * After a plain mode switch — the Settings ▸ Appearance toggle.
 *
 * Entering auto-hide leaves the sidebar at rest, hidden until a hover or ⌘B;
 * leaving it always restores the pinned sidebar. Neither direction can strand
 * someone with both hidden, which is the whole point of doing this in one place.
 */
export function afterModeChange(mode: SidebarMode, autoHide: boolean): SidebarMode {
  return { autoHide, visible: autoHide ? mode.visible : true, overlayShown: false }
}

/**
 * After the device bar's sidebar button.
 *
 * When the pinned sidebar is hidden in fixed mode — a split-resize evicted it —
 * the click just brings it back, with no mode change, so it is never a dead
 * click. Otherwise it flips the mode.
 */
export function afterButtonPress(mode: SidebarMode): SidebarMode {
  if (!mode.autoHide && !mode.visible) return pinnedSidebar()
  return afterModeChange(mode, !mode.autoHide)
}

/**
 * After ⌘B, which peeks rather than switching modes: in auto-hide it slides the
 * overlay in and out, and in fixed mode it takes the pinned sidebar away and
 * brings it back. The Mac's `toggleSidebar`.
 */
export function afterToggle(mode: SidebarMode): SidebarMode {
  return mode.autoHide
    ? { ...mode, overlayShown: !mode.overlayShown }
    : { ...mode, visible: !mode.visible }
}

/** Whether the sidebar occupies layout width right now. */
export function occupiesLayout(mode: SidebarMode): boolean {
  return !mode.autoHide && mode.visible
}

/** Whether the sidebar is drawn over the content right now. */
export function isPeeked(mode: SidebarMode): boolean {
  return mode.autoHide && mode.overlayShown
}
