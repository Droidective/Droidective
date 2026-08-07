/**
 * The daemon's JSON shapes, as they arrive through the Rust command layer.
 *
 * These mirror `droidectived/Sources/DaemonCore/` — `docs/droidectived-protocol.md`
 * is the written contract. Nothing is reshaped on the way through, so a name
 * here that stops matching the daemon is a bug, not a translation.
 */

export interface Device {
  serial: string
  /** adb's own state string: "device", "offline", "unauthorized", … */
  state: string
  model: string | null
  product: string | null
  transportId: string | null
  label: string
  isWireless: boolean
  platform: "android" | "ios-simulator"
}

/** The `FeatureKind` case names, as `String(describing:)` renders them. */
export type FeatureKind = "instantAction" | "formAction" | "toggleAction" | "view" | "system"

/** The `FieldControl` case names. */
export type FieldControl = "text" | "number" | "select" | "switch" | "slider" | "bundle" | "preset"

export type FieldValue = string | number | boolean

export interface FieldOption {
  value: string
  label: string
}

export interface FeatureField {
  name: string
  label: string
  control: FieldControl
  options: FieldOption[]
  placeholder: string | null
  description: string | null
  defaultValue: FieldValue | null
  optional: boolean
  min: number | null
  max: number | null
  step: number | null
}

export interface FeatureSummary {
  id: string
  title: string
  subtitle: string | null
  keywords: string[]
  /** The `FeatureCategory` case name — "input", "deviceState", … */
  category: string
  kind: FeatureKind
  implemented: boolean
  needsDevice: boolean
  needsBundle: boolean
  isDestructive: boolean
  isAbsorbedByHub: boolean
  fields: FeatureField[]
}

export interface AppSummary {
  packageId: string
  /** Derived by the daemon from the package id, so clients do not drift. */
  displayName: string
  versionName: string | null
  isSystem: boolean
}

/** A verb the daemon accepts, with the runner's own destructive flag. */
export interface AppActionDescriptor {
  id: string
  isDestructive: boolean
}

export interface AppsResponse {
  apps: AppSummary[]
  actions: AppActionDescriptor[]
}

/**
 * How a selected app reaches a feature runner.
 *
 * `needsBundle` features are given it as a required parameter and the rest as
 * optional context — the same rule `AppState` applies on the Mac.
 */
export const PACKAGE_PARAM = "packageId"

export interface RunResponse {
  ok: boolean
  message: string
  copyText: string | null
  revealPath: string | null
  needsAdbKeyboard: boolean
}

/**
 * Every toggle action is driven by one implicit boolean named `on`, declared
 * nowhere in its `fields` — see `FeatureEngine` and the Mac's
 * `ToggleActionView`. The daemon's `aToggleActionIsDrivenByAnOnParameter`
 * test is what fails if that ever changes.
 */
export const TOGGLE_PARAM = "on"

/** The kinds this app can actually run. Views are whole screens it has yet to grow. */
export const RUNNABLE_KINDS: readonly FeatureKind[] = [
  "instantAction",
  "formAction",
  "toggleAction",
]

export function isRunnable(feature: FeatureSummary): boolean {
  return feature.implemented && RUNNABLE_KINDS.includes(feature.kind)
}

/** One signal behind the root verdict — a row, not just a boolean. */
export interface RootSignal {
  name: string
  detail: string
  indicatesRoot: boolean
}

export interface RootStatusResponse {
  /** `su -c id` really answered uid 0 — what root-gated browsing needs. */
  hasRootShell: boolean
  likelyRooted: boolean
  summary: string
  signals: RootSignal[]
}

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

/** One row of `ls -la`, as the daemon parsed it. */
export interface FileEntry {
  name: string
  isDir: boolean
  size: number
  /** The mode column — "drwxrwx---". */
  perms: string
}

export interface FilesListResponse {
  /** Echoed by the daemon, so a late reply can be told from the current one. */
  path: string
  entries: FileEntry[]
}

/**
 * The mutations `/v1/files/op` accepts.
 *
 * The daemon owns this list and refuses anything else before it reaches a
 * device shell; these are the strings it knows, spelled its way.
 */
export type FileOperation = "makeDirectory" | "delete" | "copy" | "move"

export interface FileDetails {
  type: string
  sizeBytes: number | null
  owner: string
  permissions: string
  modified: string
  /** Last metadata change. Android records no creation time. */
  changed: string
}

export interface FileInfoResponse {
  /** Null when the device could not stat the path — an answer, not a fault. */
  info: FileDetails | null
}

export interface FilePullResponse {
  /** Where it landed on this computer, for the Show in folder button. */
  path: string
}

/** One crash, as `CrashParser` split it out of a logcat buffer. */
export interface CrashReport {
  /** Stable across refetches, so a watch poll does not move the selection. */
  id: string
  /** A `CrashReport.Kind` raw value: java, native, reactNative, anr, unknown. */
  kind: string
  /** Sent by the daemon so both UIs name a kind the same way. */
  kindLabel: string
  /** Logcat's own timestamp. A string — logcat prints no year. */
  timestamp: string | null
  process: string | null
  pid: number | null
  title: string
  /** The block as logcat printed it. */
  raw: string
  /** The block with the threadtime prefixes stripped. */
  body: string
}

export interface CrashListResponse {
  /** Newest first. */
  crashes: CrashReport[]
}

/** One performance sample, from `/v1/stream`'s `performance` topic. */
export interface PerfSample {
  /**
   * Empty on the first sample: a CPU percentage is a delta and there is
   * nothing yet to subtract from. `-1` is the all-cores aggregate.
   */
  cores: { core: number; label: string; usagePercent: number }[]
  ramTotalKb: number | null
  ramUsedKb: number | null
  appFps: number | null
  /** Percent of frames that missed the deadline, when any were drawn. */
  appJankPercent: number | null
  appPssKb: number | null
  downloadBytesPerSec: number | null
  uploadBytesPerSec: number | null
  processes: { pid: number; name: string; cpuPercent: number | null; pssKb: number | null }[]
}

export type DaemonStatus =
  | { state: "starting" }
  | { state: "ready"; port: number }
  | { state: "failed"; message: string }

/** A subscription update, shaped like the daemon's own stream event. */
export type StreamUpdate<Item> =
  | { event: "subscribed" }
  | { event: "batch"; items: Item[] }
  | { event: "dropped"; count: number }
  | { event: "ended"; reason: string }
  | { event: "failed"; message: string }

export interface LogLine {
  time: string
  pid: string
  tid: string
  level: string
  tag: string
  message: string
}

/** The daemon's error payload, widened with the failures Rust reports. */
export interface DaemonError {
  code: string
  message: string
  detail: string | null
}
