import { useCallback, useEffect, useRef, useState } from "react"

import { getPropertiesParams, keepaliveParams, releaseObjectGroupParams } from "@/lib/cdp"
import {
  awaitReply,
  findTargets,
  namedValues,
  openSocket,
  runEvaluate,
  sendOn,
  type Connection,
  type NamedValue,
  type Wiring,
} from "@/lib/cdp-session"
import { appended, localRow, type ConsoleRow } from "@/lib/console-feed"
import type { CdpTarget } from "@/lib/metro"

export interface JsConsole {
  rows: ConsoleRow[]
  targets: CdpTarget[]
  target: CdpTarget | null
  connection: Connection
  problem: string | null
  connect: (target: CdpTarget) => void
  refresh: () => void
  clear: () => void
  evaluate: (expression: string) => void
  expand: (objectId: string) => Promise<NamedValue[]>
}

/**
 * How often to poke the connection.
 *
 * The React Native debugger proxy drops a socket it decides is idle, and a
 * console watching a quiet app is exactly that. `void 0` is the cheapest
 * expression that proves the runtime is still answering.
 */
const KEEPALIVE_MS = 20_000

/** Metro's default port. */
export const DEFAULT_METRO_PORT = 8081

/**
 * A Hermes CDP console, over a WebSocket this webview owns.
 *
 * **The socket is here rather than in the daemon on purpose.**
 * `URLSessionWebSocketTask` compiles off-Darwin and then fails at runtime
 * ("WebSockets not supported by libcurl"), so the daemon would need a NIO
 * client written from scratch to hold a CDP connection. Metro runs on this
 * machine, and both WebKitGTK and WebView2 ship a real WebSocket — so there is
 * nothing to write, and nothing to behave differently per platform.
 */
export function useJsConsole(port: number): JsConsole {
  const [rows, setRows] = useState<ConsoleRow[]>([])
  const [targets, setTargets] = useState<CdpTarget[]>([])
  const [target, setTarget] = useState<CdpTarget | null>(null)
  const [connection, setConnection] = useState<Connection>("idle")
  const [problem, setProblem] = useState<string | null>(null)

  const socket = useRef<WebSocket | null>(null)
  const detach = useRef<AbortController | null>(null)
  const nextId = useRef(1)
  const nextRow = useRef(1)
  // id → whoever is waiting on that reply. A CDP reply carries only the id, so
  // this map is the entire correlation mechanism.
  const pending = useRef(new Map<number, (result: unknown) => void>())

  const addRows = useCallback((incoming: ConsoleRow[]) => {
    if (incoming.length > 0) setRows((current) => appended(current, incoming))
  }, [])

  const send = useCallback(
    (method: string, params: Record<string, unknown>) =>
      sendOn(socket.current, nextId, method, params),
    [],
  )

  const call = useCallback(
    (method: string, params: Record<string, unknown>) =>
      awaitReply(send(method, params), pending.current),
    [send],
  )

  const wiring: Wiring = {
    socket,
    detach,
    pending,
    nextRow,
    addRows,
    setConnection,
    setProblem,
    send,
  }

  const refresh = useCallback(() => {
    setProblem(null)
    setConnection((current) => (current === "connected" ? current : "searching"))
    void findTargets(port, setTargets, setConnection, setProblem)
  }, [port])

  const connect = useCallback(
    (chosen: CdpTarget) => {
      setTarget(chosen)
      openSocket(chosen, wiring)
    },
    // `wiring` is rebuilt each render out of refs and stable callbacks, so the
    // identity churn means nothing here.
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [addRows, send],
  )

  // Keepalive, only while there is something to keep alive.
  useEffect(() => {
    if (connection !== "connected") return
    const timer = setInterval(() => send("Runtime.evaluate", keepaliveParams()), KEEPALIVE_MS)
    return () => clearInterval(timer)
  }, [connection, send])

  // Close on unmount, not whenever React feels like it.
  useEffect(
    () => () => {
      detach.current?.abort()
      socket.current?.close()
      socket.current = null
    },
    [],
  )

  return {
    rows,
    targets,
    target,
    connection,
    problem,
    connect,
    refresh,
    clear: () => {
      setRows([])
      // Release the handles too: every logged object stays alive in the app's
      // heap until its group is released, so a console nobody clears is a slow
      // leak in *their* app.
      send("Runtime.releaseObjectGroup", releaseObjectGroupParams("console"))
    },
    evaluate: (expression) => echoAndRun(expression, call, nextRow, addRows),
    expand: async (objectId) =>
      namedValues(await call("Runtime.getProperties", getPropertiesParams(objectId))),
  }
}

/** Echo what was typed, then run it — the prompt's own row comes first. */
function echoAndRun(
  expression: string,
  call: (method: string, params: Record<string, unknown>) => Promise<unknown>,
  nextRow: React.RefObject<number>,
  addRows: (rows: ConsoleRow[]) => void,
): void {
  const trimmed = expression.trim()
  if (trimmed === "") return
  nextRow.current += 1
  addRows([localRow(nextRow.current, "info", `\u203A ${trimmed}`, Date.now())])
  void runEvaluate(trimmed, call, nextRow, addRows)
}

export type { Connection, NamedValue }
