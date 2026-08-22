/**
 * What a timeline row *is*: the badge, the headline, the filterable kind, and
 * the text a search matches against.
 *
 * A port of the Mac's `RtItem` and `RtPresentation`. The colours do not come
 * across as colours — a pure model that imported a palette could not be tested
 * in a DOM-less runner, which is all this app has — so each carries a *tone*
 * and the view owns the one mapping from tone to class. The tones are chosen so
 * that mapping is one-to-one with the Mac's, which is what keeps a row looking
 * the same on both.
 */

import type { ReactotronCommand } from "@/lib/wire"
import type { ReactotronEvent } from "@/lib/reactotron"

/** Green for a connect, coral for a type badge, and the log levels between. */
export type BadgeTone = "ok" | "type" | "muted" | "warn" | "error"
/** Gold for a name the app chose, plain for its own text, grey for ours. */
export type PrimaryTone = "primary" | "name" | "muted"

export interface RowPresentation {
  badge: string
  badgeTone: BadgeTone
  primary: string
  primaryTone: PrimaryTone
  /**
   * An API event's HTTP status, shown on the collapsed row — reading a timeline
   * is mostly looking for the one call that did not return 200, and without
   * this that meant expanding each row.
   */
  status?: number | undefined
}

/**
 * The filterable kinds, with the same set, grouping and display names as the
 * Reactotron desktop app's timeline filter dialog. Events the dialog does not
 * cover — REPL, custom commands, state responses — are always shown.
 */
export const EVENT_KINDS = [
  "log",
  "image",
  "display",
  "connection",
  "benchmark",
  "api",
  "asyncStorage",
  "action",
  "saga",
  "subscription",
] as const
export type EventKind = (typeof EVENT_KINDS)[number]

export const KIND_LABELS: Record<EventKind, string> = {
  log: "Log",
  image: "Image",
  display: "Custom Display",
  connection: "Connection",
  benchmark: "Benchmark",
  api: "API",
  asyncStorage: "Mutations",
  action: "Action",
  saga: "Saga",
  subscription: "Subscription Changed",
}

/** The filter dialog's sections, mirroring Reactotron's own dialog. */
export const KIND_GROUPS: readonly { name: string; kinds: readonly EventKind[] }[] = [
  { name: "Informational", kinds: ["log", "image", "display"] },
  { name: "General", kinds: ["connection", "benchmark", "api"] },
  { name: "Async Storage", kinds: ["asyncStorage"] },
  { name: "State & Sagas", kinds: ["action", "saga", "subscription"] },
]

/**
 * The kind a filter toggle covers, or null for an event no toggle reaches —
 * which is shown unconditionally.
 *
 * Sagas arrive as `unknown` because the parser has no typed case for them, and
 * the relay's synthetic disconnect notice rides the Connection toggle alongside
 * `clientIntro`.
 */
export function rowKind(event: ReactotronEvent): EventKind | null {
  switch (event.kind) {
    case "log":
      return "log"
    case "image":
      return "image"
    case "display":
      return "display"
    case "clientIntro":
      return "connection"
    case "benchmark":
      return "benchmark"
    case "apiResponse":
      return "api"
    case "asyncStorage":
      return "asyncStorage"
    case "stateAction":
      return "action"
    case "stateValuesChange":
      return "subscription"
    case "unknown":
      if (event.type === "saga.task.complete") return "saga"
      return event.type === "disconnected" ? "connection" : null
    default:
      return null
  }
}

/** Longest headline kept for an unknown frame, which has no shape to trust. */
const maxUnknownPrimary = 140
/** Longest query text a URL's row shows before the rest is dropped. */
const maxQueryLength = 60

const levelTones: Record<string, BadgeTone> = { debug: "muted", warn: "warn", error: "error" }

