/**
 * The wire shapes for the per-device screens.
 *
 * Split out of `wire.ts` when it outgrew its line budget, and split *here*
 * because these all read and write the state of one device: Developer
 * Options, the dev-time restrictions, Wi-Fi, Private DNS, and the four
 * screens that hang off a chosen package. Every one is re-exported from
 * `@/lib/wire`, so no import moved.
 */

import type { FileEntry } from "@/lib/wire"

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

// MARK: - the per-app screens

export interface AppInfoResponse {
  /** False is an answer, not a failure — the Mac shows "Not installed". */
  installed: boolean
  versionName: string
  versionCode: string
  targetSdk: string
  minSdk: string
  firstInstall: string
  lastUpdate: string
  apkPath: string | null
  apkSizeBytes: number | null
}

export interface Permission {
  name: string
  /** "CAMERA" — sent rather than derived, so both UIs split a name the same. */
  shortName: string
  granted: boolean
}

export interface PermissionsResponse {
  permissions: Permission[]
}

export interface MemRow {
  key: string
  value: string
}

export interface MemInfoResponse {
  /** False when the app has no process. Not an error. */
  running: boolean
  totalPssKb: number | null
  /** In `dumpsys meminfo`'s own order — the order is information. */
  summary: MemRow[]
}

export interface SandboxResponse {
  path: string
  entries: FileEntry[]
  /** False when `run-as` refused — a release build, which is normal. */
  debuggable: boolean
}

export interface AppPullResponse {
  /** An APK pull can answer several — a bundle install has splits. */
  paths: string[]
}

// MARK: - the Android emulator

export interface Avd {
  name: string
  /** Underscores read as spaces. Sent rather than derived. */
  displayName: string
  /** The adb serial, when this AVD is running right now. */
  runningSerial: string | null
}

export interface EmulatorsResponse {
  avds: Avd[]
  /** False when the emulator binary is not on this machine. */
  installed: boolean
}

/**
 * What can be done to an AVD. The daemon owns this list and refuses anything
 * else, so these are its strings spelled its way.
 */
export type EmulatorAction = "launch" | "coldBoot" | "wipeData" | "relaunch" | "stop"

// MARK: - installing an app package

/** One device's outcome. Per device, not one collapsed verdict. */
export interface InstallOutcome {
  serial: string
  ok: boolean
  message: string
}

export interface InstallResponse {
  outcomes: InstallOutcome[]
  fileName: string
}

// MARK: - deep links, the bug report, and the toolchain

/**
 * One saved deep link.
 *
 * `id` travels back unchanged so an edit updates rather than duplicating, and
 * `createdAt` is epoch millis — the store's own shape, shared with the Mac.
 */
export interface DeepLink {
  id: string
  label: string
  url: string
  createdAt: number
}

/** One device's answer to a launch. Per device, as an install's outcomes are. */
export interface LaunchOutcome {
  serial: string
  ok: boolean
  message: string
}

export interface LaunchResponse {
  outcomes: LaunchOutcome[]
}

export interface BugReportResponse {
  /** Where the zip landed, for the Show in folder button. */
  path: string
}

/** One external tool, as the Doctor reports it. */
export interface ToolReport {
  /** adb, scrcpy, ffmpeg, emulator. */
  id: string
  installed: boolean
  path: string | null
  version: string | null
  /** Where to get it. Neither app ever installs a tool itself. */
  installHint: string
}

export interface ToolsResponse {
  /** In the registry's own order, so the Doctor's rows do not shuffle. */
  tools: ToolReport[]
}
