/**
 * What the pull progress strip shows.
 *
 * The Mac's strip lives in the window's safe-area inset and polls the
 * destination's size against the source's; the daemon does that polling here
 * and sends both numbers, so what is left is the arithmetic and the wording —
 * which is exactly the part that reads wrong when it is approximate.
 */

/** One transfer, as the `pull` topic reports it. */
export interface PullEvent {
  copied: number
  /** Absent for a directory: a recursive pull has no single total. */
  total: number | null
  /** Where it landed, on the last event only. */
  path: string | null
  done: boolean
  /** adb's own words when it failed, on the last event only. */
  failure: string | null
}

export interface PullState {
  /** The device path being pulled, for the label. */
  path: string
  copied: number
  total: number | null
  done: boolean
  landedAt: string | null
  failure: string | null
}

/**
 * The bar's fraction, or null when there is nothing to divide by.
 *
 * Null is an *indeterminate* bar rather than zero — a directory pull has no
 * total, and a bar sitting at 0% for a minute is a worse lie than one that
 * admits it cannot know. Clamped at 1 because the destination can briefly
 * exceed the source: adb writes in blocks, and a file system can report the
 * allocated size rather than the written one.
 */
export function fraction(state: PullState): number | null {
  if (state.total === null || state.total <= 0) return null
  return Math.min(1, Math.max(0, state.copied / state.total))
}

/** `1.4 MB` — the same units the file explorer uses. */
export function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  const units = ["KB", "MB", "GB", "TB"]
  let value = bytes / 1024
  let unit = 0
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024
    unit += 1
  }
  return `${value < 10 ? value.toFixed(1) : Math.round(value)} ${units[unit]}`
}

/**
 * The line under the bar.
 *
 * A finished pull says where it went, a failed one says why, and one in flight
 * counts — because "pulling…" for ninety seconds is the state this strip
 * exists to replace.
 */
export function caption(state: PullState): string {
  if (state.failure !== null) return state.failure
  if (state.done) return `Saved to ${state.landedAt ?? "your downloads folder"}`
  if (state.total === null) return `${formatBytes(state.copied)} copied`
  return `${formatBytes(state.copied)} of ${formatBytes(state.total)}`
}

/** The name shown beside the bar. */
export function leafName(path: string): string {
  return path.split(/[/\\]/u).filter((part) => part !== "").pop() ?? path
}

/** The next state after an event — the reducer the strip is driven by. */
export function apply(state: PullState, event: PullEvent): PullState {
  return {
    ...state,
    copied: event.copied,
    total: event.total,
    done: event.done,
    landedAt: event.path ?? state.landedAt,
    failure: event.failure ?? state.failure,
  }
}

export function started(path: string): PullState {
  return { path, copied: 0, total: null, done: false, landedAt: null, failure: null }
}

/**
 * How long a finished strip stays up before it goes.
 *
 * Long enough to read where the file went, short enough that it is not still
 * there when the next thing happens. A failure stays until it is dismissed —
 * an error that vanishes on its own is an error nobody read.
 */
export const DISMISS_AFTER_MS = 4000

export function dismissDelay(state: PullState): number | null {
  if (!state.done) return null
  return state.failure === null ? DISMISS_AFTER_MS : null
}
