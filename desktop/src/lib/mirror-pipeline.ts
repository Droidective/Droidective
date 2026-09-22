/**
 * One mirror payload, from the wire into a decoder, a canvas and a speaker.
 *
 * Split from `useMirror` because none of it is a hook — it is the plumbing
 * either side of `lib/mirror.ts`, which is where the *decisions* live and
 * where they are tested without a decoder, a canvas or a device.
 */

import {
  codecSupport,
  MAX_PENDING_FRAMES,
  noteGap,
  replayable,
  stepMirror,
  type DecodeStep,
  type MirrorGate,
} from "@/lib/mirror"
import type { MirrorAudioPlayer } from "@/lib/mirror-player"
import type { MirrorFrame, StreamUpdate } from "@/lib/wire"

/** What the pieces below need to reach. Assembled once per subscription. */
export interface Wiring {
  canvas: React.RefObject<HTMLCanvasElement | null>
  gate: React.RefObject<MirrorGate>
  decoder: React.RefObject<VideoDecoder | null>
  /** Frames that arrived while `configure` was still awaiting its support check. */
  pending: React.RefObject<DecodeStep[]>
  setSize: (size: { width: number; height: number }) => void
  setDeviceName: (name: string | null) => void
  setStreaming: (streaming: boolean) => void
  setDropped: (update: (count: number) => number) => void
  fail: (message: string) => void
  live: () => boolean
  /** The graph the device's sound goes into, when the session asked for it. */
  audio: MirrorAudioPlayer
}

/**
 * Draw a decoded frame, sizing the canvas from the frame itself.
 *
 * The frames are the authority on size, not the config's hint: a device can
 * rotate mid-session and the daemon does not re-measure.
 */
function paint(frame: VideoFrame, wiring: Wiring): void {
  try {
    const element = wiring.canvas.current
    if (element === null) return
    const { displayWidth: width, displayHeight: height } = frame
    if (element.width !== width || element.height !== height) {
      element.width = width
      element.height = height
      wiring.setSize({ width, height })
    }
    element.getContext("2d")?.drawImage(frame, 0, 0)
  } finally {
    // Always, even if drawing threw: a VideoFrame holds a decoder buffer, and
    // leaking a few stalls the decoder outright.
    frame.close()
  }
}

/**
 * Build a decoder for the codec the device negotiated, once it is known to be
 * decodable here.
 */
async function configure(codec: string, wiring: Wiring): Promise<void> {
  const support = await codecSupport(codec)
  if (!wiring.live()) return
  if (!support.ok) {
    // The measured case on Linux — see `missingCodecHint`. Reported rather than
    // left as a black rectangle, which is what this check is for.
    wiring.pending.current = []
    wiring.fail(support.hint ?? "This webview cannot decode the device's video.")
    return
  }
  wiring.decoder.current?.close()
  const built = new VideoDecoder({
    output: (frame) => paint(frame, wiring),
    error: (thrown) => wiring.fail(thrown.message),
  })
  // `optimizeForLatency`: this is a live screen, so a decoder buffering frames
  // to smooth playback is showing the past.
  built.configure({ codec, optimizeForLatency: true })
  wiring.decoder.current = built
  // The await above spans frames, and scrcpy's first keyframe lands inside it.
  // Replaying from that keyframe is what gets a picture up now rather than at
  // the next one, which scrcpy leaves ten seconds away by default.
  const replay = replayable(wiring.pending.current)
  wiring.pending.current = []
  if (replay.length === 0) wiring.gate.current = noteGap(wiring.gate.current)
  for (const step of replay) decodeInto(built, step, wiring)
}

/** Hand one chunk to a configured decoder, reporting a rejection. */
function decodeInto(decoder: VideoDecoder, step: DecodeStep, wiring: Wiring): void {
  try {
    decoder.decode(
      new EncodedVideoChunk({
        type: step.type,
        timestamp: step.timestamp,
        data: step.data,
      }),
    )
  } catch (thrown) {
    // A decoder that rejects a chunk is done — it does not recover on the next
    // one, so say so rather than showing a frozen picture.
    wiring.fail(thrown instanceof Error ? thrown.message : String(thrown))
  }
}

/** One payload, through the rules in `lib/mirror.ts` and into the decoder. */
function accept(frame: MirrorFrame, wiring: Wiring): void {
  const outcome = stepMirror(wiring.gate.current, frame)
  wiring.gate.current = outcome.gate
  const step = outcome.step
  if (step.do === "configure") {
    wiring.setDeviceName(step.deviceName)
    // A hint for the first layout only — `paint` corrects it.
    wiring.setSize({ width: step.width, height: step.height })
    void configure(step.codec, wiring)
    return
  }
  if (step.do === "audio-configure") {
    wiring.audio.configure(step.sampleRate, step.channels)
    return
  }
  if (step.do === "audio") {
    wiring.audio.play(step.pcm)
    return
  }
  if (step.do !== "decode") return
  const decoder = wiring.decoder.current
  // `configure` awaits its support check, so frames — the first keyframe among
  // them — arrive before the decoder exists. Holding them is what keeps that
  // keyframe: dropping it left every following delta to be decoded against
  // pictures no decoder ever saw, which WebCodecs ends the session over
  // ("Key frame is required"). Past the cap the backlog is stale enough that
  // the next keyframe is the better start, so the gate waits for one.
  if (decoder === null || decoder.state !== "configured") {
    if (wiring.pending.current.length >= MAX_PENDING_FRAMES) {
      wiring.pending.current = []
      wiring.gate.current = noteGap(wiring.gate.current)
      return
    }
    wiring.pending.current.push(step)
    return
  }
  decodeInto(decoder, step, wiring)
}

/**
 * What each stream event means.
 *
 * Lifted out of the effect because it is the stream's protocol rather than this
 * hook's lifecycle — and because `dropped` has to reach the gate, not just a
 * counter: until the next keyframe every delta references pictures this decoder
 * never saw.
 */
export function handler(wiring: Wiring) {
  return (update: StreamUpdate<MirrorFrame>) => {
    switch (update.event) {
      case "subscribed":
        wiring.setStreaming(true)
        break
      case "batch":
        for (const item of update.items) accept(item, wiring)
        break
      case "dropped":
        wiring.gate.current = noteGap(wiring.gate.current)
        wiring.setDropped((count) => count + update.count)
        break
      case "ended":
        wiring.setStreaming(false)
        break
      default:
        wiring.fail(update.message)
    }
  }
}
