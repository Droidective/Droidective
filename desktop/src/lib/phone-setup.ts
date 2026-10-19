/**
 * The phone set-up sheet's three rows — the Mac's `PhoneSetupSheet` rows,
 * with its wording.
 *
 * Only presentation lives here. What is missing and whether anything is left
 * to do arrive from the daemon (`PhoneSetupStatus`), so this decides how a row
 * reads, never what the phone's state is.
 */

import type { PhoneSetupStatus } from "@/lib/wire"

export type RowKind = "checking" | "done" | "todo" | "unavailable"

export interface SetupRow {
  title: string
  kind: RowKind
  detail: string
}

const APP_NAME = "Droidective for Android"

/** `android.permission.DUMP` → `DUMP`. */
export function shortPermission(permission: string): string {
  return permission.split(".").at(-1) ?? permission
}

/**
 * The three rows for what the phone last reported.
 *
 * `status` is null before the first read answers (`checking`) and after one
 * that failed, which reads as "Couldn't read the phone." rather than as a
 * phone with nothing installed.
 */
export function setupRows(status: PhoneSetupStatus | null, checking: boolean): SetupRow[] {
  if (status === null) {
    const unread: Omit<SetupRow, "title"> = checking
      ? { kind: "checking", detail: "Checking…" }
      : { kind: "unavailable", detail: "Couldn't read the phone." }
    return [
      { title: "App installed", ...unread },
      { title: "Permissions granted", ...unread },
      { title: "Shizuku running", ...unread },
    ]
  }
  return [appRow(status), permissionsRow(status), shizukuRow(status)]
}

function appRow(status: PhoneSetupStatus): SetupRow {
  const title = "App installed"
  if (!status.appInstalled) {
    return { title, kind: "todo", detail: `Install ${APP_NAME} on the phone first.` }
  }
  const detail = status.appVersion === null ? APP_NAME : `${APP_NAME} ${status.appVersion}`
  return { title, kind: "done", detail }
}

function permissionsRow(status: PhoneSetupStatus): SetupRow {
  const title = "Permissions granted"
  if (!status.appInstalled) return { title, kind: "unavailable", detail: "Needs the app." }
  if (status.missingPermissions.length > 0) {
    const missing = status.missingPermissions.map(shortPermission).join(" and ")
    return { title, kind: "todo", detail: `Missing ${missing}.` }
  }
  const granted = status.grantedPermissions.map(shortPermission).join(" and ")
  return { title, kind: "done", detail: granted }
}

function shizukuRow(status: PhoneSetupStatus): SetupRow {
  const title = "Shizuku running"
  if (!status.shizukuInstalled) {
    return {
      title,
      kind: "unavailable",
      detail: "Not installed. Optional — it gives the app shell access.",
    }
  }
  return status.shizukuRunning
    ? { title, kind: "done", detail: "Running" }
    : { title, kind: "todo", detail: "Installed, not running." }
}
