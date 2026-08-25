/**
 * The wire shapes carried by `/v1/stream`.
 *
 * Split out of `wire.ts` when it outgrew its line budget, and split *here*
 * because these are the topics rather than the request/response calls: a log
 * line, a performance sample, a throughput sample, a chunk of terminal output,
 * a Reactotron frame, and the event envelope all six ride in. Every one is
 * re-exported from `@/lib/wire`, so no import moved.
 */

import type { JsonValue } from "@/lib/json"

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

/**
 * Which app is in front, when one is.
 *
 * The key is absent rather than null when there is nothing worth naming — the
 * daemon omits nil optionals throughout — and the launcher being in front is the
 * common case, not a failure.
 */
export interface ForegroundResponse {
  packageId?: string | undefined
}

/** One device's `adb reverse` outcome. */
export interface ReactotronReverseResult {
  serial: string
  ok: boolean
  /**
   * adb's own words when it refused. Not a bare failure flag: "device offline"
   * and "more than one device" want different things done about them.
   */
  detail: string
}

export interface ReactotronReverseResponse {
  results: ReactotronReverseResult[]
  /** The exact command the daemon ran, which the pane shows verbatim. */
  command: string
}

/**
 * One Reactotron frame, as the relay decoded it.
 *
 * The envelope is fixed and the payload's shape depends on `type` — that is
 * upstream's contract, not ours, so the payload stays a bare JSON value and
 * `lib/reactotron.ts` picks fields out of it per type. `important` arrives as a
 * real boolean because the daemon already repaired the client's
 * `"~~~ false ~~~"` spelling of one.
 */
export interface ReactotronCommand {
  type: string
  payload?: JsonValue | undefined
  important?: boolean | undefined
  date?: string | undefined
  deltaTime?: number | undefined
}

/**
 * One thing the relay saw, off the `reactotron` topic.
 *
 * A flat envelope with a `kind` string rather than four payload types, because
 * the timeline renders them as one list. `listening` is about the relay itself
 * and carries neither a connection nor a frame.
 */
export interface ReactotronFrame {
  kind: "listening" | "connected" | "command" | "disconnected"
  connection?: number | undefined
  port?: number | undefined
  /** What the app called itself in its `client.intro`, when it said. */
  clientId?: string | undefined
  command?: ReactotronCommand | undefined
  /** Why a client went away, when the transport said. */
  reason?: string | undefined
  /**
   * The WebSocket close status, when the client sent one.
   *
   * 1001 is the one worth acting on: Android's WebSocket closes *itself*
   * going-away once 16 MB are queued, so 1001 does not mean the app quit — it
   * means the app out-produced the connection, which has a fix nobody guesses
   * from the word "disconnected".
   */
  code?: number | undefined
  /**
   * The frame's own size on the wire, for the frames that had one.
   *
   * It travels because this side cannot recover it: the timeline bounds itself
   * by retained bytes as well as by row count, and the only other way to a size
   * is re-serializing every payload as it arrives — the exact walk the feed is
   * built to avoid.
   */
  bytes?: number | undefined
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

/**
 * One mirror frame, or the configuration that has to precede them.
 *
 * Two kinds in one payload because a client cannot decode before it has
 * configured a decoder, and sharing the subscription is what makes that
 * ordering free rather than something to sequence. The daemon's own
 * `MirrorFramePayload` is the other side of this; §5.4 of
 * `docs/droidectived-protocol.md` is the contract.
 *
 * The bytes are Annex-B, which is what `VideoDecoder` decodes when
 * `description` is absent, and every keyframe carries its own SPS/PPS.
 */
export interface MirrorFrame {
  kind: "config" | "frame"
  /** `config`: the RFC 6381 string `VideoDecoder.configure` takes. */
  codec?: string | undefined
  /**
   * `config`: the size scrcpy negotiated — a hint for the first layout, not
   * the truth. A device can rotate without the daemon learning the new
   * geometry, and a decoded `VideoFrame` carries its own dimensions, so size
   * from the frames.
   */
  width?: number | undefined
  height?: number | undefined
  /** `config`: the device's own name, for the tile caption. */
  deviceName?: string | undefined
  /** `frame`: a keyframe, which is `EncodedVideoChunk`'s `type: "key"`. */
  key?: boolean | undefined
  /** `frame`: presentation timestamp in microseconds, on the device's clock. */
  pts?: number | undefined
  /** `frame`: base64 Annex-B bytes. */
  data?: string | undefined
}
