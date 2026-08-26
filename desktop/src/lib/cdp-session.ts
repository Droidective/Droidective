/**
 * The CDP session's moving parts: the socket, the reply correlation, and the
 * events that become rows.
 *
 * Split out of `useJsConsole` because none of it is React — it is the transport
 * the webview happens to own, and keeping it here is what lets the hook stay
 * about state.
 */

import {
  asRemoteObject,
  ENABLE_METHODS,
  evaluateParams,
  parseConsoleCall,
  parseExceptionDetails,
  parseIncoming,
  request,
  type RemoteObject,
} from "@/lib/cdp"
import { rowFromCall, rowFromException, type ConsoleRow } from "@/lib/console-feed"
import { isLocalDebuggerUrl, parseTargets, targetsUrl, type CdpTarget } from "@/lib/metro"

export type Connection = "idle" | "searching" | "connecting" | "connected" | "failed"

/** A property of an expanded object — its name, and the value under it. */
export interface NamedValue {
  name: string
  value: RemoteObject
}

/** How long to wait for a reply before giving the caller nothing. */
const REPLY_TIMEOUT_MS = 10_000

/** Everything one live socket needs to reach. */
export interface Wiring {
  socket: React.RefObject<WebSocket | null>
  /** Aborting it detaches every handler — a closing socket must not report. */
  detach: React.RefObject<AbortController | null>
  pending: React.RefObject<Map<number, (result: unknown) => void>>
  nextRow: React.RefObject<number>
  addRows: (rows: ConsoleRow[]) => void
  setConnection: (connection: Connection) => void
  setProblem: (problem: string | null) => void
  send: (method: string, params: Record<string, unknown>) => number | null
}

export function sendOn(
  socket: WebSocket | null,
  nextId: React.RefObject<number>,
  method: string,
  params: Record<string, unknown>,
): number | null {
  if (socket === null || socket.readyState !== WebSocket.OPEN) return null
  const id = nextId.current
  nextId.current += 1
  socket.send(request(id, method, params))
  return id
}

/** Wait for one reply, or give up rather than holding the promise forever. */
export function awaitReply(
  id: number | null,
  pending: Map<number, (result: unknown) => void>,
): Promise<unknown> {
  if (id === null) return Promise.resolve(null)
  return new Promise((resolve) => {
    pending.set(id, resolve)
    setTimeout(() => {
      if (pending.delete(id)) resolve(null)
    }, REPLY_TIMEOUT_MS)
  })
}

export async function findTargets(
  port: number,
  setTargets: (targets: CdpTarget[]) => void,
  setConnection: (update: (current: Connection) => Connection) => void,
  setProblem: (problem: string | null) => void,
): Promise<void> {
  const settle = (connection: Connection) => {
    setConnection((current) => (current === "connected" ? current : connection))
  }
  try {
    const response = await fetch(targetsUrl(port))
    const found = parseTargets(await response.json())
    setTargets(found)
    if (found.length === 0) {
      settle("idle")
      setProblem("Metro is running, but no app has connected to it yet.")
    }
  } catch {
    setTargets([])
    settle("idle")
    setProblem(`Nothing is answering on port ${String(port)}. Is Metro running?`)
  }
}

/** Open a CDP socket to one target and wire its events. */
export function openSocket(chosen: CdpTarget, wiring: Wiring): void {
  // Loopback only. This webview opens the socket, so a target list served by a
  // rogue process on the Metro port must not be able to point it elsewhere.
  if (!isLocalDebuggerUrl(chosen.webSocketDebuggerUrl)) {
    wiring.setProblem("That target's debugger socket is not on this machine.")
    wiring.setConnection("failed")
    return
  }
  wiring.detach.current?.abort()
  wiring.socket.current?.close()
  wiring.pending.current.clear()
  wiring.setConnection("connecting")
  wiring.setProblem(null)

  const live = new WebSocket(chosen.webSocketDebuggerUrl)
  const controller = new AbortController()
  const { signal } = controller
  wiring.socket.current = live
  wiring.detach.current = controller

  live.addEventListener(
    "open",
    () => {
      wiring.setConnection("connected")
      for (const method of ENABLE_METHODS) wiring.send(method, {})
    },
    { signal },
  )
  live.addEventListener("error", () => wiring.setProblem("The debugger socket failed."), { signal })
  live.addEventListener(
    "close",
    () => {
      wiring.socket.current = null
      wiring.setConnection("failed")
      wiring.setProblem("The debugger disconnected. Reload the app, or reconnect.")
    },
    { signal },
  )
  live.addEventListener(
    "message",
    (event: MessageEvent<unknown>) => {
      if (typeof event.data !== "string") return
      handleFrame(event.data, wiring)
    },
    { signal },
  )
}

function handleFrame(text: string, wiring: Wiring): void {
  const frame = parseIncoming(text)
  if (frame === null) return
  if (frame.kind === "response") {
    const waiting = wiring.pending.current.get(frame.id)
    if (waiting !== undefined) {
      wiring.pending.current.delete(frame.id)
      waiting(frame.result)
    }
    return
  }
  wiring.addRows(rowsFor(frame.method, frame.params, wiring.nextRow))
}

export async function runEvaluate(
  expression: string,
  call: (method: string, params: Record<string, unknown>) => Promise<unknown>,
  nextRow: React.RefObject<number>,
  addRows: (rows: ConsoleRow[]) => void,
): Promise<void> {
  const result = await call("Runtime.evaluate", evaluateParams(expression))
  const record = asRecord(result)
  nextRow.current += 1
  const details = parseExceptionDetails(record?.["exceptionDetails"])
  if (details !== null) {
    addRows([rowFromException(nextRow.current, details, Date.now())])
    return
  }
  const value = asRemoteObject(record?.["result"])
  if (value === null) return
  addRows([
    {
      ...rowFromCall(nextRow.current, { type: "log", args: [value], timestamp: Date.now() }),
      local: true,
    },
  ])
}

/** A `Runtime.getProperties` reply as name/value pairs. */
export function namedValues(result: unknown): NamedValue[] {
  const list = asRecord(result)?.["result"]
  if (!Array.isArray(list)) return []
  return list.flatMap((entry) => {
    const row = asRecord(entry)
    if (row === null) return []
    const value = asRemoteObject(row["value"])
    if (value === null) return []
    return [{ name: typeof row["name"] === "string" ? row["name"] : "", value }]
  })
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null
}

/** The rows one CDP event produces, if any. */
function rowsFor(
  method: string,
  params: Record<string, unknown>,
  counter: React.RefObject<number>,
): ConsoleRow[] {
  if (method === "Runtime.consoleAPICalled") {
    const call = parseConsoleCall(params)
    if (call === null) return []
    counter.current += 1
    return [rowFromCall(counter.current, call)]
  }
  if (method === "Runtime.exceptionThrown") {
    const details = parseExceptionDetails(params["exceptionDetails"])
    if (details === null) return []
    counter.current += 1
    const timestamp = params["timestamp"]
    return [
      rowFromException(
        counter.current,
        details,
        typeof timestamp === "number" ? timestamp : Date.now(),
      ),
    ]
  }
  return []
}
