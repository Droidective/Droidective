import { useCallback, useEffect, useRef, useState } from "react"
import { asDaemonError, watchPerformance, type Subscription } from "@/lib/daemon"
import { timed, type PerfPhase, type TimedSample } from "@/lib/performance"
import type { DaemonError, PerfSample, StreamUpdate } from "@/lib/wire"

export interface Performance {
  /** Oldest first. A recording, not a rolling window. */
  samples: TimedSample[]
  latest: TimedSample | null
  phase: PerfPhase
  error: DaemonError | null
  /** How many samples the daemon's bounded buffer discarded, if any. */
  dropped: number

  /** Record → Pause → Resume, the Mac's one button. */
  toggleRecord: () => void
  stop: () => void
}

/**
 * A recording of one device's performance.
 *
 * Record-first, as `PerformanceView` is: nothing is sampled until Record, and
 * Pause really stops the sampling rather than hiding it — the subscription is
 * what keeps a `PerformanceService` reading `/proc` and `dumpsys` on the daemon
 * side, so leaving it up while paused would keep measuring a device nobody is
 * watching.
 */
export function usePerformance({
  serial,
  packageId,
  processes,
}: {
  serial: string | null
  packageId: string | null
  processes: boolean
}): Performance {
  const [samples, setSamples] = useState<TimedSample[]>([])
  const [phase, setPhase] = useState<PerfPhase>("idle")
  const [error, setError] = useState<DaemonError | null>(null)
  const [dropped, setDropped] = useState(0)
  const subscription = useRef<Subscription | null>(null)

  // A recording belongs to one device and one app; changing either ends it
  // rather than splicing two devices' numbers into one chart.
  useEffect(() => {
    setSamples([])
    setPhase("idle")
    setDropped(0)
  }, [serial, packageId, processes])

  useEffect(() => {
    if (phase !== "recording" || serial === null) return
    // StrictMode runs this twice in development; without the flag the second
    // run's subscription replaces the first, which is then never stopped.
    let cancelled = false
    setError(null)

    const onUpdate = (update: StreamUpdate<PerfSample>) => {
      switch (update.event) {
        case "batch":
          setSamples((current) => [
            ...current,
            ...update.items.map((item, offset) => timed(item, current.length + offset)),
          ])
          break
        case "dropped":
          // Never swallowed: a chart with a silent gap claims a continuity it
          // does not have, and the elapsed clock would understate the run.
          setDropped((current) => current + update.count)
          break
        case "ended":
          setPhase("paused")
          break
        case "failed":
          setError({ code: "stream_failed", message: update.message, detail: null })
          setPhase("paused")
          break
        default:
          break
      }
    }

    void (async () => {
      try {
        const live = await watchPerformance({ serial, packageId, processes }, onUpdate)
        if (cancelled) {
          void live.stop()
          return
        }
        subscription.current = live
      } catch (thrown) {
        if (!cancelled) {
          setError(asDaemonError(thrown))
          setPhase("idle")
        }
      }
    })()

    return () => {
      cancelled = true
      const live = subscription.current
      subscription.current = null
      void live?.stop()
    }
  }, [phase, serial, packageId, processes])

  return {
    samples,
    latest: samples.at(-1) ?? null,
    phase,
    error,
    dropped,

    toggleRecord: useCallback(() => {
      setPhase((current) => (current === "recording" ? "paused" : "recording"))
    }, []),
    stop: useCallback(() => {
      setPhase("idle")
    }, []),
  }
}
