/**
 * The REPL screen's decisions.
 *
 * Its own module rather than more of `reactotron-state.ts`: three screens now
 * speak this protocol and one file holding all of them went past the line
 * budget. They share `Outgoing` and nothing else.
 */
import type { Outgoing } from "@/lib/reactotron-state"

/**
 * List what the app registered with `Reactotron.repl(name, value)`.
 *
 * Sent when the screen opens, not just on Refresh: an empty expression box with
 * no list of names is a prompt with nothing to type into it.
 */
export function listReplNames(): Outgoing {
  return { kind: "repl.ls", payload: null }
}

/**
 * Evaluate an expression.
 *
 * The payload is the bare string, not an object — `repl.execute` is the one
 * state command whose payload is not a wrapper, and sending `{ code }` gets
 * silently evaluated as nothing.
 */
export function evaluate(code: string): Outgoing {
  return { kind: "repl.execute", payload: code.trim() }
}

/** What a REPL reply means. */
export type ReplEvent = { kind: "names"; names: string[] } | { kind: "result"; text: string } | null

export function readReplEvent(type: string, payload: unknown): ReplEvent {
  if (type === "repl.ls.response") {
    if (!Array.isArray(payload)) return null
    return { kind: "names", names: payload.filter((name) => typeof name === "string") }
  }
  if (type === "repl.execute.response") {
    // `undefined` is a real answer — an expression that returned nothing ran
    // just as much as one that returned a value, and a blank result panel
    // cannot tell you which happened.
    return {
      kind: "result",
      text: payload === undefined || payload === null ? "undefined" : JSON.stringify(payload, null, 2),
    }
  }
  return null
}
