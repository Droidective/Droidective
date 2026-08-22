import { useCallback, useEffect, useRef, useState } from "react"
import { asDaemonError, watchNetspeed, type Subscription } from "@/lib/daemon"
import {
  CHART_WINDOW,
  MAX_SAMPLES,
  timed,
  withSample,
  type TimedNetSample,
} from "@/lib/netspeed"
import type { DaemonError, NetSample, StreamUpdate } from "@/lib/wire"

export interface Netspeed {
  /** The rolling window the chart draws. */
  live: TimedNetSample[]
  /** The kept samples, when recording. */
  recorded: TimedNetSample[]
  streaming: boolean
  recording: boolean
  error: DaemonError | null
  /** Samples the daemon had to discard because this client fell behind. */
  dropped: number
  startRecording: () => void
  stopRecording: () => void
}

/**
 * What each stream event means.
 *
 * Lifted out of the effect because it is the stream's protocol rather than
 * this hook's lifecycle — and because a `dropped` marker has to be surfaced,
 * not swallowed: a chart with a silent gap claims a continuity it does not
 * have, and the elapsed clock would understate the run.
 */
function handler({
  accept,
  setStreaming,
  setDropped,
  setError,
}: {
  accept: (sample: NetSample) => void
  setStreaming: (streaming: boolean) => void
  setDropped: (update: (count: number) => number) => void
  setError: (error: DaemonError) => void
}) {
  return (update: StreamUpdate<NetSample>) => {
    switch (update.event) {
      case "subscribed":
        setStreaming(true)
        break
      case "batch":
        for (const item of update.items) accept(item)
        break
      case "dropped":
        setDropped((count) => count + update.count)
        break
      case "ended":
        setStreaming(false)
        break
      default:
        setError({ code: "stream_failed", message: update.message, detail: null })
        setStreaming(false)
    }
  }
}

/**
 * The Network Speed stream.
 *
 * Sampling starts as soon as the screen is open — watching traffic is the
 * common case and the Mac's `NetworkView` goes live on appear — while a
 * recording is an explicit second state layered on top. The subscription is
 * torn down on unmount, so a background tab is not quietly polling a device.
 */
export function useNetspeed(serial: string | null): Netspeed {
  const [live, setLive] = useState<TimedNetSample[]>([])
  const [recorded, setRecorded] = useState<TimedNetSample[]>([])
  const [streaming, setStreaming] = useState(false)
  const [recording, setRecording] = useState(false)
  const [error, setError] = useState<DaemonError | null>(null)
  const [dropped, setDropped] = useState(0)

  // Refs, not state: the stream callback must see the current values without
  // re-subscribing every time a sample arrives.
  const index = useRef(0)
  const isRecording = useRef(false)

  useEffect(() => {
    setLive([])
    setRecorded([])
    setDropped(0)
    setStreaming(false)
    index.current = 0
    if (serial === null) return

    let cancelled = false
    let subscription: Subscription | null = null

    const accept = (sample: NetSample) => {
      const stamped = timed(sample, index.current)
      index.current += 1
      setLive((current) => withSample(current, stamped, CHART_WINDOW))
      if (isRecording.current) {
        setRecorded((current) => withSample(current, stamped, MAX_SAMPLES))
      }
    }

    watchNetspeed(
      serial,
      handler({ accept, setStreaming, setDropped, setError }),
    ).then(
      (handle) => {
        if (cancelled) {
          void handle.stop()
          return
        }
        subscription = handle
      },
      (thrown: unknown) => {
        if (!cancelled) setError(asDaemonError(thrown))
      },
    )

    return () => {
      cancelled = true
      void subscription?.stop()
    }
  }, [serial])

  return {
    live,
    recorded,
    streaming,
    recording,
    error,
    dropped,

    startRecording: useCallback(() => {
      // From now on, not retroactively: the rolling window holds whatever
      // happened to still be in it, and a recording that silently began two
      // minutes ago is not what Record means.
      setRecorded([])
      isRecording.current = true
      setRecording(true)
    }, []),

    // Only flips the flag; the samples stay exportable, as they do on the Mac.
    // There is no `discard` here on purpose — nothing in the UI throws a
    // recording away, and the one that used to (a successful export) was the
    // bug. The Mac's exit guard offers a real discard; when that lands here,
    // it comes back with a caller.
    stopRecording: useCallback(() => {
      isRecording.current = false
      setRecording(false)
    }, []),
  }
}
