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
