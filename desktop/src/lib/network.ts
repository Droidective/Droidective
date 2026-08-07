/**
 * What the Wi-Fi and Private DNS screens work out for themselves.
 *
 * The device answers are parsed in ADBKit; what is left here is presentation —
 * the headline over the status card, the detail line beside it, and which
 * security modes the connect form offers. All of it is copied from
 * `WiFiView` and `PrivateDnsSection` rather than invented, and none of it
 * needs a device, so all of it is tested.
 */

import type { DnsMode, SavedNetwork, WifiStatus } from "@/lib/wire"

/**
 * The big line on the status card.
 *
 * The SSID when there is one, and otherwise the reason there isn't — "Not
 * connected" and "Wi-Fi off" are different problems and the Mac distinguishes
 * them.
 */
export function wifiHeadline(status: WifiStatus | null): string {
  if (status === null) return "Wi-Fi off"
  if (status.ssid !== null && status.ssid !== "") return status.ssid
  return status.enabled ? "Not connected" : "Wi-Fi off"
}

/**
 * The muted line under it: IP · link speed · frequency · signal.
 *
 * Only while connected, and only the parts the device reported — a lone
 * separator where a value should be reads as a bug.
 */
export function wifiDetail(status: WifiStatus | null): string {
  if (status === null || !status.connected) return ""
  return [status.ipAddress, status.linkSpeed, status.frequency, status.signal]
    .filter((part): part is string => part !== null && part !== "")
    .join(" · ")
}

/**
 * The security modes the connect form offers.
 *
 * A closed set, and the daemon refuses anything outside it: the value reaches
 * `cmd wifi connect-network` as a keyword in the argument vector, not as a
 * quoted value. The labels are the Mac's.
 */
export const SECURITY_MODES: readonly { value: string; label: string }[] = [
  { value: "wpa2", label: "WPA2" },
  { value: "wpa3", label: "WPA3" },
  { value: "open", label: "Open" },
]

/** Whether Connect should be enabled. The Mac gates on a non-empty SSID. */
export function canConnect(ssid: string, busy: boolean): boolean {
  return !busy && ssid.trim() !== ""
}

/** A saved network's password, if one was readable. */
export function revealedPassword(network: SavedNetwork, revealed: boolean): string | null {
  if (network.password === null || network.password === "") return null
  return revealed ? network.password : "••••••••"
}

/** What the saved-networks card says when it has nothing to list. */
export function savedEmptyText(loaded: boolean): string {
  return loaded ? "No saved networks reported (needs Android 11+)." : "Loading…"
}

/** The Mac's three Private DNS choices, in its order. */
export const DNS_MODES: readonly { value: DnsMode; label: string }[] = [
  { value: "off", label: "Off" },
  { value: "automatic", label: "Automatic" },
  { value: "hostname", label: "Hostname" },
]

/**
 * Whether Apply should be enabled.
 *
 * Hostname mode with nothing typed would write an empty specifier and leave
 * DNS broken, so the Mac disables Apply rather than letting it through — and
 * the daemon refuses it too, because a UI is not a security boundary.
 */
export function canApplyDns(mode: DnsMode, hostname: string, ready: boolean): boolean {
  if (!ready) return false
  return mode !== "hostname" || hostname.trim() !== ""
}
