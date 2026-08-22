/**
 * Which devices an action runs on — ported from `AppState.targetSerials` and
 * its two guards.
 *
 * The subtlety worth keeping is `effectiveRunOnAll`: the toggle being on is not
 * enough, the *focused feature* has to support fanning out. Without that, a
 * toggle left on from Send Text would silently fan the next thing out too, and
 * "the next thing" might be a pull that writes every device's file to one path.
 */

import type { Device, FeatureSummary } from "@/lib/wire"

/** A device adb will actually talk to. */
export function isReady(device: Device): boolean {
  return device.state === "device"
}

export function readyDevices(devices: readonly Device[]): Device[] {
  return devices.filter((device) => isReady(device))
}

/**
 * Whether the focused feature offers running on every device.
 *
 * The registry's answer, over the wire. Null — no feature focused — is false:
 * Home is not something to fan out.
 */
export function supportsRunAll(feature: FeatureSummary | null): boolean {
  return feature?.supportsRunAll ?? false
}

/**
 * Run-on-all actually in effect.
 *
 * Gating here rather than on the raw toggle is what stops a toggle left on from
 * a supported feature from reaching a single-device one.
 */
export function effectiveRunOnAll(runOnAll: boolean, feature: FeatureSummary | null): boolean {
  return runOnAll && supportsRunAll(feature)
}

/**
 * Whether the toggle is worth showing at all — the Mac's
 * `readyDeviceCount > 1 && activeFeatureSupportsRunAll`. One device is not a
 * fan-out, so offering the choice would be offering nothing.
 */
export function showsRunAll(
  devices: readonly Device[],
  feature: FeatureSummary | null,
): boolean {
  return readyDevices(devices).length > 1 && supportsRunAll(feature)
}

/**
 * The serials an action should run on, selected device first.
 *
 * First because a fan-out reports per device and the one on the bar is the one
 * the person is looking at — `AppState.targetSerials` swaps it to the front for
 * exactly that reason. With run-on-all off it is the only target, and an
 * unready selection is no target at all rather than a call adb will refuse.
 */
export function targetSerials(
  devices: readonly Device[],
  selected: Device | null,
  runAll: boolean,
): string[] {
  const ready = readyDevices(devices)
  const chosen = selected !== null && isReady(selected) ? selected : null
  if (!runAll) return chosen === null ? [] : [chosen.serial]
  const serials = ready.map((device) => device.serial)
  if (chosen === null) return serials
  return [chosen.serial, ...serials.filter((serial) => serial !== chosen.serial)]
}

/** One device's outcome in a fan-out. */
export interface Outcome {
  serial: string
  ok: boolean
  message: string
}

/**
 * How a fan-out reads as one line.
 *
 * One target keeps its own message untouched — that is the single-device case
 * and it must not grow a summary it never had. Several become a count, because
 * five toasts for one keypress is not a report.
 */
export function summarise(outcomes: readonly Outcome[]): { ok: boolean; message: string } {
  if (outcomes.length === 0) return { ok: false, message: "No device connected." }
  const [only] = outcomes
  if (outcomes.length === 1 && only !== undefined) {
    return { ok: only.ok, message: only.message }
  }
  const failed = outcomes.filter((outcome) => !outcome.ok)
  if (failed.length === 0) {
    return { ok: true, message: `Ran on ${String(outcomes.length)} devices` }
  }
  // Naming the failures rather than counting them: "2 of 5 failed" sends
  // someone hunting for which two.
  const names = failed.map((outcome) => outcome.serial).join(", ")
  return {
    ok: false,
    message: `Ran on ${String(outcomes.length - failed.length)} of ${String(outcomes.length)} — failed on ${names}`,
  }
}
