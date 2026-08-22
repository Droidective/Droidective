/**
 * The wire shapes carried by `/v1/stream`.
 *
 * Split out of `wire.ts` when it outgrew its line budget, and split *here*
 * because these are the topics rather than the request/response calls: a log
 * line, a performance sample, a throughput sample, a chunk of terminal output,
 * and the event envelope all five ride in. Every one is re-exported from
 * `@/lib/wire`, so no import moved.
 */

/** A subscription update, shaped like the daemon's own stream event. */
export type StreamUpdate<Item> =
  | { event: "subscribed" }
  | { event: "batch"; items: Item[] }
  | { event: "dropped"; count: number }
  | { event: "ended"; reason: string }
  | { event: "failed"; message: string }

/**
 * Whatever the shell just wrote, base64.
 *
 * Base64 because it is bytes: a pty read ends wherever its buffer filled, so a
 * chunk can stop mid-character, and a JSON string would replace the half with
 * U+FFFD. `decodeChunk` in `lib/terminal.ts` turns it back.
 */
export interface PtyChunk {
  data: string
}

export interface LogLine {
  time: string
  pid: string
  tid: string
  level: string
  tag: string
  message: string
}

/** One performance sample, from `/v1/stream`'s `performance` topic. */
export interface PerfSample {
  /**
   * Empty on the first sample: a CPU percentage is a delta and there is
   * nothing yet to subtract from. `-1` is the all-cores aggregate.
   */
  cores: { core: number; label: string; usagePercent: number }[]
  ramTotalKb: number | null
  ramUsedKb: number | null
  appFps: number | null
  /** Percent of frames that missed the deadline, when any were drawn. */
  appJankPercent: number | null
  appPssKb: number | null
  downloadBytesPerSec: number | null
  uploadBytesPerSec: number | null
  processes: { pid: number; name: string; cpuPercent: number | null; pssKb: number | null }[]
}

/** One `/proc/net/dev` sample, as the daemon differenced it. */
export interface NetSample {
  downloadBytesPerSec: number
  uploadBytesPerSec: number
  /**
   * Since the device booted, not since the stream started — the screen
   * derives its own session totals by differencing against the first sample,
   * which is the only way a mid-session subscribe reads right.
   */
  totalRxBytes: number
  totalTxBytes: number
  interfaces: {
    name: string
    downloadBytesPerSec: number
    uploadBytesPerSec: number
    rxBytes: number
    txBytes: number
  }[]
}
