/**
 * Chrome DevTools Protocol framing for the JS console.
 *
 * A port of ADBKit's `CDPProtocol`, param for param. The params are not
 * decoration: `replMode` is what lets someone re-declare a `let` at the prompt,
 * `generatePreview` is what makes the common log line render without a second
 * round trip, and `objectGroup: "console"` is what lets Clear release every
 * handle at once instead of leaking them into the app's heap.
 */

/** A CDP `Runtime.RemoteObject` — a value, or a handle to one. */
export interface RemoteObject {
  type: string
  subtype?: string
  className?: string
  value?: unknown
  unserializableValue?: string
  description?: string
  objectId?: string
  preview?: ObjectPreview
}

export interface ObjectPreview {
  type: string
  subtype?: string
  description?: string
  overflow: boolean
  properties: PropertyPreview[]
}

export interface PropertyPreview {
  name: string
  type: string
  subtype?: string
  value?: string
}

/** One `Runtime.consoleAPICalled` event. */
export interface ConsoleApiCall {
  type: string
  args: RemoteObject[]
  timestamp: number
  stackTrace?: StackTrace
}

export interface StackTrace {
  callFrames: CallFrame[]
}

export interface CallFrame {
  functionName: string
  url: string
  lineNumber: number
  columnNumber: number
}

export interface ExceptionDetails {
  text: string
  exception?: RemoteObject
  stackTrace?: StackTrace
  lineNumber?: number
  columnNumber?: number
  url?: string
}

/** A protocol-level error — not a JavaScript exception, which rides a reply. */
export interface CdpError {
  code: number
  message: string
}

export type Incoming =
  | { kind: "response"; id: number; result: unknown; error: CdpError | null }
  | { kind: "event"; method: string; params: Record<string, unknown> }

function asRecord(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null
}

/** `{ id, method, params }`. */
export function request(id: number, method: string, params: Record<string, unknown>): string {
  return JSON.stringify({ id, method, params })
}

/**
 * REPL-flavoured `Runtime.evaluate` params.
 *
 * `replMode` allows `let` re-declaration and top-level `await`;
 * `includeCommandLineAPI` exposes `$_` and friends; `generatePreview` returns
 * inline previews so a logged object renders without a follow-up
 * `getProperties`; the result stays in the `console` group rather than being
 * returned by value, so it can be expanded lazily and released all at once.
 */
export function evaluateParams(expression: string): Record<string, unknown> {
  return {
    expression,
    objectGroup: "console",
    includeCommandLineAPI: true,
    replMode: true,
    generatePreview: true,
    userGesture: true,
    awaitPromise: true,
    returnByValue: false,
  }
}

/**
 * Keepalive params: a no-op expression, `silent` so it can never surface an
 * exception event, and `returnByValue` so the runtime never retains a handle
 * for the result.
 */
export function keepaliveParams(): Record<string, unknown> {
  return {
    expression: "void 0",
    silent: true,
    returnByValue: true,
    generatePreview: false,
  }
}

export function getPropertiesParams(objectId: string): Record<string, unknown> {
  return {
    objectId,
    ownProperties: true,
    accessorPropertiesOnly: false,
    generatePreview: true,
  }
}

export function releaseObjectGroupParams(group: string): Record<string, unknown> {
  return { objectGroup: group }
}

/** Decode one inbound frame. Returns null for anything that is neither. */
export function parseIncoming(text: string): Incoming | null {
  let root: unknown
  try {
    root = JSON.parse(text)
  } catch {
    return null
  }
  const record = asRecord(root)
  if (record === null) return null
  if (typeof record["id"] === "number") {
    return {
      kind: "response",
      id: record["id"],
      result: record["result"] ?? null,
      error: parseError(record["error"]),
    }
  }
  if (typeof record["method"] === "string") {
    return {
      kind: "event",
      method: record["method"],
      params: asRecord(record["params"]) ?? {},
    }
  }
  return null
}

function parseError(value: unknown): CdpError | null {
  const record = asRecord(value)
  if (record === null) return null
  const message = record["message"]
  if (typeof message !== "string") return null
  const code = record["code"]
  return { code: typeof code === "number" ? code : 0, message }
}

/** The domains the console needs enabled, in the order Chrome enables them. */
export const ENABLE_METHODS = ["Runtime.enable", "Log.enable"] as const

