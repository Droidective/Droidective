import { useCallback, useEffect, useRef, useState } from "react"
import { asDaemonError, listCrashes } from "@/lib/daemon"
import {
  newestUnseen,
  NO_FILTERS,
  prunedFilters,
  sameCrashes,
  WATCH_INTERVAL_MS,
  type CrashFilters,
} from "@/lib/crashes"
import type { CrashReport, DaemonError } from "@/lib/wire"

/** Reading the device's crash buffer, and keeping it read. */
export interface CrashBuffer {
  crashes: CrashReport[]
  filters: CrashFilters
  /** A fetch has come back at least once, so "empty" means empty. */
  fetched: boolean
  /** The last fetch failed. The previous list is kept, but this says so. */
  failed: boolean
  loading: boolean
  watching: boolean
  error: DaemonError | null
  /** The crash a Watch poll spotted arriving, until it is dismissed. */
  arrival: CrashReport | null

  setFilters: (filters: CrashFilters) => void
  setWatching: (on: boolean) => void
  setArrival: (crash: CrashReport | null) => void
  setError: (error: DaemonError | null) => void
  refresh: () => void
  /** The current list, without re-rendering to read it. */
  latest: { current: CrashReport[] }
}

/**
 * Split from `useCrashes` for the reason the file explorer's two hooks are:
 * this is fetching and a timer, that is selection and clearing, and they
 * change for different reasons.
 */
export function useCrashBuffer(serial: string | null): CrashBuffer {
  const [crashes, setCrashes] = useState<CrashReport[]>([])
  const [filters, setFilters] = useState<CrashFilters>(NO_FILTERS)
  const [fetched, setFetched] = useState(false)
  const [failed, setFailed] = useState(false)
  const [loading, setLoading] = useState(false)
  const [watching, setWatching] = useState(false)
  const [error, setError] = useState<DaemonError | null>(null)
  const [arrival, setArrival] = useState<CrashReport | null>(null)
  const [generation, setGeneration] = useState(0)

  // Read through a ref so a poll's identity does not change every render.
  const latest = useRef(crashes)
  latest.current = crashes

  useEffect(() => {
    setCrashes([])
    setFilters(NO_FILTERS)
    setFetched(false)
    setFailed(false)
    setArrival(null)
  }, [serial])

  const fetch = useCallback(
    async (announce: boolean) => {
      if (serial === null) return
      try {
        const next = (await listCrashes(serial)).crashes
        setError(null)
        setFailed(false)
        setFetched(true)
        if (announce) {
          // Only *set* it. Writing the miss back too would have the next poll
          // clear the announcement five seconds after it appeared, which is
          // long enough to see out of the corner of an eye and not read.
          const arrived = newestUnseen(latest.current, next)
          if (arrived !== null) setArrival(arrived)
        }
        // A watch poll mostly returns the same list; writing it back would
        // re-render the trace every five seconds for nothing.
        if (!sameCrashes(latest.current, next)) setCrashes(next)
        setFilters((current) => prunedFilters(current, next))
      } catch (thrown) {
        // Keep the last good list, but say so — a swallowed poll failure reads
        // as "still checking" forever.
        setFailed(true)
        setError(asDaemonError(thrown))
      }
    },
    [serial],
  )

  useEffect(() => {
    if (serial === null) return
    let live = true
    setLoading(true)
    void fetch(false).finally(() => {
      if (live) setLoading(false)
    })
    return () => {
      live = false
    }
  }, [serial, fetch, generation])

  useEffect(() => {
    if (!watching || serial === null) return
    const timer = globalThis.setInterval(() => {
      void fetch(true)
    }, WATCH_INTERVAL_MS)
    return () => {
      globalThis.clearInterval(timer)
    }
  }, [watching, serial, fetch])

  return {
    crashes,
    filters,
    fetched,
    failed,
    loading,
    watching,
    error,
    arrival,
    setFilters,
    setWatching,
    setArrival,
    setError,
    refresh: useCallback(() => {
      setGeneration((current) => current + 1)
    }, []),
    latest,
  }
}
