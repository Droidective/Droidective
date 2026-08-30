/**
 * Narrowing the log to one app.
 *
 * The Mac's `LogcatView.streamLoop` in three decisions, kept here so they can be
 * tested without a device or a stream. The loop it describes is not obvious and
 * every step of it is there for a reason the Mac learned:
 *
 * - **An app filter means *that app's* logs.** If the app is not running, wait
 *   for it rather than silently streaming everything — a log that quietly shows
 *   the whole device while claiming to be filtered is worse than an empty one.
 * - **`adb logcat --pid` goes silent forever when the app dies or relaunches**
 *   under a new pid. So the pid is re-read on a timer and the stream restarted
 *   when it moves; otherwise the feed looks alive and is dead.
 * - **The device does the filtering.** `--pid` means the ring buffer holds only
 *   that app's lines; filtering a mixed buffer in the client would let a chatty
 *   neighbour evict the lines being looked for before anyone sees them.
 */

export type AppFilter =
  /** No app chosen — the whole device, which is what the log opens as. */
  | { kind: "off" }
  /** An app is chosen but not running. Nothing is streamed yet. */
  | { kind: "waiting"; packageId: string }
  /** Streaming that app, at the pid it was found under. */
  | { kind: "streaming"; packageId: string; pid: number }

export const APP_FILTER_OFF: AppFilter = { kind: "off" }

/**
 * How long before asking the device for the pid again.
 *
 * The Mac's two cadences: two seconds while waiting for a launch, because
 * someone watching an empty log is waiting on this; three while streaming,
 * because it is only checking that a live pid has not moved. Nothing to ask
 * about when no app is chosen.
 */
export function pollDelayMs(filter: AppFilter): number | null {
  switch (filter.kind) {
    case "off":
      return null
    case "waiting":
      return 2000
    case "streaming":
      return 3000
  }
}

/**
 * The filter after the device answered.
 *
 * `resolved` is the pid `/v1/logcat/pid` reported, or null for "not running".
 * The `packageId` is passed alongside so a stale answer — one that arrived
 * after the choice changed — is discarded rather than applied to the wrong app.
 */
export function nextAppFilter(
  current: AppFilter,
  packageId: string | null,
  resolved: number | null,
): AppFilter {
  if (packageId === null) return APP_FILTER_OFF
  // The answer is about an app nobody is asking about any more.
  if (current.kind !== "off" && current.packageId !== packageId) return current
  if (resolved === null) return { kind: "waiting", packageId }
  return { kind: "streaming", packageId, pid: resolved }
}

/**
 * Whether the subscription has to be torn down and reopened.
 *
 * True when the pid moved, which is the relaunch case, and when the filter goes
 * on or off. False for a re-read that found the same pid — restarting there
 * would clear the feed every three seconds.
 */
export function needsRestart(before: AppFilter, after: AppFilter): boolean {
  return streamPid(before) !== streamPid(after)
}

/**
 * The pid the subscription should carry, or null for the whole device.
 *
 * `waiting` is null like `off` is, and that is the one thing to be careful
 * about: they stream the same thing (nothing yet, and everything) but mean
 * opposite things to a reader, which is why the pane says which it is rather
 * than leaving an empty feed to be interpreted.
 */
export function streamPid(filter: AppFilter): number | null {
  return filter.kind === "streaming" ? filter.pid : null
}

/** What the toolbar says the log is showing. */
export function appFilterLabel(filter: AppFilter): string {
  switch (filter.kind) {
    case "off":
      return "All apps"
    case "waiting":
      return `Waiting for ${filter.packageId}…`
    case "streaming":
      return `${filter.packageId} (pid ${filter.pid})`
  }
}
