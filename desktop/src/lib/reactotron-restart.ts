/**
 * What "Restart app" does, decided without touching a device.
 *
 * The Mac's `RestartAppMenu` mixes three things: which app to restart, what to
 * wipe first, and what to say afterwards. Only the middle one is obvious, so
 * the other two live here as pure functions — the target chain is the part that
 * can go wrong in a way that matters (clearing the data of an app nobody asked
 * about), and the wording is the part that has to stay honest when a step
 * fails.
 */

import { matchAppName } from "@/lib/app-name-match"

/**
 * What a restart wipes first: the app's cache (`pm clear --cache-only` — safe,
 * keeps you signed in) or its whole data (`pm clear` — signs you out and wipes
 * local storage, so it always sits behind a confirmation). Null restarts
 * without wiping anything.
 */
export type ClearScope = "cache" | "data" | null

/** The adb-side verb for a scope, as `controlApp` names it. */
export function clearAction(scope: Exclude<ClearScope, null>): "clearCache" | "clearData" {
  return scope === "cache" ? "clearCache" : "clearData"
}

/**
 * `pm clear --cache-only` never returns on some images — observed live on the
 * API 36 emulator — so the cache clear gets a bounded window. A full data clear
 * needs none: `pm clear` returns reliably.
 */
export const CACHE_CLEAR_TIMEOUT_MS = 10_000

export interface TargetInputs {
  /** What the connected Reactotron client called itself, when one is connected. */
  clientName: string | null
  installed: readonly string[]
  /** The frontmost package, when the device named one. */
  foreground: string | null
}

export type Target =
  | { kind: "package"; packageId: string }
  /** Nothing trustworthy to guess at — the caller has to ask. */
  | { kind: "ask"; reason: "no-client" | "no-match" }

/**
 * Which app to restart.
 *
 * The client's own name first, because it is the only signal that names the
 * app that is actually talking to us. The foreground app second, and only when
 * it is something installed — never the launcher, and never a package the
 * device reported but we cannot see. With no client connected there is nothing
 * trustworthy at all: the foreground app could be anything, so ask straight
 * away rather than restarting whatever happens to be open.
 */
export function restartTarget(inputs: TargetInputs): Target {
  if (inputs.clientName === null || inputs.clientName.trim() === "") {
    return { kind: "ask", reason: "no-client" }
  }
  const matched = matchAppName(inputs.clientName, inputs.installed)
  if (matched !== null) return { kind: "package", packageId: matched }
  if (inputs.foreground !== null && inputs.installed.includes(inputs.foreground)) {
    return { kind: "package", packageId: inputs.foreground }
  }
  return { kind: "ask", reason: "no-match" }
}

/**
 * What to say once the relaunch is under way.
 *
 * A failed clear is reported rather than fatal — the restart proceeds either
 * way, and someone who asked for a clean start deserves to know they did not
 * get one instead of being told nothing.
 */
export function restartMessage(args: {
  packageId: string
  scope: ClearScope
  cleared: boolean
}): string {
  if (args.scope === null) return `Restarting ${args.packageId}…`
  if (args.scope === "cache") {
    return args.cleared
      ? `Cleared cache — restarting ${args.packageId}…`
      : `Cache clear didn't finish — restarting ${args.packageId}…`
  }
  return args.cleared
    ? `Cleared data — restarting ${args.packageId}…`
    : `Data clear failed — restarting ${args.packageId}…`
}

/**
 * What to say when the target could not be established.
 *
 * Names the way out rather than just the problem: the Apps screen restarts any
 * package, so "we could not guess" is only half an answer.
 */
export function askMessage(reason: "no-client" | "no-match", clientName: string | null): string {
  if (reason === "no-client") {
    return "Connect your app first, or restart it from the Apps screen."
  }
  const named = clientName === null || clientName.trim() === "" ? "the connected app" : `"${clientName}"`
  return `Couldn't tell which package ${named} is — restart it from the Apps screen.`
}

/** The sentence the clear-data confirmation asks, as the Mac words it. */
export const CLEAR_DATA_PROMPT =
  "Clear all data for the app and restart? This signs you out and wipes local storage."
