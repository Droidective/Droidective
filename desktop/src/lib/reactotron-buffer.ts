/**
 * The timeline's backing store: a ring of rows bounded by count *and* bytes,
 * and the reduction of relay frames into it.
 *
 * Pure and immutable, so the trimming, the clear scoping and the client
 * bookkeeping are all tested without a socket or a rendered list — the same
 * reason ADBKit keeps its parsers static, and the only kind of test this app can
 * run at all.
 *
 * `ReactotronTimeline`'s caps come across unchanged, including the reason for
 * the second one: a React Native client streams frames of arbitrary size (api
 * response bodies, base64 display images, whole state trees), so a count cap
 * alone still lets the retained timeline reach gigabytes.
 */

import { parseEvent, type ReactotronEvent } from "@/lib/reactotron"
import { makeRow, type TimelineRow } from "@/lib/reactotron-rows"
import type { ReactotronCommand, ReactotronFrame } from "@/lib/wire"

/** Most rows the timeline retains. */
export const MAX_ROWS = 2000
/**
 * Most cumulative wire bytes it retains. The retained JavaScript graph is
 * proportional to the wire size — typically a small multiple of it.
 */
export const MAX_TOTAL_BYTES = 128 * 1024 * 1024

export interface ReactotronClient {
  connection: number
  name: string
  platform?: string | undefined
}

export interface Timeline {
  rows: TimelineRow[]
  /** Monotonic and never reused, so React keys survive a trim. */
  nextId: number
  totalBytes: number
  /** Every app currently connected, in the order they arrived. */
  clients: ReactotronClient[]
  /** The port the relay reported binding, once it said. */
  port: number | null
}

export function emptyTimeline(): Timeline {
  return { rows: [], nextId: 0, totalBytes: 0, clients: [], port: null }
}

/**
 * How many rows to drop from the front so the buffer fits its caps.
 *
 * Trims with hysteresis — once a cap is exceeded it trims down to 7/8 of that
 * cap — so a steady stream trims in batches instead of shifting the array on
 * every append. The newest row is always kept, even when it alone exceeds the
 * byte budget.
 */
export function dropCount(
  sized: readonly { bytes: number }[],
  totalBytes: number,
  maxRows: number = MAX_ROWS,
  maxBytes: number = MAX_TOTAL_BYTES,
): number {
  if (sized.length <= maxRows && totalBytes <= maxBytes) return 0
  const targetRows = maxRows - Math.trunc(maxRows / 8)
  const targetBytes = maxBytes - Math.trunc(maxBytes / 8)
  let drop = 0
  let kept = sized.length
  let bytes = totalBytes
  while (kept > 1 && (kept > targetRows || bytes > targetBytes)) {
    const size = sized[drop]?.bytes
    if (size === undefined) break
    drop++
    kept--
    bytes -= size
  }
  return drop
}

/** One relay frame folded into the timeline. */
export function applyFrame(
  timeline: Timeline,
  frame: ReactotronFrame,
  receivedAt: number,
): Timeline {
  switch (frame.kind) {
    case "listening":
      return { ...timeline, port: frame.port ?? timeline.port }
    case "connected":
      return connected(timeline, frame, receivedAt)
    case "command":
      return commanded(timeline, frame, receivedAt)
    case "disconnected":
      return disconnected(timeline, frame, receivedAt)
  }
}

function connected(timeline: Timeline, frame: ReactotronFrame, receivedAt: number): Timeline {
  const connection = frame.connection
  const command = frame.command
  if (connection === undefined || command === undefined) return timeline
  const event = parseEvent(command)
  const name = event.kind === "clientIntro" ? event.name : "App"
  const platform = event.kind === "clientIntro" ? event.platform : undefined
  // Replace rather than append on a re-introduction: upstream's client sends a
  // second intro after a reload, and appending would double the app picker.
  const clients = [
    ...timeline.clients.filter((client) => client.connection !== connection),
    { connection, name, platform },
  ]
  return { ...appended(timeline, event, command, connection, frame.bytes ?? 0, receivedAt), clients }
}

