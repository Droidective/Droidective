/**
 * Geometry for the API pane's two draggable seams —
 * `ADBKit/Services/ApiClient/ApiPaneLayout.swift`, ported.
 *
 * Kept out of the components for the reason `panes.ts` is: the drag gesture
 * and the layout have to agree about the bounds, and they only reliably do
 * that when one tested function decides them.
 *
 * The sidebar is stored as a width (it should not grow with the window) and
 * the split as a fraction (it should), which is why they clamp differently.
 */

export const SIDEBAR_MIN = 200
export const SIDEBAR_MAX = 460
export const FRACTION_MIN = 0.25
export const FRACTION_MAX = 0.75

/**
 * An absolute floor on top of the fraction, so a tight window shrinks both
 * panes evenly rather than squeezing one to nothing.
 */
export const MIN_PANE = 240

/** Narrower than this and the sidebar overlays rather than sitting beside. */
export const NARROW_PANE = 760

/** Narrower than this and the toolbar wraps and the tabs abbreviate. */
export const COMPACT_PANE = 620

/**
 * The sidebar never takes more than a third of the pane, so the request and
 * response columns keep the room they need on a narrow window.
 */
export function sidebarWidth(stored: number, total: number): number {
  const clamped = Math.min(SIDEBAR_MAX, Math.max(SIDEBAR_MIN, stored))
  if (total <= 0) return clamped
  return Math.min(clamped, Math.max(SIDEBAR_MIN, total / 3))
}

export function clampedFraction(fraction: number): number {
  return Math.min(FRACTION_MAX, Math.max(FRACTION_MIN, fraction))
}

function paneFloor(total: number): number {
  return Math.min(MIN_PANE, total / 2)
}

/** The leading pane's length, with the absolute floor applied on both sides. */
export function leadingLength(total: number, fraction: number): number {
  if (total <= 0) return 0
  const floor = paneFloor(total)
  const wanted = total * clampedFraction(fraction)
  return Math.min(Math.max(wanted, floor), total - floor)
}

/**
 * The fraction a drag lands on: where it started, plus how far it moved as a
 * share of the current total. Both halves come from the same `total`, so the
 * seam cannot be converted through one width and back through another.
 */
export function fractionFrom(start: number, movedBy: number, total: number): number {
  if (total <= 0) return clampedFraction(start)
  return clampedFraction(start + movedBy / total)
}
