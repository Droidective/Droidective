import { isJsonObject, type JsonObject, type JsonValue } from "@/lib/json"

/**
 * The State screen's decisions — what to send, and what an arriving command
 * means for what is on screen.
 *
 * Reactotron's state protocol is request/response over one socket with no
 * correlation id: a `state.values.request` is answered by a
 * `state.values.response` that lands on the timeline like any other event. So
 * the pane sends, then watches the feed. Everything about *which* event answers
 * *which* question lives here, where it can be tested without a device.
 */

/** A path being watched, and the last value seen for it. */
export interface Watch {
  path: string
  value: JsonValue | undefined
  /** When the value last changed, for the row's timestamp. */
  at: number | null
}

export interface Snapshot {
  id: string
  takenAt: number
  state: JsonValue
}

/** A command to put on the wire: `{ kind, payload }`, as the Rust side takes. */
export interface Outgoing {
  kind: string
  payload: JsonValue
}

/**
 * Pull the whole store.
 *
 * Two commands, not one, and that is upstream's shape rather than belt and
 * braces: `reactotron-redux` answers `state.backup.request`, while a
 * `state.values.request` with no path comes back as a `state.keys.response`
 * (redux) or a `state.values.response` (mst). Ask for both and take whichever
 * arrives — the Mac's `loadStateTree` does exactly this.
 */
export function loadStateTree(): Outgoing[] {
  return [
    { kind: "state.values.request", payload: {} },
    { kind: "state.backup.request", payload: {} },
  ]
}

/** Freeze the store as it is now. */
export function takeSnapshot(): Outgoing {
  return { kind: "state.backup.request", payload: {} }
}

export function restoreSnapshot(state: JsonValue): Outgoing {
  return { kind: "state.restore.request", payload: { state } }
}

/**
 * The whole watch list, every time.
 *
 * `state.values.subscribe` replaces the client's set rather than adding to it,
 * so sending one new path would silently stop watching the others.
 */
export function subscribeTo(paths: readonly string[]): Outgoing {
  return { kind: "state.values.subscribe", payload: { paths: [...paths] } }
}

/**
 * Add a path, or refuse it.
 *
 * Returns the new list, or null when there is nothing to do — blank, or already
 * watched. Null rather than the unchanged list so the caller can tell "no
 * change" from "changed to the same thing" and skip the round trip.
 */
export function withWatch(paths: readonly string[], raw: string): string[] | null {
  const path = raw.trim()
  if (path === "" || paths.includes(path)) return null
  return [...paths, path]
}

export function withoutWatch(paths: readonly string[], path: string): string[] {
  return paths.filter((existing) => existing !== path)
}

/** What a dispatch box holds must be an action object, not any JSON. */
export type ParsedAction = { ok: true; action: JsonValue } | { ok: false; reason: string }

/**
 * Parse the dispatch box.
 *
 * A Redux action is an object with a `type`; a bare string or array would be
 * accepted by `JSON.parse` and then rejected by the store, at which point the
 * failure is a red screen in the app rather than a line in this pane.
 */
export function parseAction(text: string): ParsedAction {
  const trimmed = text.trim()
  if (trimmed === "") return { ok: false, reason: "Enter an action first." }
  let parsed: unknown
  try {
    parsed = JSON.parse(trimmed)
  } catch {
    return { ok: false, reason: "Invalid action JSON" }
  }
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    return { ok: false, reason: "An action must be a JSON object, e.g. { \"type\": \"INCREMENT\" }" }
  }
  if (!("type" in parsed)) {
    return { ok: false, reason: "An action needs a \"type\"." }
  }
  return { ok: true, action: parsed as JsonValue }
}

export function dispatchAction(action: JsonValue): Outgoing {
  return { kind: "state.action.dispatch", payload: { action } }
}

/**
 * What an arriving command means for the State screen.
 *
 * The timeline carries everything; this picks out the four replies that answer
 * something this pane asked, and says nothing about the rest.
 */
export type StateEvent =
  | { kind: "tree"; state: JsonValue }
  | { kind: "backup"; state: JsonValue }
  | { kind: "values"; changes: { path: string; value: JsonValue }[] }
  | null

export function readStateEvent(type: string, payload: unknown): StateEvent {
  const body = asObject(payload)
  if (body === null) return null

  // redux answers a pathless request with keys, mst with values; both carry the
  // whole store under `value`.
  if (type === "state.keys.response" || type === "state.values.response") {
    const value = body["value"]
    if (value === undefined) return null
    // A *subscription* update also arrives as `state.values.change`; a response
    // with no path is the whole tree.
    return { kind: "tree", state: value }
  }
  if (type === "state.backup.response") {
    const state = body["state"] ?? body["value"]
    if (state === undefined) return null
    return { kind: "backup", state }
  }
  if (type === "state.values.change") {
    const changes = body["changes"]
    if (!Array.isArray(changes)) return null
    const read: { path: string; value: JsonValue }[] = []
    for (const entry of changes) {
      const row = asObject(entry)
      const path = row?.["path"]
      if (typeof path === "string") read.push({ path, value: row?.["value"] ?? null })
    }
    return read.length === 0 ? null : { kind: "values", changes: read }
  }
  return null
}

/** Fold a `state.values.change` into the watch list, leaving order alone. */
export function applyChanges(
  watches: readonly Watch[],
  changes: readonly { path: string; value: JsonValue }[],
  at: number,
): Watch[] {
  const byPath = new Map(changes.map((change) => [change.path, change.value]))
  return watches.map((watch) =>
    byPath.has(watch.path) ? { path: watch.path, value: byPath.get(watch.path), at } : watch,
  )
}

/**
 * A payload as an object, or nothing.
 *
 * Takes `unknown` because a payload off the wire is exactly that, and hands
 * back the codebase's `JsonObject` so the values read out of it are already
 * `JsonValue` rather than needing a cast at each use.
 */
function asObject(value: unknown): JsonObject | null {
  const json = value as JsonValue
  return isJsonObject(json) ? json : null
}

// MARK: - REPL

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
