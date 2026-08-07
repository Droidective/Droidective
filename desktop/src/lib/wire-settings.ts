/**
 * The wire shapes for the device-state and network screens.
 *
 * Split out of `wire.ts` when it outgrew its line budget, and split *here*
 * because these are the screens that read and write one device's settings —
 * Developer Options, the dev-time restrictions, Wi-Fi and Private DNS. Every
 * one of them is re-exported from `@/lib/wire`, so no import moved.
 */

/**
 * One Developer Options row — what it is, and what the device reports.
 *
 * The title and detail arrive from the daemon rather than being written here.
 * `DeveloperSettingsService` holds one declarative table of them and the Mac's
 * panel renders straight from it, so a copy on this side would be a second
 * table to keep in agreement — the same reason the feature registry travels
 * instead of being restated.
 */
export interface DevToggle {
  id: string
  title: string
  detail: string
  on: boolean
}

export interface DevScale {
  id: string
  title: string
  value: number
}

export interface DevSettingsResponse {
  toggles: DevToggle[]
  scales: DevScale[]
  /** The steps the picker offers, from the service rather than from here. */
  scaleChoices: number[]
}

export interface RestrictionsResponse {
  adbInstallVerification: boolean
  packageVerifier: boolean
  stayAwake: boolean
  hiddenApiEnforced: boolean
  /**
   * Null when `getenforce` said neither — "we could not tell" is a different
   * claim from "permissive", and neither is shown as the other.
   */
  selinuxEnforcing: boolean | null
  /** Whether the root-only half of the screen is reachable at all. */
  hasRootShell: boolean
}

/**
 * The restrictions the daemon will write. It owns this list and refuses
 * anything else, so these are its strings spelled its way.
 */
export type RestrictionKey =
  | "adbInstallVerification"
  | "packageVerifier"
  | "stayAwake"
  | "hiddenApiEnforced"
  | "selinuxEnforcing"

export interface WifiStatus {
  enabled: boolean
  connected: boolean
  ssid: string | null
  ipAddress: string | null
  linkSpeed: string | null
  frequency: string | null
  signal: string | null
}

export interface SavedNetwork {
  id: string
  ssid: string
  security: string | null
  /** Only ever present on a rooted device — it comes from WifiConfigStore.xml. */
  password: string | null
}

export interface WifiResponse {
  status: WifiStatus
  networks: SavedNetwork[]
  /** Why a password is missing, rather than implying there is none. */
  hasRootShell: boolean
}

/** off | automatic | hostname — the daemon's own spelling. */
export type DnsMode = "off" | "automatic" | "hostname"

export interface DnsResponse {
  mode: DnsMode
  hostname: string | null
}
