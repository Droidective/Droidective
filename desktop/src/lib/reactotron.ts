/**
 * A Reactotron frame, decoded into the event a timeline row renders.
 *
 * A port of ADBKit's `ReactotronProtocol`, which mirrors
 * `reactotron-core-contract`. Lenient throughout, on purpose: a client sends
 * what it sends, so a missing field gets a default rather than dropping the
 * frame, and an unrecognised `type` becomes `unknown` and still shows up. A
 * timeline that silently omits what it did not expect is worse than useless —
 * it reads as the app having gone quiet.
 *
 * Optional fields are spelled `?: T | undefined` rather than bare `?:` because
 * `exactOptionalPropertyTypes` is on and every one is assigned from a lookup
 * that may find nothing. Same reason `Controls.tsx` does it.
 */

import {
  arrayField,
  compactPreview,
  field,
  isJsonObject,
  numberField,
  stringField,
  type JsonValue,
} from "@/lib/json"
import type { ReactotronCommand } from "@/lib/wire"

export type LogLevel = "debug" | "warn" | "error"

export interface StackFrame {
  fileName: string
  functionName: string
  lineNumber: number | null
  columnNumber: number | null
}

export interface BenchmarkStep {
  title: string
  time: number
  delta: number
}

export interface StateChange {
  path: string
  value: JsonValue
}

export interface CommandArg {
  name: string
  /** In practice always "string"; the contract leaves it open. */
  type: string
}

/**
 * A decoded timeline event. Forward-compatible types land in `unknown`, which
 * is also where the relay's own synthetic notices ride.
 */
export type ReactotronEvent =
  | {
      kind: "clientIntro"
      name: string
      environment?: string | undefined
      platform?: string | undefined
      clientVersion?: string | undefined
    }
  | { kind: "log"; level: LogLevel; message: string; stack: StackFrame[] }
  | {
      kind: "display"
      name: string
      value?: JsonValue | undefined
      preview?: string | undefined
      image?: string | undefined
    }
  | {
      kind: "image"
      uri: string
      preview?: string | undefined
      caption?: string | undefined
      width?: number | undefined
      height?: number | undefined
    }
  | {
      kind: "apiResponse"
      method: string
      url: string
      status: number
      duration: number
      request?: JsonValue | undefined
      response?: JsonValue | undefined
    }
  | { kind: "benchmark"; title: string; steps: BenchmarkStep[] }
  | { kind: "clear" }
  | { kind: "asyncStorage"; action: string; data?: JsonValue | undefined }
  | { kind: "stateAction"; name: string; action?: JsonValue | undefined; ms?: number | undefined }
  | { kind: "stateValuesChange"; changes: StateChange[] }
  | {
      kind: "customCommandRegister"
      id: number
      command: string
      title?: string | undefined
      description?: string | undefined
      args: CommandArg[]
    }
  | { kind: "customCommandUnregister"; id: number; command: string }
  /**
   * A missing path means the client returned the *whole* store in `value` — how
   * a full state tree arrives from MST via `state.values.request`. Otherwise it
   * is the value at that one path.
   */
  | { kind: "stateValuesResponse"; path?: string | undefined; value?: JsonValue | undefined }
  /**
   * With a path, `keys` is the array of key names at that path; with none, the
   * client returned the whole cleaned store in `keys`.
   */
  | { kind: "stateKeysResponse"; path?: string | undefined; keys?: JsonValue | undefined }
  | { kind: "stateBackup"; state?: JsonValue | undefined }
  | { kind: "replKeys"; names: string[] }
  | { kind: "replResult"; value?: JsonValue | undefined }
  | { kind: "unknown"; type: string; payload?: JsonValue | undefined }

/** Longest log message kept for a row. The full value lives in the payload. */
const maxMessageLength = 500

/**
 * Every wire type that becomes something other than `unknown`.
 *
 * A table rather than a switch for the reason `FeatureRegistry` is one: the set
 * of types is the contract, and a table can be asserted against upstream's list
 * in a test. The types deliberately absent — sagas, the devtools and editor
 * pokes, storybook, overlay — are real frames with no typed case, and they show
 * as themselves.
 */
