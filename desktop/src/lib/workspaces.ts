/**
 * Which window is holding what — `ADBKit.WorkspaceRegistry`, ported.
 *
 * The *state* lives in the Rust process, because that is this app's
 * one-per-app place (the Mac's is `AppCore`). The rules live here, pure, for
 * the reason they live in ADBKit there: they are the part that has to be right
 * and the part that is easy to test without a window.
 */

/** The first window's label. Tauri creates it from `tauri.conf.json`. */
export const MAIN_WINDOW = "main"

/** One window's claim, as the Rust side broadcasts it. */
export interface WindowClaim {
  label: string
  /** 1 for the first window, 2 for the next. Never reused within a session. */
  ordinal: number
  serial: string | null
  /** Every open feature, not only the exclusive ones. */
  features: string[]
}

/**
 * Features that cannot run twice against one device.
 *
 * `WorkspaceRegistry.exclusiveFeatureIDs`, with the same reasons: scrcpy and
 * screen recording share the device's one H.264 encoder, the JS console loses
 * its CDP target to whichever client connected last, and Frida owns a port.
 *
 * `mirror-wall` is deliberately **not** here, exactly as on the Mac: a
 * whole-pane banner over the window's selected device would block five working
 * tiles because of the sixth, so it contends per tile instead.
 */
export const EXCLUSIVE_FEATURE_IDS: readonly string[] = [
  "scrcpy",
  "screen-record",
  "js-console",
  "frida-console",
]

export function isExclusive(featureId: string): boolean {
  return EXCLUSIVE_FEATURE_IDS.includes(featureId)
}

/**
 * The window already running `featureId` against `serial`, if it is not this
 * one.
 *
 * Null covers all three "nothing to say" cases — the feature is not exclusive,
 * no device is selected, or this window is the only claimant — because the
 * banner's condition is exactly "somebody else has it".
 */
export function claimantOf(
  featureId: string,
  serial: string | null,
  claims: WindowClaim[],
  self: string,
): WindowClaim | null {
  if (serial === null || !isExclusive(featureId)) return null
  return (
    claims.find(
      (claim) =>
        claim.label !== self && claim.serial === serial && claim.features.includes(featureId),
    ) ?? null
  )
}

/**
 * The window whose bar is pointed at `serial`, if it is not this one.
 *
 * Selecting a device another window holds focuses that window rather than
 * duplicating it — the Mac's rule, and the reason it is worth knowing before
 * the selection is applied.
 */
export function windowHolding(
  serial: string,
  claims: WindowClaim[],
  self: string,
): WindowClaim | null {
  return claims.find((claim) => claim.label !== self && claim.serial === serial) ?? null
}

/** "Window 2" — what a Focus button and a device menu call a window. */
export function windowTitle(ordinal: number): string {
  return `Window ${String(ordinal)}`
}

/**
 * The colour a window's device icon takes.
 *
 * Null for the first window, which keeps the app accent — `DeviceTint` on the
 * Mac tints only the windows *after* the first, so one window looks exactly as
 * it always did and a second one is visibly a second one.
 */
export function windowTint(ordinal: number): string | null {
  if (ordinal <= 1) return null
  const palette = ["#4aa3ff", "#e2b341", "#c678dd", "#e8755c", "#41d6c3"]
  return palette[(ordinal - 2) % palette.length] ?? null
}

/**
 * Whether this window should show anything about other windows at all.
 *
 * One window is the ordinary case and must look untouched: no Windows section
 * in the device menu, no tint, no banners.
 */
export function hasOtherWindows(claims: WindowClaim[], self: string): boolean {
  return claims.some((claim) => claim.label !== self)
}

/** This window's own row, once it has published one. */
export function selfClaim(claims: WindowClaim[], self: string): WindowClaim | null {
  return claims.find((claim) => claim.label === self) ?? null
}
