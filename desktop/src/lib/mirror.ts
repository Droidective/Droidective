/**
 * What a mirror subscription's frames mean, kept away from React.
 *
 * The daemon relays scrcpy's stream and the webview decodes it — that decision,
 * and the measurement behind it, is backlog 25's step 0 in
 * `docs/desktop-parity.md`. Three rules come with it, all of them here so they
 * can be tested without a device, a decoder, or a canvas:
 *
 * 1. **Configure on `config`, never before.** A decoder fed a frame before it
 *    has a codec throws, and the throw is terminal for the `VideoDecoder`.
 * 2. **After a gap, wait for a keyframe.** `dropped` on this topic means the
 *    daemon's bounded buffer discarded frames, and an H.264 delta frame is
 *    meaningless without its predecessors — feeding one after a gap renders
 *    garbage rather than a gap. Every keyframe the daemon sends carries its own
 *    SPS/PPS, so the next one is always a clean start.
 * 3. **Size from the frames.** `config.width`/`height` are the session's
 *    opening dimensions and a device can rotate afterwards; a decoded frame
 *    carries its own. See `MirrorFramePayload` in the daemon.
 */

import type { MirrorFrame } from "@/lib/wire"

/** What the caller should do with one payload. */
export type MirrorStep =
  | {
      do: "configure"
      codec: string
      width: number
      height: number
      deviceName: string | null
    }
  | DecodeStep
  /** Nothing to do, and why — the reasons are distinct bugs if they persist. */
  | { do: "skip"; why: "unconfigured" | "awaiting-key" | "malformed" }

/** One chunk to hand a configured decoder. */
export interface DecodeStep {
  do: "decode"
  type: "key" | "delta"
  timestamp: number
  data: Uint8Array
}

/**
 * How many decodable frames to hold while a decoder configures.
 *
 * `configure` awaits `VideoDecoder.isConfigSupported`, so it spans frames, and
 * scrcpy sends its first keyframe immediately after the config packet — inside
 * that window. A cap because this is a live stream: if configuring takes long
 * enough to fill it, replaying the backlog would show seconds of the past, and
 * the next keyframe is the better start. At ~60fps this is four seconds.
 */
export const MAX_PENDING_FRAMES = 240

/**
 * The frames worth replaying once a decoder is finally configured.
 *
 * A `VideoDecoder` must be handed a keyframe before any delta — WebCodecs
 * answers a delta-first stream with "Key frame is required", and the decoder is
 * dead after it. So the replay starts at the first keyframe in the window and
 * discards whatever preceded it, which is exactly what those deltas are worth:
 * they reference pictures this decoder never decoded.
 *
 * Empty when the window holds no keyframe, which leaves the caller waiting for
 * the next one rather than feeding the decoder something it must reject.
 */
export function replayable(pending: readonly DecodeStep[]): DecodeStep[] {
  const first = pending.findIndex((step) => step.type === "key")
  return first === -1 ? [] : pending.slice(first)
}

/** Whether a decoder exists yet, and whether it is mid-recovery. */
export interface MirrorGate {
  configured: boolean
  awaitingKey: boolean
}

export function newGate(): MirrorGate {
  return { configured: false, awaitingKey: false }
}

/**
 * The daemon reported a gap.
 *
 * Recovery is to drop everything until the next keyframe. Nothing is reset
 * besides that: the decoder is still configured, and re-configuring it would
 * throw away the frames still in flight for no gain.
 */
export function noteGap(gate: MirrorGate): MirrorGate {
  return { ...gate, awaitingKey: true }
}

/** A fresh stream — a reconnect, or a different device. */
export function noteRestart(): MirrorGate {
  return newGate()
}

