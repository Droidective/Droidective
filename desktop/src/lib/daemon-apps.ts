/**
 * The installed-app surface: listing, the verbs, and the lifecycle.
 *
 * Split out of `daemon.ts` so that file stays inside its line budget;
 * `@/lib/daemon` re-exports every name here, so it remains the one import.
 */

import { invoke } from "@tauri-apps/api/core"

import type { AppsResponse, ForegroundResponse, RunResponse } from "@/lib/wire"

export function listApps(serial: string): Promise<AppsResponse> {
  return invoke<AppsResponse>("list_apps", { serial })
}

/** Everything `getprop` printed, as the daemon passed it through. */
export function deviceProps(serial: string): Promise<{ properties: Record<string, string> }> {
  return invoke<{ properties: Record<string, string> }>("device_props", { serial })
}

/** The frontmost app on the device, when there is one worth naming. */
/**
 * The process id an app is running under, or null when it is not running.
 *
 * Null is an answer rather than a failure: an app whose log you opened before
 * launching it is the ordinary case, and the log waits for it.
 */
export function logcatPid(serial: string, packageId: string): Promise<number | null> {
  return invoke<{ pid: number | null }>("logcat_pid", { serial, packageId }).then(
    (answer) => answer.pid ?? null,
  )
}

export function foregroundApp(serial: string): Promise<ForegroundResponse> {
  return invoke<ForegroundResponse>("foreground_app", { serial })
}

export function controlApp(args: {
  serial: string
  packageId: string
  action: string
}): Promise<RunResponse> {
  return invoke<RunResponse>("control_app", args)
}

/**
 * Disable, enable, remove for this user, or restore one package.
 *
 * Not an app *action*: these change what the package is for this user rather
 * than what it is doing, and both directions of both are reversible. Exactly
 * one of the two flags, which is what picks the verb — the daemon refuses a
 * body naming both or neither rather than guessing.
 */
export function appLifecycle(args: {
  serial: string
  packageId: string
  disabled?: boolean
  removed?: boolean
}): Promise<RunResponse> {
  return invoke<RunResponse>("app_lifecycle", {
    serial: args.serial,
    packageId: args.packageId,
    disabled: args.disabled ?? null,
    removed: args.removed ?? null,
  })
}
