import { useCallback, useEffect, useRef, useState } from "react"
import { asDaemonError, watchMirror, type MirrorSession } from "@/lib/daemon"
import { newGate, type DecodeStep, type MirrorGate } from "@/lib/mirror"
import { handler, type Wiring } from "@/lib/mirror-pipeline"
import { MirrorAudioPlayer } from "@/lib/mirror-player"
import { FULL_QUALITY, type Quality } from "@/lib/mirror-wall"
import { encodeControl } from "@/lib/scrcpy-control"
import type { DaemonError } from "@/lib/wire"

export interface Mirror {
  /** The video's own size, from the decoded frames. Zero until the first. */
  size: { width: number; height: number }
  /** The device's name, as scrcpy reported it. */
  deviceName: string | null
  streaming: boolean
  error: DaemonError | null
  /** Tear the session down and start a new one — the Mac's Reconnect. */
  reconnect: () => void
  /** Frames the daemon discarded because this client fell behind. */
  dropped: number
  /** Send a control message — a tap, a key, a scroll. */
  send: (bytes: Uint8Array) => void
  /** Paint the newest decoded frame into a canvas. */
  attach: (canvas: HTMLCanvasElement | null) => void
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
/**
 * The two callbacks that outlive every session: where to paint, and how to
 * talk back. Neither depends on the subscription, so neither belongs in it.
 */
function useMirrorIO(
  canvas: React.RefObject<HTMLCanvasElement | null>,
  session: React.RefObject<MirrorSession | null>,
): Pick<Mirror, "attach" | "send"> {
  return {
    attach: useCallback(
      (element: HTMLCanvasElement | null) => {
        canvas.current = element
      },
      [canvas],
    ),
    send: useCallback(
      (bytes: Uint8Array) => {
        // Fire and forget: a tap that fails is not worth a dialog, and the next
        // frame will show whether it landed. Ordering is the socket's job.
        void session.current?.send(encodeControl(bytes))
      },
      [session],
    ),
  }
}

/** Everything one subscription needs to write back into. */
interface SessionRefs {
  canvas: React.RefObject<HTMLCanvasElement | null>
  session: React.RefObject<MirrorSession | null>
  decoder: React.RefObject<VideoDecoder | null>
  gate: React.RefObject<MirrorGate>
  pending: React.RefObject<DecodeStep[]>
}

interface SessionSinks {
  setSize: (size: { width: number; height: number }) => void
  setDeviceName: (name: string | null) => void
  setStreaming: (streaming: boolean) => void
  setError: (error: DaemonError | null) => void
  setDropped: React.Dispatch<React.SetStateAction<number>>
}

/**
 * One scrcpy session, for as long as its inputs hold still.
 *
 * Its own hook because it is the only long thing here, and because its
 * dependency list is the feature's whole restart policy: the serial, the two
 * quality numbers, whether sound was asked for — scrcpy takes audio as a
 * *start* option, which is why the Mac's toggle says "restarts mirror" — and
 * the reconnect counter.
 */
function useMirrorSession(args: {
  serial: string | null
  maxSize: number
  maxFps: number
  wantsAudio: boolean
  attempt: number
  player: MirrorAudioPlayer
  refs: SessionRefs
  sinks: SessionSinks
}): void {
  const { serial, maxSize, maxFps, wantsAudio, attempt, player } = args
  // Through a ref, the way `useClearApk` takes its sink: every one of these is
  // stable in practice (a `useRef` box, a `useState` setter), but they arrive
  // as arguments, where the linter cannot see that — and listing them would
  // restart the scrcpy server on every render.
  const latest = useRef(args)
  latest.current = args

  useEffect(() => {
    const { canvas, session, decoder, gate, pending } = latest.current.refs
    const { setSize, setDeviceName, setStreaming, setError, setDropped } = latest.current.sinks

    // A new session is a new stream: everything the last one left behind
    // describes a device this one is not watching.
    setSize({ width: 0, height: 0 })
    setDeviceName(null)
    setStreaming(false)
    setError(null)
    setDropped(0)
    gate.current = newGate()
    pending.current = []
    player.close()
    if (serial === null) return

    let cancelled = false
    const wiring: Wiring = {
      canvas,
      gate,
      decoder,
      pending,
      setSize,
      setDeviceName,
      setStreaming,
      setDropped,
      audio: player,
      live: () => !cancelled,
      fail: (message) => {
        if (cancelled) return
        setError({ code: "mirror_failed", message, detail: null })
        setStreaming(false)
      },
    }

    watchMirror(serial, { maxSize, maxFps, audio: wantsAudio }, handler(wiring)).then(
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
      pending.current = []
      // Same reasoning for the sound: the queue is for a session that is gone,
      // and letting it drain would play seconds of a device nobody is watching.
      player.close()
      // `close`, not `flush`: pending frames are for a screen that is gone.
      if (built !== null && built.state !== "closed") built.close()
    }
    // `wantsAudio` restarts the session on purpose: scrcpy takes audio as a
    // *start* option, which is why the Mac's own toggle says "restarts mirror".
  }, [serial, maxSize, maxFps, wantsAudio, attempt, player])
}

export function useMirror(serial: string | null, quality: Quality = FULL_QUALITY): Mirror {
  // One player for the hook's life, not per session: a reconnect should not
  // cost an `AudioContext`, and browsers cap how many a page may hold.
  const audioRef = useRef<MirrorAudioPlayer | null>(null)
  audioRef.current ??= new MirrorAudioPlayer()
  const player = audioRef.current
  // Destructured so the effect depends on the two numbers rather than the
  // object: a caller computing quality inline hands a fresh identity every
  // render, and depending on that would restart the scrcpy server on each one.
  const { maxSize, maxFps, audio: wantsAudio = false } = quality
  const [size, setSize] = useState({ width: 0, height: 0 })
  const [deviceName, setDeviceName] = useState<string | null>(null)
  const [streaming, setStreaming] = useState(false)
  const [error, setError] = useState<DaemonError | null>(null)
  const [dropped, setDropped] = useState(0)
  /**
   * Bumped by `reconnect`, and in the session effect's deps so bumping it
   * tears the old session down and starts a new one.
   *
   * A counter rather than a flag: two reconnects in a row have to be two
   * restarts, and a boolean that was already true would make the second do
   * nothing — which is exactly when someone presses it again.
   */
  const [attempt, setAttempt] = useState(0)

  // Refs throughout: the decoder callback runs outside React's world and must
  // not re-subscribe the stream every time a frame lands.
  const canvas = useRef<HTMLCanvasElement | null>(null)
  const session = useRef<MirrorSession | null>(null)
  const decoder = useRef<VideoDecoder | null>(null)
  const gate = useRef<MirrorGate>(newGate())
  const pending = useRef<DecodeStep[]>([])

  const { attach, send } = useMirrorIO(canvas, session)

  useMirrorSession({
    serial,
    maxSize,
    maxFps,
    wantsAudio,
    attempt,
    player,
    refs: { canvas, session, decoder, gate, pending },
    sinks: { setSize, setDeviceName, setStreaming, setError, setDropped },
  })

  const reconnect = useCallback(() => {
    setAttempt((current) => current + 1)
  }, [])

  return { size, deviceName, streaming, error, dropped, send, attach, reconnect }
}