export function presentation(event: ReactotronEvent): RowPresentation {
  switch (event.kind) {
    case "clientIntro":
      return {
        badge: "CONNECT",
        badgeTone: "ok",
        primary: [event.name, event.environment].filter(Boolean).join(" · "),
        primaryTone: "primary",
      }
    case "log":
      return {
        badge: event.level.toUpperCase(),
        badgeTone: levelTones[event.level] ?? "muted",
        primary: event.message,
        primaryTone: "primary",
      }
    case "display":
      return {
        badge: "DISPLAY",
        badgeTone: "type",
        primary: [event.name, event.preview].filter(Boolean).join(" — "),
        primaryTone: "name",
      }
    case "image":
      return { badge: "IMAGE", badgeTone: "type", primary: event.caption ?? "", primaryTone: "primary" }
    case "apiResponse":
      return {
        badge: "API",
        badgeTone: "type",
        primary: `${event.method} ${shortPath(event.url)}`,
        primaryTone: "primary",
        status: event.status,
      }
    case "benchmark":
      return { badge: "BENCHMARK", badgeTone: "type", primary: event.title, primaryTone: "name" }
    case "clear":
      return { badge: "CLEAR", badgeTone: "muted", primary: "", primaryTone: "muted" }
    case "asyncStorage":
      return { badge: "STORAGE", badgeTone: "type", primary: event.action, primaryTone: "name" }
    case "stateAction":
      return { badge: "ACTION", badgeTone: "type", primary: event.name, primaryTone: "name" }
    case "stateValuesChange":
      return {
        badge: "STATE",
        badgeTone: "type",
        primary: event.changes[0]?.path ?? `${event.changes.length} changes`,
        primaryTone: "name",
      }
    case "customCommandRegister":
      return { badge: "COMMAND", badgeTone: "type", primary: event.command, primaryTone: "name" }
    case "customCommandUnregister":
      return {
        badge: "COMMAND",
        badgeTone: "muted",
        primary: `removed ${event.command}`,
        primaryTone: "muted",
      }
    case "stateValuesResponse":
    case "stateKeysResponse":
      return { badge: "STATE", badgeTone: "type", primary: event.path ?? "store", primaryTone: "name" }
    case "stateBackup":
      return { badge: "SNAPSHOT", badgeTone: "type", primary: "", primaryTone: "primary" }
    case "replKeys":
      return { badge: "REPL", badgeTone: "type", primary: event.names.join(", "), primaryTone: "primary" }
    case "replResult":
      return { badge: "REPL", badgeTone: "type", primary: "result", primaryTone: "primary" }
    case "unknown":
      return unknownPresentation(event.type, event.payload)
  }
}

function unknownPresentation(type: string, payload: unknown): RowPresentation {
  const text = typeof payload === "string" ? payload : ""
  // The relay's synthetic drop notice — not a wire event. It gets warning
  // styling and an untruncated headline.
  if (type === "disconnected") {
    return { badge: "DISCONNECTED", badgeTone: "warn", primary: text, primaryTone: "primary" }
  }
  return {
    badge: type.toUpperCase(),
    badgeTone: "muted",
    primary: text.slice(0, maxUnknownPrimary),
    primaryTone: "muted",
  }
}

/**
 * Path (and a trimmed query) of an API URL, for the compact row; the full URL
 * shows once the row is expanded. A string that is not an absolute URL is left
 * exactly as the app sent it.
 */
export function shortPath(url: string): string {
  let parsed: URL
  try {
    parsed = new URL(url)
  } catch {
    return url
  }
  if (parsed.host === "") return url
  const path = parsed.pathname === "" ? "/" : parsed.pathname
  // `search` keeps its leading "?" when there is one at all.
  const query = parsed.search.slice(1)
  return query === "" ? path : `${path}?${query.slice(0, maxQueryLength)}`
}

/** The row as one line of text, for a copy of the collapsed timeline. */
export function rowText(row: RowPresentation): string {
  return [row.badge, row.status === undefined ? null : String(row.status), row.primary]
    .filter((part) => part !== null && part !== "")
    .join(" ")
    .trim()
}

export interface TimelineRow {
  /**
   * Monotonic and never reused, so it is both a stable React key and the
   * watermark a "clear" compares against: everything received up to this point
   * is one integer comparison, undisturbed by trimming.
   */
  id: number
  event: ReactotronEvent
  command: ReactotronCommand
  connection: number
  important: boolean
  /** The frame's wire size, which is what the byte budget is spent on. */
  bytes: number
  receivedAt: number
  /**
   * Badge and headline, lowercased once here, so filtering is a plain substring
   * check rather than rebuilding the presentation on every pass. Bounded, so a
   * `console.log` of a huge string cannot store a second megabyte-long copy of
   * itself: search matches the headline, and the full payload lives in the
   * expanded row.
   */
  searchText: string
}

const maxSearchTextLength = 2000

export function makeRow(args: {
  id: number
  event: ReactotronEvent
  command: ReactotronCommand
  connection: number
  bytes: number
  receivedAt: number
}): TimelineRow {
  const shown = presentation(args.event)
  return {
    ...args,
    important: args.command.important ?? false,
    searchText: `${shown.badge} ${shown.primary}`.slice(0, maxSearchTextLength).toLowerCase(),
  }
}
