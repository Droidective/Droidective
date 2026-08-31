/**
 * The translucent-window appearance — ported from ADBKit's `WindowEffects`.
 *
 * Pure, and deliberately the same arithmetic as the Mac's rather than a
 * lookalike: the two apps have to turn the same stored opacity into the same
 * glass, or a window set up on one machine looks wrong on the other.
 *
 * One thing does *not* port, and it is named here because it is a real
 * difference rather than an omission: the Mac's Blur is a slider, driving a
 * window-server blur radius. No other platform exposes a radius — Windows has
 * Acrylic and Mica, both on-or-off, and Linux leaves window blur entirely to
 * the compositor — so `blurRadius` has no counterpart and the desktop's Blur is
 * a switch. See `docs/desktop-parity.md`.
 */

/** Opacity floor — near-invisible but never gone, so the window stays findable. */
export const MINIMUM_OPACITY = 0.1

/** Full grain maps to this alpha; past it the speckle eats text contrast. */
export const MAXIMUM_GRAIN_ALPHA = 0.2

/** Stored values can be out of range; everything downstream reads through this. */
export function clampedOpacity(opacity: number): number {
  if (!Number.isFinite(opacity)) return 1
  return Math.min(Math.max(opacity, MINIMUM_OPACITY), 1)
}

/** A 0…1 slider amount, pinned; non-finite reads as 0. */
export function clampedAmount(amount: number): number {
  if (!Number.isFinite(amount)) return 0
  return Math.min(Math.max(amount, 0), 1)
}

/**
 * The effect engages only below full opacity, so 100% keeps the exact
 * pre-feature rendering: opaque window, no blur, no grain film.
 */
export function isTranslucent(opacity: number): boolean {
  return clampedOpacity(opacity) < 0.999
}

/**
 * Lifted surfaces — the sidebar, cards, bars — STACK on the root wash, so they
 * carry only the contrast step: an alpha sized so root + surface composites to
 * roughly the root plus 0.15 instead of compounding to near-solid.
 */
export function cardAlpha(rootOpacity: number): number {
  const root = clampedOpacity(rootOpacity)
  if (!isTranslucent(root)) return 1
  return Math.min(0.15 / Math.max(1 - root, 0.15), 1)
}

/**
 * The grain film's alpha. Independent of the window opacity on purpose: the
 * film reads as texture over a solid window just as well as over glass.
 */
export function grainOpacity(amount: number): number {
  return clampedAmount(amount) * MAXIMUM_GRAIN_ALPHA
}

/** The percent readout beside a slider — the Mac's rounding, so they agree. */
export function percentLabel(value: number): string {
  return `${String(Math.round(value * 100))}%`
}

/**
 * A `#rrggbb` token re-expressed at an alpha.
 *
 * The palette tokens are hex because that is what the asset catalog holds;
 * translucency needs the same colours with an alpha channel, and rewriting the
 * palette in `rgb()` throughout would make every token harder to compare with
 * the Mac's. Anything unparseable is handed back untouched — a token that is
 * already a function or a named colour should not be corrupted into one.
 */
export function withAlpha(hex: string, alpha: number): string {
  const parsed = /^#([0-9a-f]{6})$/iu.exec(hex.trim())
  if (parsed === null) return hex
  const value = Number.parseInt(parsed[1] ?? "", 16)
  const red = (value >> 16) & 0xff
  const green = (value >> 8) & 0xff
  const blue = value & 0xff
  if (alpha >= 0.999) return hex
  // Three decimals: enough that a 1% slider step is a distinct colour, short
  // enough that the inspected value is readable.
  const rounded = Math.round(clampedAmount(alpha) * 1000) / 1000
  return `rgb(${String(red)} ${String(green)} ${String(blue)} / ${String(rounded)})`
}
