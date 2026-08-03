/**
 * Geometry for the two-pane split, ported from ADBKit's `PaneSplit`.
 *
 * Kept out of the view for the reason the Swift version gives: the drag gesture
 * and the layout must not be able to disagree about the bounds. They did once —
 * the drag allowed 20…80% while the layout floored each pane at a fixed width.
 */

/** The seam between the panes. */
export const DIVIDER_WIDTH = 8

/**
 * A pane is never narrower than 30% of the split area — below that no feature
 * layout survives — and never wider than 70%.
 */
export const MIN_FRACTION = 0.3
export const MAX_FRACTION = 0.7

/** The absolute floor a pane keeps on top of the fraction, in pixels. */
const MIN_PANE_PX = 320

export function clampedFraction(fraction: number): number {
  return Math.min(MAX_FRACTION, Math.max(MIN_FRACTION, fraction))
}

/**
 * The left pane's width for a stored fraction.
 *
 * On top of the 30…70% clamp each pane keeps an absolute floor, so a tight
 * window shrinks both panes evenly instead of pushing the right one off-screen.
 */
export function leftWidth(total: number, fraction: number): number {
  const available = Math.max(0, total - DIVIDER_WIDTH)
  const floor = minPane(available)
  const clamped = available * clampedFraction(fraction)
  return Math.min(Math.max(clamped, floor), available - floor)
}

/** The fraction a divider dragged to `x` represents. */
export function fractionForDrag(x: number, total: number): number {
  const available = Math.max(0, total - DIVIDER_WIDTH)
  if (available <= 0) return MIN_FRACTION
  return clampedFraction(x / available)
}

function minPane(available: number): number {
  return Math.min(Math.max(MIN_PANE_PX, available * MIN_FRACTION), available / 2)
}
