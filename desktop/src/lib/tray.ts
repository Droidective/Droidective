import type { FeatureSummary } from "@/lib/wire"

/**
 * What the tray icon offers — the Mac's `MenuBarView`, row for row.
 *
 * Pure, because every decision in it is one: which features appear, what a
 * missing device reads as, where the separators fall. The Rust side renders
 * what this returns and forwards the clicks back (see `src-tauri/src/tray.rs`).
 */

export interface TrayEntry {
  /** Empty for a separator. */
  id: string
  label: string
  /** False renders a label rather than a command — the device name is one. */
  enabled: boolean
}

const SEPARATOR: TrayEntry = { id: "", label: "", enabled: true }

/** A feature row's id, so the click handler can tell them from the fixed rows. */
export const FEATURE_PREFIX = "feature."

export const TRAY_QUICK = "tray.quick-actions"
export const TRAY_SCREENSHOT = "tray.screenshot"
export const TRAY_MIRROR = "tray.mirror"
export const TRAY_OPEN = "tray.open"
export const TRAY_QUIT = "tray.quit"

/**
 * The features the tray lists — `AppState.menuBarFeatures`.
 *
 * The Mac's three cases in its order: the ones explicitly chosen, else the
 * pinned ones, else every enabled instant action. Screenshot and Mirror Screen
 * are excluded from that last case because they have rows of their own above,
 * and the Mac excludes them for the same reason.
 */
export function trayFeatures(
  features: readonly FeatureSummary[],
  {
    chosen,
    favorites,
    disabled,
  }: { chosen: readonly string[]; favorites: readonly string[]; disabled: readonly string[] },
): FeatureSummary[] {
  const listed = (ids: readonly string[]) =>
    ids
      .map((id) => features.find((feature) => feature.id === id))
      .filter((feature) => feature !== undefined)
  if (chosen.length > 0) return listed(chosen)
  if (favorites.length > 0) return listed(favorites)
  return features.filter(
    (feature) =>
      feature.kind === "instantAction" &&
      feature.id !== "screenshot" &&
      feature.id !== "scrcpy" &&
      !disabled.includes(feature.id),
  )
}

/**
 * The whole menu.
 *
 * The Mac's order, which is worth keeping literally: the device you are
 * pointed at, then the three things worth doing with no window at all, then
 * what you chose, then the way back in and the way out.
 */
export function trayMenu({
  deviceLabel,
  features,
}: {
  deviceLabel: string | null
  features: readonly FeatureSummary[]
}): TrayEntry[] {
  return [
    { id: "tray.device", label: deviceLabel ?? "No device", enabled: false },
    SEPARATOR,
    { id: TRAY_QUICK, label: "Quick Actions…", enabled: true },
    { id: TRAY_SCREENSHOT, label: "Screenshot", enabled: true },
    { id: TRAY_MIRROR, label: "Mirror Screen", enabled: true },
    SEPARATOR,
    ...features.map((feature) => ({
      id: `${FEATURE_PREFIX}${feature.id}`,
      label: feature.title,
      enabled: true,
    })),
    ...(features.length > 0 ? [SEPARATOR] : []),
    { id: TRAY_OPEN, label: "Open Droidective", enabled: true },
    { id: TRAY_QUIT, label: "Quit Droidective", enabled: true },
  ]
}

/** The feature id behind a row, or null for one of the fixed rows. */
export function featureOfTrayCommand(id: string): string | null {
  return id.startsWith(FEATURE_PREFIX) ? id.slice(FEATURE_PREFIX.length) : null
}
