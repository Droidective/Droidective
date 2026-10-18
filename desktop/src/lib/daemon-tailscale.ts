/**
 * Tailscale mode — the device menu's Tailscale section.
 *
 * Its own module so `daemon.ts` stays inside its line budget; `@/lib/daemon`
 * re-exports it, so it stays the one import.
 */

import { invoke } from "@tauri-apps/api/core"

import type { RunResponse, TailscalePeer, TailscaleStatus } from "@/lib/wire"

/**
 * The tailnet's Android phones that adb does not already list. Always a
 * background read on the daemon's side: the menu asks on every open.
 */
export function tailscaleStatus(): Promise<TailscaleStatus> {
  return invoke<TailscaleStatus>("tailscale_status")
}

/** `adb connect` to one peer by its 100.x address, exactly as the status sent it. */
export function connectTailscale(peer: TailscalePeer): Promise<RunResponse> {
  return invoke<RunResponse>("connect_tailscale", { peer })
}

/** `adb tcpip 5555` on a USB phone, and nothing more. */
export function prepareForTailscale(serial: string): Promise<RunResponse> {
  return invoke<RunResponse>("prepare_for_tailscale", { serial })
}
