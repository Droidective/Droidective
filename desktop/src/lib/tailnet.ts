/**
 * Tailscale mode's rules — ADBKit's `TailscalePeers` and `RemoteLink`, ported.
 *
 * Ported rather than served because they are asked of a serial on every
 * render: whether a device is reached over Tailscale is a property of its
 * `ip:port` serial, and a round trip to the daemon to learn it would be a
 * device title that flickers. The vectors in `tailnet.test.ts` are ADBKit's own
 * (`TailnetAddressTests`), so the two cannot drift without a test noticing.
 * The *wording* of every question is the daemon's — the registry's
 * `remoteLinkWarning` and the status's `prepareWarning` — and is never
 * restated here.
 */

import { isReady } from "@/lib/targets"
import type { Device } from "@/lib/wire"

/**
 * Whether `address` is in Tailscale's IPv4 block, 100.64.0.0/10 — the
 * carrier-grade NAT range, which an adb serial is otherwise never in.
 */
export function isTailnetAddress(address: string): boolean {
  const octets = address.split(".")
  if (octets.length !== 4) return false
  const values: number[] = []
  for (const octet of octets) {
    if (!/^[0-9]{1,3}$/u.test(octet)) return false
    const value = Number(octet)
    if (value > 255) return false
    values.push(value)
  }
  const [first, second] = values
  return first === 100 && second !== undefined && second >= 64 && second <= 127
}

/** Whether a device serial is a tailnet `ip:port` — a phone reached over Tailscale. */
export function isTailnetSerial(serial: string): boolean {
  const parts = serial.split(":")
  if (parts.length !== 2) return false
  const [host = "", port = ""] = parts
  return /^[0-9]+$/u.test(port) && isTailnetAddress(host)
}

/**
 * The device's title, as the Mac's `deviceTitle` ends it: a phone reached over
 * Tailscale says so as one more ` · ` part, because the mirror runs at the
 * remote preset and some features ask first there, and the title is where
 * someone looks for why. Not ready reads "<label> — <state>", as before.
 */
export function deviceTitle(device: Device): string {
  if (!isReady(device)) return `${device.label} — ${device.state}`
  const remote = device.platform === "android" && isTailnetSerial(device.serial)
  return remote ? `${device.label} · Tailscale` : device.label
}

/** The question a link-cutting feature asks first, or null when there is none. */
export interface LinkCutQuestion {
  title: string
  message: string
}

/**
 * `RemoteLink.confirmation`: ask before running a feature that can take a
 * phone off the network on one reached over Tailscale.
 *
 * `warning` is the feature's `remoteLinkWarning`, the registry's sentence. The
 * device named is the first tailnet target, by its label when it is known.
 */
export function linkCutQuestion(
  warning: string | null | undefined,
  serials: readonly string[],
  devices: readonly Device[],
): LinkCutQuestion | null {
  if (warning === null || warning === undefined) return null
  const remote = serials.find((serial) => isTailnetSerial(serial))
  if (remote === undefined) return null
  const name = devices.find((device) => device.serial === remote)?.label ?? remote
  return {
    title: `${name} is connected over Tailscale`,
    message: `${warning} If the link drops, reconnecting needs the phone in hand.`,
  }
}

/**
 * Whether the menu offers "Prepare … for Tailscale…" for this device: a ready
 * Android phone on a cable. A wireless one is already reachable without it,
 * and an emulator is not a phone a tailnet can reach.
 */
export function canPrepareForTailscale(device: Device | null): device is Device {
  return (
    device !== null &&
    device.platform === "android" &&
    isReady(device) &&
    !device.isWireless &&
    !device.serial.startsWith("emulator-")
  )
}

/** The prepare confirmation's title — `TailscaleService.prepareTitle`. */
export function prepareTitle(name: string): string {
  return `Prepare ${name} for Tailscale?`
}