function commanded(timeline: Timeline, frame: ReactotronFrame, receivedAt: number): Timeline {
  const connection = frame.connection
  const command = frame.command
  if (connection === undefined || command === undefined) return timeline
  const event = parseEvent(command)
  // A `clear` from the app wipes its own rows and leaves no row of its own.
  // Scoped to the sending client, so one app clearing does not wipe another
  // connected app's timeline.
  if (event.kind === "clear") return cleared(timeline, connection)
  return appended(timeline, event, command, connection, frame.bytes ?? 0, receivedAt)
}

function disconnected(timeline: Timeline, frame: ReactotronFrame, receivedAt: number): Timeline {
  const connection = frame.connection
  if (connection === undefined) return timeline
  // Named before the client is forgotten — the notice reads as the app's own.
  const app = timeline.clients.find((client) => client.connection === connection)?.name
  const clients = timeline.clients.filter((client) => client.connection !== connection)
  const notice = disconnectNotice(frame, app)
  if (notice === null) return { ...timeline, clients }
  const event: ReactotronEvent = { kind: "unknown", type: "disconnected", payload: notice.headline }
  // The full explanation rides the command payload, which is what the row
  // expands to; the headline is the one line the collapsed row has room for.
  const command: ReactotronCommand = { type: "disconnected", payload: notice.detail, important: true }
  return { ...appended(timeline, event, command, connection, 0, receivedAt), clients }
}

/**
 * Why the app went away, in words worth reading.
 *
 * 1001 is the one that matters: Android's WebSocket closes itself going-away
 * once 16 MB are queued, so it does not mean "the app quit", it means the app
 * out-produced the connection — and the fix is in the app's logging, which is
 * not something anyone guesses from "disconnected".
 */
export function disconnectNotice(
  frame: { reason?: string | undefined; code?: number | undefined },
  app: string | undefined,
): { headline: string; detail: string } | null {
  if (frame.reason === undefined) return null
  const name = app ?? "The app"
  if (frame.code === 1001) {
    return {
      headline: `${name} hung up — events outpaced the connection (WS 1001). Expand for the fix.`,
      detail:
        `${name} produced Reactotron events faster than the connection could send them, ` +
        "so Android's WebSocket closed itself once 16 MB were queued (close code 1001, " +
        "going-away).\n\nVery large console.log / action payloads are the usual cause — log " +
        "IDs and summaries instead of whole objects.\n\nReload the app to reconnect.",
    }
  }
  const text = `${name} closed the connection (app reloaded or exited).`
  return { headline: text, detail: text }
}

function appended(
  timeline: Timeline,
  event: ReactotronEvent,
  command: ReactotronCommand,
  connection: number,
  bytes: number,
  receivedAt: number,
): Timeline {
  const row = makeRow({ id: timeline.nextId, event, command, connection, bytes, receivedAt })
  const rows = [...timeline.rows, row]
  const totalBytes = timeline.totalBytes + bytes
  const drop = dropCount(rows, totalBytes)
  if (drop === 0) return { ...timeline, rows, nextId: timeline.nextId + 1, totalBytes }
  const dropped = rows.slice(0, drop)
  return {
    ...timeline,
    rows: rows.slice(drop),
    nextId: timeline.nextId + 1,
    totalBytes: totalBytes - dropped.reduce((sum, item) => sum + item.bytes, 0),
  }
}

/** Everything one client sent, forgotten. Its own rows only. */
export function cleared(timeline: Timeline, connection: number | null): Timeline {
  const rows =
    connection === null ? [] : timeline.rows.filter((row) => row.connection !== connection)
  return { ...timeline, rows, totalBytes: rows.reduce((sum, row) => sum + row.bytes, 0) }
}
