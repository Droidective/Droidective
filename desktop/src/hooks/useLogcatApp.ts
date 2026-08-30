import { useEffect, useRef, useState } from "react"
import { logcatPid } from "@/lib/daemon"
import {
  APP_FILTER_OFF,
  nextAppFilter,
  pollDelayMs,
  streamPid,
  type AppFilter,
} from "@/lib/logcat-app"

/**
 * Which process the log should be narrowed to, kept current.
 *
 * The Mac's `streamLoop` pid half, minus the streaming: it re-reads the app's
 * pid on a timer, waits when the app is not running, and follows it to a new
 * pid when it relaunches. Every decision it makes is `lib/logcat-app.ts`, which
 * is where they are tested — this is the timer and the request.
 *
 * The pid it reports is what the subscription carries, so the caller re-keys
 * its stream on it.
 */
export function useLogcatApp(serial: string | null, packageId: string | null): AppFilter {
  const [filter, setFilter] = useState<AppFilter>(APP_FILTER_OFF)
  // Read inside the timer without making it a dependency: including the filter
  // would tear down and rebuild the poll on every answer, including the ones
  // that changed nothing.
  const latest = useRef<AppFilter>(APP_FILTER_OFF)
  latest.current = filter

  useEffect(() => {
    if (serial === null || packageId === null) {
      setFilter(APP_FILTER_OFF)
      return
    }

    let cancelled = false
    let timer: ReturnType<typeof setTimeout> | undefined

    const poll = async () => {
      let resolved: number | null = null
      try {
        resolved = await logcatPid(serial, packageId)
      } catch {
        // A device that went away answers nothing. Treat it as "not running"
        // — the pane already says the device is gone, and a second error about
        // its pid would be noise.
        resolved = null
      }
      if (cancelled) return
      const next = nextAppFilter(latest.current, packageId, resolved)
      latest.current = next
      setFilter(next)
      const delay = pollDelayMs(next)
      if (delay !== null) timer = setTimeout(() => void poll(), delay)
    }

    void poll()
    return () => {
      cancelled = true
      if (timer !== undefined) clearTimeout(timer)
    }
  }, [serial, packageId])

  return filter
}

/** The pid a subscription should carry for this filter. Re-exported for callers. */
export { streamPid }
