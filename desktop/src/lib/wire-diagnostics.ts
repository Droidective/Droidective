/**
 * The wire shapes for the two records you read when something went wrong: the
 * device's crash buffer, and this app's own log of the adb it ran.
 *
 * Split out of `wire.ts` when it outgrew its line budget, and split *here*
 * because neither is the state of a device — one is what a device already
 * printed, the other is what this app did. Both are re-exported from
 * `@/lib/wire`, so no import moved.
 */

/** One crash, as `CrashParser` split it out of a logcat buffer. */
export interface CrashReport {
  /** Stable across refetches, so a watch poll does not move the selection. */
  id: string
  /** A `CrashReport.Kind` raw value: java, native, reactNative, anr, unknown. */
  kind: string
  /** Sent by the daemon so both UIs name a kind the same way. */
  kindLabel: string
  /** Logcat's own timestamp. A string — logcat prints no year. */
  timestamp: string | null
  process: string | null
  pid: number | null
  title: string
  /** The block as logcat printed it. */
  raw: string
  /** The block with the threadtime prefixes stripped. */
  body: string
}

export interface CrashListResponse {
  /** Newest first. */
  crashes: CrashReport[]
}

/** One recorded adb call, as `CommandLogProtocol.Entry` sends it. */
export interface CommandLogEntry {
  id: string
  /** Milliseconds since the epoch. */
  at: number
  command: string
  /** Null when the process was killed rather than exiting. */
  exitCode: number | null
  durationMs: number
  stdout: string
  stderr: string
}

export interface CommandLogResponse {
  /** Most-recent-first, as `CommandLog.snapshot()` orders them. */
  entries: CommandLogEntry[]
}
