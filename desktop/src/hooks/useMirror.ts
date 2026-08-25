import { useCallback, useEffect, useRef, useState } from "react"
import { asDaemonError, watchMirror, type MirrorSession } from "@/lib/daemon"
import { codecSupport, newGate, noteGap, stepMirror, type MirrorGate } from "@/lib/mirror"
import { encodeControl } from "@/lib/scrcpy-control"
import type { DaemonError, MirrorFrame, StreamUpdate } from "@/lib/wire"

export interface Mirror {
  /** The video's own size, from the decoded frames. Zero until the first. */
  size: { width: number; height: number }
  /** The device's name, as scrcpy reported it. */
  deviceName: string | null
  streaming: boolean
  error: DaemonError | null
  /** Frames the daemon discarded because this client fell behind. */
  dropped: number
  /** Send a control message — a tap, a key, a scroll. */
  send: (bytes: Uint8Array) => void
  /** Paint the newest decoded frame into a canvas. */
  attach: (canvas: HTMLCanvasElement | null) => void
}

/** What the pieces below need to reach. Assembled once per subscription. */
interface Wiring {
  canvas: React.RefObject<HTMLCanvasElement | null>
  gate: React.RefObject<MirrorGate>
  decoder: React.RefObject<VideoDecoder | null>
  setSize: (size: { width: number; height: number }) => void
  setDeviceName: (name: string | null) => void
  setStreaming: (streaming: boolean) => void
  setDropped: (update: (count: number) => number) => void
  fail: (message: string) => void
  live: () => boolean
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
  if (step.do !== "decode") return
  const decoder = wiring.decoder.current
  // `configure` is async, so frames can arrive before the decoder exists.
  // Dropping them is right: the next keyframe is moments away.
  if (decoder === null || decoder.state !== "configured") return
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

/**
 * What each stream event means.
 *
 * Lifted out of the effect because it is the stream's protocol rather than this
 * hook's lifecycle — and because `dropped` has to reach the gate, not just a
 * counter: until the next keyframe every delta references pictures this decoder
 * never saw.
 */
function handler(wiring: Wiring) {
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

/**
 * One device's screen, decoded in this webview.
 *
 * The decode lives in a hook rather than in `lib/` because a `VideoDecoder` is
 * a stateful resource with a lifetime, like the subscription — and the two have
 * to be torn down together. What is *not* here is the protocol: `lib/mirror.ts`
 * decides what each payload means, so the rules that matter are tested without
 * a decoder, a canvas or a device.
 */
export function useMirror(serial: string | null): Mirror {
  const [size, setSize] = useState({ width: 0, height: 0 })
  const [deviceName, setDeviceName] = useState<string | null>(null)
  const [streaming, setStreaming] = useState(false)
  const [error, setError] = useState<DaemonError | null>(null)
  const [dropped, setDropped] = useState(0)

  // Refs throughout: the decoder callback runs outside React's world and must
  // not re-subscribe the stream every time a frame lands.
  const canvas = useRef<HTMLCanvasElement | null>(null)
  const session = useRef<MirrorSession | null>(null)
  const decoder = useRef<VideoDecoder | null>(null)
  const gate = useRef<MirrorGate>(newGate())

  const attach = useCallback((element: HTMLCanvasElement | null) => {
    canvas.current = element
  }, [])

  const send = useCallback((bytes: Uint8Array) => {
    // Fire and forget: a tap that fails is not worth a dialog, and the next
    // frame will show whether it landed. Ordering is the socket's job.
    void session.current?.send(encodeControl(bytes))
  }, [])

  useEffect(() => {
    setSize({ width: 0, height: 0 })
    setDeviceName(null)
    setStreaming(false)
    setError(null)
    setDropped(0)
    gate.current = newGate()
    if (serial === null) return

    let cancelled = false
    const wiring: Wiring = {
      canvas,
      gate,
      decoder,
      setSize,
      setDeviceName,
      setStreaming,
      setDropped,
      live: () => !cancelled,
      fail: (message) => {
        if (cancelled) return
        setError({ code: "mirror_failed", message, detail: null })
        setStreaming(false)
      },
    }

    watchMirror(serial, handler(wiring)).then(
      (handle) => {
        if (cancelled) {
          // Stopping is what removes the `adb forward`, so a subscription that
          // arrives after unmount must still be torn down.
          void handle.stop()
          return
        }
        session.current = handle
      },
      (thrown: unknown) => {
        if (!cancelled) setError(asDaemonError(thrown))
      },
    )

    return () => {
      cancelled = true
      void session.current?.stop()
      session.current = null
      const built = decoder.current
      decoder.current = null
      // `close`, not `flush`: pending frames are for a screen that is gone.
      if (built !== null && built.state !== "closed") built.close()
    }
  }, [serial])

  return { size, deviceName, streaming, error, dropped, send, attach }
}