export function stepMirror(
  gate: MirrorGate,
  frame: MirrorFrame,
): { gate: MirrorGate; step: MirrorStep } {
  if (frame.kind === "config") {
    if (
      typeof frame.codec !== "string" ||
      typeof frame.width !== "number" ||
      typeof frame.height !== "number"
    ) {
      return { gate, step: { do: "skip", why: "malformed" } }
    }
    // A re-configure clears the wait: the parameter sets just changed, so
    // whatever was in flight for the old ones is not worth waiting for.
    return {
      gate: { configured: true, awaitingKey: false },
      step: {
        do: "configure",
        codec: frame.codec,
        width: frame.width,
        height: frame.height,
        deviceName: frame.deviceName ?? null,
      },
    }
  }

  const bytes = typeof frame.data === "string" ? decodeFrame(frame.data) : null
  if (bytes === null || typeof frame.pts !== "number") {
    return { gate, step: { do: "skip", why: "malformed" } }
  }
  const key = frame.key === true
  if (!gate.configured) return { gate, step: { do: "skip", why: "unconfigured" } }
  if (gate.awaitingKey && !key) return { gate, step: { do: "skip", why: "awaiting-key" } }
  return {
    gate: { ...gate, awaitingKey: false },
    step: { do: "decode", type: key ? "key" : "delta", timestamp: frame.pts, data: bytes },
  }
}

/**
 * One frame's Annex-B bytes.
 *
 * The same byte-per-code-unit walk `decodeChunk` does for terminal output, and
 * for the same reason: this is binary, so anything that treats it as text
 * corrupts it. Kept separate rather than imported because that one is about a
 * pty and this one runs per video frame.
 */
export function decodeFrame(base64: string): Uint8Array | null {
  let binary: string
  try {
    binary = atob(base64)
  } catch {
    // A frame that is not base64 is a protocol bug, not something to crash the
    // pane over: skip it and let the next keyframe recover.
    return null
  }
  const bytes = new Uint8Array(binary.length)
  for (let index = 0; index < binary.length; index += 1) {
    // oxlint-disable-next-line unicorn/prefer-code-point
    bytes[index] = binary.charCodeAt(index)
  }
  return bytes
}

/** Whether this build of the webview can decode at all. */
export function hasVideoDecoder(): boolean {
  return globalThis.VideoDecoder !== undefined
}

/**
 * Whether this webview can decode `codec`, and what to say if it cannot.
 *
 * This is not defensive programming — it is the feature. WebKitGTK implements
 * WebCodecs over GStreamer, so `VideoDecoder` exists while H.264 does not:
 * measured on WebKitGTK 2.52.3, every `avc1.*` config is unsupported on a stock
 * Ubuntu 24.04 and supported once `gstreamer1.0-libav` is installed, which is
 * not a dependency of the webview package. Without this check the mirror is a
 * black rectangle; with it, it names the package.
 * `scripts/probe-webkit-webcodecs.sh` re-runs that measurement.
 */
export async function codecSupport(codec: string): Promise<{ ok: boolean; hint: string | null }> {
  if (!hasVideoDecoder()) {
    return { ok: false, hint: "This webview has no VideoDecoder, so it cannot mirror a screen." }
  }
  try {
    const support = await VideoDecoder.isConfigSupported({ codec })
    if (support.supported === true) return { ok: true, hint: null }
  } catch {
    // A codec string the implementation refuses to parse lands here, and it
    // means the same thing as an unsupported one.
  }
  return { ok: false, hint: missingCodecHint(codec) }
}

/**
 * What to tell someone whose webview cannot decode H.264.
 *
 * Names the package rather than the codec: "avc1.42C029 is unsupported" is true
 * and useless, and the fix is one `apt install` away on the platform where this
 * actually happens.
 */
export function missingCodecHint(codec: string): string {
  return (
    `This webview cannot decode ${codec}. On Linux the H.264 decoder is a ` +
    "separate GStreamer package — install gstreamer1.0-libav (Debian and " +
    "Ubuntu) or gstreamer1-libav (Fedora, from RPM Fusion), then reopen the " +
    "mirror."
  )
}
