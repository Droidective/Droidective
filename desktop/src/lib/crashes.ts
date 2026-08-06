/**
 * The Crash Catcher's rules.
 *
 * The daemon hands over whatever `CrashParser` found, newest first, and adds
 * nothing. Everything here is about *narrowing* that list — which kinds are
 * worth offering as a filter, what a search matches, and which crashes a Clear
 * Buffer should keep hiding — and none of it belongs inside a component.
 */

import type { CrashReport } from "@/lib/wire"

/** The formats the Mac's Copy menu offers, mirroring ADBKit's `CrashFormat`. */
export type CrashFormat = "plain" | "slack" | "jira"

export const CRASH_FORMATS: readonly { readonly id: CrashFormat; readonly label: string }[] = [
  { id: "plain", label: "Plain text" },
  { id: "slack", label: "Slack code block" },
  { id: "jira", label: "Jira code block" },
]

/**
 * A crash wrapped for pasting somewhere. Mirrors `CrashExtractor.format` — the
 * fences are a contract with the Mac, so the same crash pasted from either app
 * arrives in Slack looking the same.
 */
export function formatCrash(block: string, format: CrashFormat): string {
  switch (format) {
    case "slack":
      return "```\n" + block + "\n```"
    case "jira":
      return "{code}\n" + block + "\n{code}"
    default:
      return block
  }
}

export interface CrashFilters {
  /** A `CrashReport.kind` raw value, or null for every kind. */
  kind: string | null
  process: string | null
  search: string
}

export const NO_FILTERS: CrashFilters = { kind: null, process: null, search: "" }

/**
 * Crashes hidden by a Clear Buffer.
 *
 * Clearing empties `logcat -b crash`, but the same crashes can resurface from
 * the main-buffer fallback the next fetch uses when the crash buffer is empty —
 * so the Mac remembers a high-water mark and keeps hiding anything at or below
 * it. Scoped to the serial it was taken on: a mark from one device must never
 * hide another's crashes.
 */
export interface ClearMark {
  serial: string
  /** The newest timestamp present when Clear ran. */
  mark: string
}

/**
 * The mark to remember after clearing, or null when there is nothing to
 * compare against later.
 */
export function markAfterClear(serial: string, crashes: readonly CrashReport[]): ClearMark | null {
  const stamps = crashes.map((crash) => crash.timestamp).filter((stamp) => stamp !== null)
  const newest = stamps.toSorted().at(-1)
  return newest === undefined ? null : { serial, mark: newest }
}

/**
 * Everything not hidden by a previous Clear Buffer.
 *
 * A crash with no timestamp cannot be compared against the mark, so it stays
 * visible: resurfacing a cleared crash is a smaller harm than silently hiding
 * a new one. Logcat stamps carry no year, so the string compare mis-hides only
 * across a December→January rollover, and only until the mark is dropped.
 */
export function unclearedCrashes(
  crashes: readonly CrashReport[],
  serial: string | null,
  cleared: ClearMark | null,
): CrashReport[] {
  if (cleared === null || cleared.serial !== serial) return [...crashes]
  return crashes.filter((crash) => crash.timestamp === null || crash.timestamp > cleared.mark)
}

/** Case-insensitive, over the title, the process, and the whole raw block. */
export function matchesCrash(crash: CrashReport, search: string): boolean {
  const needle = search.toLowerCase().trim()
  if (needle === "") return true
  return (
    crash.title.toLowerCase().includes(needle) ||
    (crash.process?.toLowerCase().includes(needle) ?? false) ||
    crash.raw.toLowerCase().includes(needle)
  )
}

export function filterCrashes(
  crashes: readonly CrashReport[],
  filters: CrashFilters,
): CrashReport[] {
  return crashes.filter((crash) => {
    if (filters.kind !== null && crash.kind !== filters.kind) return false
    if (filters.process !== null && crash.process !== filters.process) return false
    return matchesCrash(crash, filters.search)
  })
}

export interface KindOption {
  kind: string
  label: string
}

/**
 * The kinds actually present, in the order they first appear.
 *
 * Only what is there: a Kind menu listing five options against a list holding
 * one is a menu whose other four choices all empty the list.
 */
export function presentKinds(crashes: readonly CrashReport[]): KindOption[] {
  const seen = new Map<string, string>()
  for (const crash of crashes) {
    if (!seen.has(crash.kind)) seen.set(crash.kind, crash.kindLabel)
  }
  return [...seen].map(([kind, label]) => ({ kind, label }))
}

/** The processes present, sorted. Empty when nothing named one. */
export function presentProcesses(crashes: readonly CrashReport[]): string[] {
  const names = new Set<string>()
  for (const crash of crashes) {
    if (crash.process !== null) names.add(crash.process)
  }
  return [...names].toSorted((left, right) => left.localeCompare(right))
}

/**
 * A filter naming something no longer in the list is dropped.
 *
 * Otherwise a refresh that removes the last crash of some kind leaves the
 * screen empty with a Kind menu still claiming to be filtering on it, and
 * nothing on screen explains why.
 */
export function prunedFilters(
  filters: CrashFilters,
  crashes: readonly CrashReport[],
): CrashFilters {
  const kinds = new Set(presentKinds(crashes).map((option) => option.kind))
  const processes = new Set(presentProcesses(crashes))
  return {
    kind: filters.kind !== null && kinds.has(filters.kind) ? filters.kind : null,
    process: filters.process !== null && processes.has(filters.process) ? filters.process : null,
    search: filters.search,
  }
}

/**
 * What stays selected after a refresh.
 *
 * A watch poll mostly returns the same list, and the selection has to survive
 * it — that is why the daemon sends a `CrashReport.id` stable across refetches.
 * When the selected crash really is gone, fall to the first visible one rather
 * than to nothing.
 */
export function keptSelection(
  selected: string | null,
  visible: readonly CrashReport[],
): string | null {
  if (selected !== null && visible.some((crash) => crash.id === selected)) return selected
  return visible[0]?.id ?? null
}

/**
 * The newest crash in `next` that was not in `previous`, or null.
 *
 * What Watch announces. Compared by id rather than by count: a crash aging out
 * of the buffer while another arrives leaves the count unchanged.
 */
export function newestUnseen(
  previous: readonly CrashReport[],
  next: readonly CrashReport[],
): CrashReport | null {
  const known = new Set(previous.map((crash) => crash.id))
  return next.find((crash) => !known.has(crash.id)) ?? null
}

/** True when two fetches returned the same crashes, so nothing need re-render. */
export function sameCrashes(left: readonly CrashReport[], right: readonly CrashReport[]): boolean {
  if (left.length !== right.length) return false
  return left.every((crash, index) => crash.id === right[index]?.id)
}

/** How long Watch waits between polls, matching the Mac's 5 s. */
export const WATCH_INTERVAL_MS = 5000
