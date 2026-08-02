import { useCallback, useEffect, useRef, useState } from "react"
import { asDaemonError, watchLogcat, type Subscription } from "@/lib/daemon"
import { emptyBuffer, withGap, withLines, type LogBuffer } from "@/lib/logbuffer"
import type { DaemonError } from "@/lib/wire"

export interface LogcatStream {
  buffer: LogBuffer
  streaming: boolean
  error: DaemonError | null
  /** Why the daemon stopped sending, if it did. */
  ended: string | null
  stop: () => Promise<void>
}

/**
 * One device's live log.
 *
 * A subscription left running keeps an `adb logcat` child alive on the daemon
 * side, so the cleanup here is load-bearing rather than tidiness — the
 * daemon's unsubscribe is what kills that child.
 */
export function useLogcatStream(serial: string | null): LogcatStream {
  const [buffer, setBuffer] = useState<LogBuffer>(emptyBuffer)
  const [streaming, setStreaming] = useState(false)
  const [error, setError] = useState<DaemonError | null>(null)
  const [ended, setEnded] = useState<string | null>(null)
  const subscription = useRef<Subscription | null>(null)

  const stop = useCallback(async () => {
    const live = subscription.current
    subscription.current = null
    setStreaming(false)
    await live?.stop()
  }, [])

  useEffect(() => {
    if (serial === null) return
    // StrictMode runs this twice in development; without the flag the second
    // run's subscription replaces the first, which is then never stopped.
    let cancelled = false
    setBuffer(emptyBuffer())
    setEnded(null)
    setError(null)

    const start = async () => {
      try {
        const live = await watchLogcat(serial, (update) => {
          switch (update.event) {
            case "batch":
              setBuffer((current) => withLines(current, update.items))
              break
            case "dropped":
              // Rendered as a visible gap, never swallowed: the daemon drops
              // oldest under load and says so, and hiding that would let the
              // feed quietly claim to be complete.
              setBuffer((current) => withGap(current, update.count))
              break
            case "ended":
              setEnded(update.reason)
              setStreaming(false)
              break
            case "failed":
              setError({ code: "stream_failed", message: update.message, detail: null })
              setStreaming(false)
              break
            default:
              break
          }
        })
        if (cancelled) {
          void live.stop()
          return
        }
        subscription.current = live
        setStreaming(true)
      } catch (thrown) {
        if (!cancelled) setError(asDaemonError(thrown))
      }
    }
    void start()

    return () => {
      cancelled = true
      void stop()
    }
  }, [serial, stop])

  return { buffer, streaming, error, ended, stop }
}
