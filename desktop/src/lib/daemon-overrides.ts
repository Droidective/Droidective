/**
 * Device-state overrides: what is in effect, and clearing it.
 *
 * Its own module rather than another pair in `daemon-settings.ts`, which is at
 * its line budget; `@/lib/daemon` re-exports both, so it stays the one import.
 */

import { invoke } from "@tauri-apps/api/core"

import type { ActiveOverride, RunResponse } from "@/lib/wire"

/**
 * The device-state overrides in effect.
 *
 * Reconciled against the device rather than read from a record: a proxy
 * someone cleared in Settings is not an override any more, and a screen
 * offering to reset it would be lying.
 */
export function activeOverrides(serial: string): Promise<{ overrides: ActiveOverride[] }> {
  return invoke<{ overrides: ActiveOverride[] }>("active_overrides", { serial })
}

/** Clear one override, or every one of them when `kind` is omitted. */
export function resetOverrides(serial: string, kind?: string): Promise<RunResponse> {
  return invoke<RunResponse>("reset_overrides", { serial, kind: kind ?? null })
}
