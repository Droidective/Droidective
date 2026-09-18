import { invoke } from "@tauri-apps/api/core"

import type { CommandLogResponse, CrashListResponse, RunResponse } from "@/lib/wire"

/**
 * The two records you read when something went wrong: the device's crash
 * buffer, and this app's own log of the adb it ran.
 *
 * Split out of `daemon.ts` when it reached its line budget, and re-exported
 * from `@/lib/daemon` so there is still one import for everything the page
 * asks Rust for.
 */

/**
 * Every crash the device has recorded, newest first.
 *
 * `background` keeps the pane's first load and its five-second Watch poll out
 * of the Command Log, leaving only the Refresh button in it — the split
 * `CrashView.fetch(userInitiated:)` makes on the Mac.
 */
export function listCrashes(serial: string, background: boolean): Promise<CrashListResponse> {
  return invoke<CrashListResponse>("list_crashes", { serial, background })
}

/** The recent adb calls, most-recent-first. */
export function commandLog(): Promise<CommandLogResponse> {
  return invoke<CommandLogResponse>("command_log")
}

export function clearCommandLog(): Promise<RunResponse> {
  return invoke<RunResponse>("clear_command_log")
}

/** Empties `logcat -b crash` on the device. */
export function clearCrashes(serial: string): Promise<RunResponse> {
  return invoke<RunResponse>("clear_crashes", { serial })
}
