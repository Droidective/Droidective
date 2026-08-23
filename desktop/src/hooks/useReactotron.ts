import { useCallback, useEffect, useRef, useState } from "react"
import { asDaemonError, watchReactotron, type Subscription } from "@/lib/daemon"
import { applyFrame, cleared, emptyTimeline, type Timeline } from "@/lib/reactotron-buffer"
import type { DaemonError, ReactotronFrame } from "@/lib/wire"

/**
 * Whether the relay is up, and whether anything has found it.
 *
 * The distinction is the whole point of the connect banner: a relay listening
 * with nothing connected looks identical to a broken feature unless the screen
 * says which it is.
 */
export type RelayState = "starting" | "listening" | "connected" | "failed"

export interface ReactotronFeed {
  timeline: Timeline
  relay: RelayState
  error: DaemonError | null
  /** Why the daemon stopped sending, if it did. */
  ended: string | null
  /** Throw away the rows without touching the subscription. */
  clear: () => void
  /** Subscribe again after a failure, which also restarts the relay. */
  restart: () => void
}

/**
 * How long a batch is held before it reaches React.
 *
 * A chatty app produces frames far faster than anyone reads them, and a
 * `setState` per frame re-renders the feed per frame. The Mac coalesces on the
 * same 16 ms for the same reason: one frame's worth of latency is invisible,
 * and the alternative is a pane that stutters exactly when there is most to
 * look at.
 */
const FLUSH_MS = 16

/**
 * The relay's feed, folded into a timeline.
 *
 * Subscribing starts the relay and the last unsubscribe stops it, so the
 * cleanup here is load-bearing rather than tidiness: a subscription left behind
 * keeps a listener on port 9090, which is the port the *other* Reactotron would
 * want next.
 */
export function useReactotron(): ReactotronFeed {
  const [timeline, setTimeline] = useState<Timeline>(emptyTimeline)
  const [error, setError] = useState<DaemonError | null>(null)
  const [ended, setEnded] = useState<string | null>(null)
  const [generation, setGeneration] = useState(0)
  const subscription = useRef<Subscription | null>(null)
  // Frames wait here between flushes. A ref rather than state: adding to it
  // must not itself be a render.
  const pending = useRef<ReactotronFrame[]>([])
  const flush = useRef<ReturnType<typeof setTimeout> | null>(null)

  const clear = useCallback(() => {
    setTimeline((current) => cleared(current, null))
  }, [])

  const restart = useCallback(() => {
    setGeneration((current) => current + 1)
  }, [])

  useEffect(() => {
    // StrictMode runs this twice in development; without the flag the second
    // run's subscription replaces the first, which is then never stopped — and
    // an unstopped subscription holds the relay's port.
    let cancelled = false
    setEnded(null)
    setError(null)
    setTimeline(emptyTimeline())

    const drain = () => {
      flush.current = null
      const batch = pending.current
      if (batch.length === 0) return
      pending.current = []
      const at = Date.now()
      // One reduce, one render, however many frames arrived.
      setTimeline((current) => batch.reduce((folded, frame) => applyFrame(folded, frame, at), current))
    }

    const start = async () => {
      try {
        const live = await watchReactotron((update) => {
          switch (update.event) {
            case "batch":
              for (const frame of update.items) pending.current.push(frame)
              flush.current ??= setTimeout(drain, FLUSH_MS)
              break
            case "dropped":
              // Nothing to draw for this one. The timeline has its own caps and
              // trims from the front, so a gap marker placed mid-feed would
              // claim the loss happened somewhere it did not.
              break
            case "ended":
              setEnded(update.reason)
              break
            case "failed":
              setError({ code: "relay_failed", message: update.message, detail: null })
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
      } catch (thrown) {
        if (!cancelled) setError(asDaemonError(thrown))
      }
    }
    void start()

    return () => {
      cancelled = true
      if (flush.current !== null) clearTimeout(flush.current)
      flush.current = null
      pending.current = []
      const live = subscription.current
      subscription.current = null
      void live?.stop()
    }
  }, [generation])

  // Derived, not tracked. The timeline already knows both facts — it has a port
  // once the relay reported one, and a client list that is the authority on who
  // is there — so a second copy in state could only ever disagree with it.
  const relay: RelayState =
    error !== null || ended !== null
      ? "failed"
      : timeline.port === null
        ? "starting"
        : timeline.clients.length > 0
          ? "connected"
          : "listening"

  return { timeline, relay, error, ended, clear, restart }
}