export function parseConsoleCall(params: Record<string, unknown>): ConsoleApiCall | null {
  const type = params["type"]
  if (typeof type !== "string") return null
  const rawArgs = params["args"]
  const args = Array.isArray(rawArgs)
    ? rawArgs.map((one) => asRemoteObject(one)).filter((one): one is RemoteObject => one !== null)
    : []
  const timestamp = params["timestamp"]
  return {
    type,
    args,
    timestamp: typeof timestamp === "number" ? timestamp : 0,
    ...(parseStackTrace(params["stackTrace"]) === null
      ? {}
      : { stackTrace: parseStackTrace(params["stackTrace"]) as StackTrace }),
  }
}

export function asRemoteObject(value: unknown): RemoteObject | null {
  const record = asRecord(value)
  if (record === null) return null
  const type = record["type"]
  if (typeof type !== "string") return null
  const object: RemoteObject = { type }
  if (typeof record["subtype"] === "string") object.subtype = record["subtype"]
  if (typeof record["className"] === "string") object.className = record["className"]
  if (typeof record["description"] === "string") object.description = record["description"]
  if (typeof record["objectId"] === "string") object.objectId = record["objectId"]
  if (typeof record["unserializableValue"] === "string") {
    object.unserializableValue = record["unserializableValue"]
  }
  if ("value" in record) object.value = record["value"]
  const preview = parsePreview(record["preview"])
  if (preview !== null) object.preview = preview
  return object
}

function parsePreview(value: unknown): ObjectPreview | null {
  const record = asRecord(value)
  if (record === null) return null
  const type = record["type"]
  if (typeof type !== "string") return null
  const rawProperties = record["properties"]
  const properties: PropertyPreview[] = Array.isArray(rawProperties)
    ? rawProperties.flatMap((one) => {
        const entry = asRecord(one)
        if (entry === null) return []
        const name = entry["name"]
        const propertyType = entry["type"]
        if (typeof name !== "string" || typeof propertyType !== "string") return []
        const property: PropertyPreview = { name, type: propertyType }
        if (typeof entry["subtype"] === "string") property.subtype = entry["subtype"]
        if (typeof entry["value"] === "string") property.value = entry["value"]
        return [property]
      })
    : []
  const preview: ObjectPreview = {
    type,
    overflow: record["overflow"] === true,
    properties,
  }
  if (typeof record["subtype"] === "string") preview.subtype = record["subtype"]
  if (typeof record["description"] === "string") preview.description = record["description"]
  return preview
}

export function parseStackTrace(value: unknown): StackTrace | null {
  const record = asRecord(value)
  if (record === null) return null
  const frames = record["callFrames"]
  if (!Array.isArray(frames)) return null
  const callFrames: CallFrame[] = frames.flatMap((one) => {
    const frame = asRecord(one)
    if (frame === null) return []
    const url = frame["url"]
    if (typeof url !== "string") return []
    return [
      {
        functionName: typeof frame["functionName"] === "string" ? frame["functionName"] : "",
        url,
        lineNumber: typeof frame["lineNumber"] === "number" ? frame["lineNumber"] : 0,
        columnNumber: typeof frame["columnNumber"] === "number" ? frame["columnNumber"] : 0,
      },
    ]
  })
  return { callFrames }
}

export function parseExceptionDetails(value: unknown): ExceptionDetails | null {
  const record = asRecord(value)
  if (record === null) return null
  const text = record["text"]
  if (typeof text !== "string") return null
  const details: ExceptionDetails = { text }
  const exception = asRemoteObject(record["exception"])
  if (exception !== null) details.exception = exception
  const stack = parseStackTrace(record["stackTrace"])
  if (stack !== null) details.stackTrace = stack
  if (typeof record["url"] === "string") details.url = record["url"]
  if (typeof record["lineNumber"] === "number") details.lineNumber = record["lineNumber"]
  if (typeof record["columnNumber"] === "number") details.columnNumber = record["columnNumber"]
  return details
}

/**
 * A stack frame's script name, as the source label shows it.
 *
 * The last path component without its query — a Metro bundle URL carries a
 * cache-busting query that would otherwise be most of the label.
 */
export function scriptName(url: string): string {
  if (url === "") return ""
  const withoutQuery = url.split("?")[0] ?? url
  const last = withoutQuery.split("/").pop() ?? withoutQuery
  return last === "" ? withoutQuery : last
}
