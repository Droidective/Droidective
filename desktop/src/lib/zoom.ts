/**
 * ⌘= / ⌘- UI zoom, ported from `AppState`'s font scaling.
 *
 * The Mac scales its window content with a `scaleEffect` because macOS ignores
 * SwiftUI's dynamic type; a webview reaches the same outcome with CSS `zoom` on
 * the root, which grows every font, icon and control together and reflows the
 * layout rather than magnifying a snapshot. The steps are the Mac's, so the same
 * number of presses lands on the same size in both apps.
 */

export const ZOOM_STEPS: readonly number[] = [0.8, 0.9, 1.0, 1.15, 1.3, 1.5, 1.75, 2.0]

/** The step that means "no zoom". `ZOOM_STEPS[DEFAULT_ZOOM_STEP]` is exactly 1. */
export const DEFAULT_ZOOM_STEP = 2

export function clampZoomStep(step: number): number {
  if (!Number.isFinite(step)) return DEFAULT_ZOOM_STEP
  return Math.min(Math.max(Math.round(step), 0), ZOOM_STEPS.length - 1)
}

export function zoomScale(step: number): number {
  return ZOOM_STEPS[clampZoomStep(step)] ?? 1
}

/**
 * How the zoom reads in the UI — "100%", "115%".
 *
 * Rounded, because 1.15 is 114.99999999999999% in binary floating point and a
 * menu item that says so is a bug report waiting to happen.
 */
export function zoomLabel(step: number): string {
  return `${String(Math.round(zoomScale(step) * 100))}%`
}
