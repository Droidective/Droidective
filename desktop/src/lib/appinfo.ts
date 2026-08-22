/**
 * What the per-app screens work out for themselves.
 *
 * The device answers are parsed in ADBKit and the daemon passes them through;
 * what is left is the arranging — which rows App Info shows and in what order,
 * how a byte count reads, and the Mac's wording for a multi-file APK pull.
 * None of it needs a device, so all of it is tested.
 */

import type { AppInfoResponse, MemInfoResponse } from "@/lib/wire"

export interface Row {
  label: string
  value: string
}

/**
 * The App Info rows, in the Mac's order.
 *
 * APK Size is last and only present when the device reported one — a "—" there
 * would look like a failed read rather than a package manager that did not say.
 */
export function infoRows(info: AppInfoResponse): Row[] {
  const rows: Row[] = [
    { label: "Version", value: info.versionName },
    { label: "Version Code", value: info.versionCode },
    { label: "Target SDK", value: info.targetSdk },
    { label: "Min SDK", value: info.minSdk },
    { label: "First Install", value: info.firstInstall },
    { label: "Last Update", value: info.lastUpdate },
  ]
  if (info.apkSizeBytes !== null) {
    rows.push({ label: "APK Size", value: formatBytes(info.apkSizeBytes) })
  }
  return rows
}

/**
 * A byte count as `ByteCountFormatter(.file)` prints it — decimal units, so a
 * 12,345-byte APK reads "12.3 kB" on both platforms rather than "12.1 KiB" on
 * one of them.
 */
export function formatBytes(bytes: number): string {
  if (bytes < 1000) return `${String(bytes)} bytes`
  const units = ["kB", "MB", "GB", "TB"]
  let value = bytes / 1000
  let unit = 0
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000
    unit += 1
  }
  return `${value.toFixed(1)} ${units[unit] ?? "TB"}`
}

/**
 * The Mac's toast for an APK pull.
 *
 * An App Bundle install saves splits beside the base, and spelling out how
 * many is what stops the extra files being a surprise.
 */
export function pulledApkMessage(paths: readonly string[]): string {
  const splits = paths.length - 1
  if (splits <= 0) return "APK saved"
  return `APK + ${String(splits)} split${splits === 1 ? "" : "s"} saved`
}

/** Memory's headline: total PSS, or why there is none. */
export function memoryHeadline(info: MemInfoResponse): string {
  if (!info.running) return "Not running"
  if (info.totalPssKb === null) return "No memory reported"
  return formatBytes(info.totalPssKb * 1000)
}

/**
 * Whether a permission matches a filter.
 *
 * Matched against both the short name and the full one, because people search
 * for "CAMERA" and paste "android.permission.CAMERA" in roughly equal measure.
 */
export function permissionMatches(
  permission: { name: string; shortName: string },
  query: string,
): boolean {
  const needle = query.trim().toLowerCase()
  if (needle === "") return true
  return (
    permission.shortName.toLowerCase().includes(needle) ||
    permission.name.toLowerCase().includes(needle)
  )
}

/** The parent of a sandbox path, or null at the app's root. */
export function sandboxParent(path: string, root: string): string | null {
  if (path === root || !path.startsWith(root)) return null
  const cut = path.lastIndexOf("/")
  if (cut <= 0) return root
  const parent = path.slice(0, cut)
  return parent.length < root.length ? root : parent
}

/** The app's sandbox root on the device. */
export function sandboxRoot(packageId: string): string {
  return `/data/data/${packageId}`
}
