/**
 * The JS Console's two app verbs, as decisions rather than wiring.
 *
 * Both mirror `JSConsoleView` on the Mac: Reload JS asks the runtime first and
 * falls back to the device's own reload keys, and Restart app works out which
 * package is under debug from the target Metro reported.
 */

import type { CdpError } from "@/lib/cdp"
import type { Target } from "@/lib/reactotron-restart"

/** What a `Page.reload` reply means for the caller. */
export type ReloadStep = "done" | "fall-back"

/**
 * Whether the runtime reloaded, or the device has to be asked instead.
 *
 * Hermes does not implement `Page.reload` on every release — it answers
 * method-not-found — and the Mac treats *any* refusal the same way: send the
 * dev menu's double-R through adb, which is what `react-native` itself does.
 * So this is deliberately not a check for one error code. A reply that never
 * came is a refusal too: the caller cannot tell a silent runtime from a
 * missing one, and leaving the bundle unreloaded is the worse answer.
 */
export function reloadStep(error: CdpError | null): ReloadStep {
  return error === null ? "done" : "fall-back"
}

/**
 * What to say once a reload has been asked for.
 *
 * The fallback is named rather than hidden: it goes through the device's key
 * events, so it only reaches an app that is in front, and someone whose app was
 * backgrounded needs to know that is why nothing happened.
 */
export function reloadMessage(step: ReloadStep, viaDevice: { ok: boolean } | null): string {
  if (step === "done") return "Reloading the JS bundle…"
  if (viaDevice === null) return "Reload failed — the runtime didn't accept Page.reload."
  return viaDevice.ok
    ? "The runtime refused Page.reload — sent the reload keys to the device instead."
    : "Reload failed — the runtime refused it and the device didn't take the reload keys."
}

/**
 * Which package to restart.
 *
 * Metro reports the application id for the target being debugged, which names
 * the exact app rather than guessing at one — so unlike Reactotron's path there
 * is no name to match against the installed list. With nothing connected there
 * is no appId, and the Mac opens its installed-apps picker; there is none here
 * yet, so this asks instead of restarting whatever happens to be in front.
 */
export function consoleRestartTarget(appId: string | null): Target {
  const trimmed = appId?.trim() ?? ""
  if (trimmed === "") return { kind: "ask", reason: "no-client" }
  return { kind: "package", packageId: trimmed }
}
