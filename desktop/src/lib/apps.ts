import type { AppActionDescriptor, AppSummary } from "@/lib/wire"

/**
 * Pure rules for the Apps pane.
 *
 * The verbs and their destructive flags come from the daemon; only the English
 * belongs here. A label this file does not know still renders — the daemon is
 * the authority on which verbs exist, so an unrecognised one must not vanish
 * from the UI.
 */

const LABELS: Record<string, string> = {
  open: "Open",
  restart: "Restart",
  stop: "Force Stop",
  minimize: "Minimize",
  clearCache: "Clear Cache",
  clearData: "Clear Data",
  uninstall: "Uninstall",
}

export function actionLabel(action: AppActionDescriptor): string {
  return LABELS[action.id] ?? titleCase(action.id)
}

/** "clearCache" → "Clear Cache", for a verb shipped after this build. */
function titleCase(id: string): string {
  const spaced = id.replaceAll(/([a-z\d])([A-Z])/gu, "$1 $2")
  return spaced.charAt(0).toUpperCase() + spaced.slice(1)
}

/**
 * Filters the list, mirroring `AppListing.matches`: package id, display name
 * or version. System apps are hidden unless asked for — there are hundreds of
 * them and they bury the handful anyone is looking for.
 */
export function searchApps(
  apps: AppSummary[],
  query: string,
  includeSystem: boolean,
): AppSummary[] {
  const needle = query.toLowerCase().trim()
  return apps.filter((app) => {
    if (!includeSystem && app.isSystem) return false
    if (needle === "") return true
    return (
      app.packageId.toLowerCase().includes(needle) ||
      app.displayName.toLowerCase().includes(needle) ||
      (app.versionName?.toLowerCase().includes(needle) ?? false)
    )
  })
}

/** User apps first, then system, each alphabetical by display name. */
export function sortApps(apps: AppSummary[]): AppSummary[] {
  return apps.toSorted((a, b) => {
    if (a.isSystem !== b.isSystem) return a.isSystem ? 1 : -1
    return a.displayName.localeCompare(b.displayName)
  })
}
