/**
 * The saved custom commands.
 *
 * Their own module rather than more of `daemon-settings.ts`, which is at the
 * line budget that made it a separate file to begin with. Re-exported from
 * `@/lib/daemon`, which stays the one import for everything that talks to the
 * daemon.
 */

import { invoke } from "@tauri-apps/api/core"
import type { CommandPreset, CustomCommand, RunResponse } from "@/lib/wire"

/** The saved custom commands. */
export function customCommands(): Promise<{
  commands: CustomCommand[]
  presets: CommandPreset[]
}> {
  return invoke("custom_commands")
}

/**
 * Replaces the whole list.
 *
 * The whole list rather than an add or a delete: this side holds what it is
 * showing, so a per-item verb would make the daemon re-derive it — the same
 * shape the deep links use.
 */
export function writeCustomCommands(
  commands: CustomCommand[],
): Promise<{ commands: CustomCommand[]; presets: CommandPreset[] }> {
  return invoke("write_custom_commands", { commands })
}

/** Runs one saved command on one device. */
export function runCustomCommand(
  id: string,
  serial: string,
  bundleId: string | null,
): Promise<RunResponse> {
  return invoke("run_custom_command", { id, serial, bundleId })
}