const parsers: Record<string, (payload: JsonValue | undefined) => ReactotronEvent> = {
  "client.intro": (payload) => ({
    kind: "clientIntro",
    name: stringField(payload, "name") ?? "App",
    environment: stringField(payload, "environment"),
    platform: stringField(payload, "platform"),
    clientVersion:
      stringField(payload, "reactotronCoreClientVersion") ??
      stringField(payload, "reactotronVersion"),
  }),
  log: (payload) => ({
    kind: "log",
    level: logLevel(stringField(payload, "level")),
    message: messageText(field(payload, "message")),
    stack: parseStack(field(payload, "stack")),
  }),
  display: (payload) => ({
    kind: "display",
    name: stringField(payload, "name") ?? "Display",
    value: field(payload, "value"),
    preview: stringField(payload, "preview"),
    image: imageUri(field(payload, "image")),
  }),
  image: (payload) => ({
    kind: "image",
    uri: stringField(payload, "uri") ?? "",
    preview: stringField(payload, "preview"),
    caption: stringField(payload, "caption"),
    width: numberField(payload, "width"),
    height: numberField(payload, "height"),
  }),
  "api.response": (payload) => {
    const request = field(payload, "request")
    const response = field(payload, "response")
    return {
      kind: "apiResponse",
      method: (stringField(request, "method") ?? "GET").toUpperCase(),
      url: stringField(request, "url") ?? "",
      status: numberField(response, "status") ?? 0,
      duration: numberField(payload, "duration") ?? 0,
      request,
      response,
    }
  },
  "benchmark.report": (payload) => ({
    kind: "benchmark",
    title: stringField(payload, "title") ?? "Benchmark",
    steps: (arrayField(payload, "steps") ?? []).map((step) => ({
      title: stringField(step, "title") ?? "",
      time: numberField(step, "time") ?? 0,
      delta: numberField(step, "delta") ?? 0,
    })),
  }),
  clear: () => ({ kind: "clear" }),
  "asyncStorage.mutation": (payload) => ({
    kind: "asyncStorage",
    action: stringField(payload, "action") ?? "",
    data: field(payload, "data"),
  }),
  "state.action.complete": (payload) => ({
    kind: "stateAction",
    name: stringField(payload, "name") ?? "(action)",
    action: field(payload, "action"),
    ms: numberField(payload, "ms"),
  }),
  "state.values.change": (payload) => ({
    kind: "stateValuesChange",
    changes: (arrayField(payload, "changes") ?? []).map((change) => ({
      path: stringField(change, "path") ?? "",
      value: field(change, "value") ?? null,
    })),
  }),
  "customCommand.register": (payload) => ({
    kind: "customCommandRegister",
    id: numberField(payload, "id") ?? 0,
    command: stringField(payload, "command") ?? "",
    title: stringField(payload, "title"),
    description: stringField(payload, "description"),
    args: (arrayField(payload, "args") ?? []).map((arg) => ({
      name: stringField(arg, "name") ?? "",
      type: stringField(arg, "type") ?? "string",
    })),
  }),
  "customCommand.unregister": (payload) => ({
    kind: "customCommandUnregister",
    id: numberField(payload, "id") ?? 0,
    command: stringField(payload, "command") ?? "",
  }),
  "state.values.response": (payload) => ({
    kind: "stateValuesResponse",
    path: stringField(payload, "path"),
    value: field(payload, "value"),
  }),
  "state.keys.response": (payload) => ({
    kind: "stateKeysResponse",
    path: stringField(payload, "path"),
    keys: field(payload, "keys"),
  }),
  "state.backup.response": (payload) => ({
    kind: "stateBackup",
    state: field(payload, "state"),
  }),
  "repl.ls.response": (payload) => ({
    kind: "replKeys",
    names: (Array.isArray(payload) ? payload : []).filter(
      (name): name is string => typeof name === "string",
    ),
  }),
  "repl.execute.response": (payload) => ({ kind: "replResult", value: payload }),
}

/** Every wire type this decodes to a typed event — the contract, for tests. */
export const typedCommandTypes: readonly string[] = Object.keys(parsers)

/** Parse a raw frame into a typed timeline event. */
export function parseEvent(command: ReactotronCommand): ReactotronEvent {
  const parse = parsers[command.type]
  if (parse === undefined) return { kind: "unknown", type: command.type, payload: command.payload }
  return parse(command.payload)
}

function logLevel(raw: string | undefined): LogLevel {
  return raw === "warn" || raw === "error" ? raw : "debug"
}

function messageText(value: JsonValue | undefined): string {
  if (value === undefined) return ""
  if (typeof value === "string") return value.slice(0, maxMessageLength)
  // Compact JSON so `console.log(object)` and multi-arg logs preview their
  // content on the collapsed row — like Reactotron's own desktop timeline — and
  // not an opaque element count. Bounded: this costs O(500) however big the
  // logged object is.
  if (Array.isArray(value) || isJsonObject(value)) return compactPreview(value, maxMessageLength)
  return String(value)
}

function imageUri(value: JsonValue | undefined): string | undefined {
  if (value === undefined) return undefined
  if (typeof value === "string") return value
  return stringField(value, "uri")
}

function parseStack(value: JsonValue | undefined): StackFrame[] {
  if (!Array.isArray(value)) return []
  return value.flatMap((frame) => {
    if (isJsonObject(frame)) {
      return [
        {
          fileName: stringField(frame, "fileName") ?? "",
          functionName: stringField(frame, "functionName") ?? "",
          lineNumber: numberField(frame, "lineNumber") ?? null,
          columnNumber: numberField(frame, "columnNumber") ?? null,
        },
      ]
    }
    if (typeof frame === "string") {
      return [{ fileName: frame, functionName: "", lineNumber: null, columnNumber: null }]
    }
    return []
  })
}
