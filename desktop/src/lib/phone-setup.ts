/**
 * The phone set-up sheet's three rows, its button and its subtitle — the Mac's
 * `PhoneSetupSheet`, with its wording.
 *
 * Only presentation lives here. What is missing, what a run does about the
 * app, and whether anything is left to do arrive from the daemon
 * (`PhoneSetupStatus`), so this decides how a row reads, never what the
 * phone's state is.
 */

import type { PhoneSetupStatus, StreamedPhoneSetupStatus } from "@/lib/wire"

export type RowKind = "checking" | "done" | "todo" | "unavailable"

export interface SetupRow {
  title: string
  kind: RowKind
  detail: string
}

const APP_NAME = "Droidective for Android"

export const SUBTITLE =
  "Installs or updates the app from GitHub, grants it the permissions only adb can, " +
  "and starts Shizuku if it’s there."

/** The Mac's Android 11 floor, `PhoneAppReleases.minimumSdk`. */
const MINIMUM_SDK = 30

/** "DUMP", "WRITE_SECURE_SETTINGS and DUMP", "A, B and C": ADBKit's `readableList`. */
export function readableList(names: string[]): string {
  const last = names.at(-1)
  if (names.length < 2 || last === undefined) return names[0] ?? ""
  return `${names.slice(0, -1).join(", ")} and ${last}`
}

/** `android.permission.DUMP` → `DUMP`. */
export function shortPermission(permission: string): string {
  return permission.split(".").at(-1) ?? permission
}

/** The button's verb: what pressing it does first. */
export function actionTitle(status: PhoneSetupStatus | null): string {
  switch (status?.step) {
    case "install":
      return "Install"
    case "update":
      return "Update"
    default:
      return "Set Up"
  }
}

/**
 * A streamed status in the shape the routes deliver.
 *
 * Route replies cross Rust's typed structs, which write a nil as `null`;
 * stream items cross untyped, so Swift's omitted keys stay omitted. One place
 * fills them in, so the rows never see `undefined`.
 */
export function streamedStatus(raw: StreamedPhoneSetupStatus): PhoneSetupStatus {
  const offer = raw.offer
  return {
    appInstalled: raw.appInstalled,
    appVersion: raw.appVersion ?? null,
    sdk: raw.sdk ?? null,
    grantedPermissions: raw.grantedPermissions ?? [],
    missingPermissions: raw.missingPermissions ?? [],
    shizukuInstalled: raw.shizukuInstalled ?? false,
    shizukuRunning: raw.shizukuRunning ?? false,
    needsSetup: raw.needsSetup ?? false,
    latestVersion: raw.latestVersion ?? null,
    latestProblem: raw.latestProblem ?? null,
    step: raw.step ?? "none",
    hasWork: raw.hasWork ?? false,
    offer:
      offer === undefined
        ? null
        : { kind: offer.kind, menuTitle: offer.menuTitle, from: offer.from ?? null, to: offer.to ?? null },
  }
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
  const latest = status.latestVersion ?? ""
  if (status.step === "install") {
    return { title, kind: "todo", detail: `Not installed. Install downloads ${latest} from GitHub.` }
  }
  if (status.step === "update") {
    const installed = status.appVersion ?? "An older version"
    return { title, kind: "todo", detail: `${installed} is installed. Update installs ${latest}.` }
  }
  if (!status.appInstalled) return { title, ...absentApp(status) }
  const detail = status.appVersion === null ? APP_NAME : `${APP_NAME} ${status.appVersion}`
  return { title, kind: "done", detail }
}

/** Why a phone without the app can't be given it from here. */
function absentApp(status: PhoneSetupStatus): Omit<SetupRow, "title"> {
  if (status.sdk !== null && status.sdk < MINIMUM_SDK) {
    return { kind: "unavailable", detail: `Not installed. ${APP_NAME} needs Android 11 or later.` }
  }
  if (status.latestProblem !== null) {
    return {
      kind: "unavailable",
      detail: `Not installed, and the latest release couldn't be found: ${status.latestProblem}`,
    }
  }
  return { kind: "todo", detail: "Not installed." }
}

function permissionsRow(status: PhoneSetupStatus): SetupRow {
  const title = "Permissions granted"
  if (!status.appInstalled) return { title, kind: "unavailable", detail: "Needs the app." }
  if (status.missingPermissions.length > 0) {
    const missing = readableList(status.missingPermissions.map(shortPermission))
    return { title, kind: "todo", detail: `Missing ${missing}.` }
  }
  const granted = readableList(status.grantedPermissions.map(shortPermission))
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
