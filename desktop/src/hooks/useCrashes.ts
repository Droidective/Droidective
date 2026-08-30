import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import { useCrashBuffer } from "@/hooks/useCrashBuffer"
import { useNotifications } from "@/hooks/useNotifications"
import { asDaemonError, clearCrashes } from "@/lib/daemon"
import { systemTitle } from "@/lib/notifications"
import {
  filterCrashes,
  keptSelection,
  markAfterClear,
  unclearedCrashes,
  type ClearMark,
  type CrashFilters,
} from "@/lib/crashes"
import type { CrashReport, DaemonError } from "@/lib/wire"

/** Why the list is empty, which is three different situations. */
export type CrashPhase = "checking" | "empty" | "failed" | "ready"

export interface Crashes {
  /** Everything not hidden by a Clear Buffer. */
  visible: CrashReport[]
  /** `visible` narrowed by the filters — what the list shows. */
  shown: CrashReport[]
  filters: CrashFilters
  selected: CrashReport | null
  phase: CrashPhase
  loading: boolean
  watching: boolean
  error: DaemonError | null
  /** The crash Watch spotted arriving, until it is dismissed. */
  arrival: CrashReport | null
  notice: string | null

  refresh: () => void
  setFilters: (filters: CrashFilters) => void
  select: (id: string) => void
  setWatching: (on: boolean) => void
  clear: () => void
  dismiss: () => void
}

/**
 * One device's crashes, and what is being done with them.
 *
 * Every rule this leans on is in `lib/crashes.ts` — what a Clear Buffer keeps
 * hiding, which filters survive a refresh, what stays selected, what counts as
 * a new arrival. This composes them over `useCrashBuffer`'s fetching.
 */
export function useCrashes(serial: string | null): Crashes {
  const buffer = useCrashBuffer(serial)
  const [selectedID, setSelectedID] = useState<string | null>(null)
  const [cleared, setCleared] = useState<ClearMark | null>(null)
  const [notice, setNotice] = useState<string | null>(null)

  useEffect(() => {
    setSelectedID(null)
    setCleared(null)
    setNotice(null)
  }, [serial])

  const visible = useMemo(
    () => unclearedCrashes(buffer.crashes, serial, cleared),
    [buffer.crashes, serial, cleared],
  )
  const shown = useMemo(() => filterCrashes(visible, buffer.filters), [visible, buffer.filters])

  // Keep something selected as filters and refreshes move the list around.
  const kept = keptSelection(selectedID, shown)
  useEffect(() => {
    setSelectedID(kept)
  }, [kept])

  useArrivalNotice(buffer.arrival)
  const clear = useClearBuffer({ serial, buffer, setCleared, setSelectedID, setNotice })

  return {
    visible,
    shown,
    filters: buffer.filters,
    selected: shown.find((crash) => crash.id === kept) ?? null,
    phase: phaseOf(buffer.failed, buffer.fetched, shown.length),
    loading: buffer.loading,
    watching: buffer.watching,
    error: buffer.error,
    arrival: buffer.arrival,
    notice,

    refresh: buffer.refresh,
    setFilters: buffer.setFilters,
    select: setSelectedID,
    setWatching: buffer.setWatching,
    clear,
    dismiss: useCallback(() => {
      buffer.setArrival(null)
      buffer.setError(null)
      setNotice(null)
    }, [buffer]),
  }
}

/**
 * Say it outside the window too.
 *
 * Watch is the one thing on this screen someone leaves running while they go
 * and use the app they are debugging — which is the whole point of it — so a
 * crash arriving has to reach them where they are. The Mac announces the same
 * arrival as an error toast and mirrors error toasts to the tray, so both apps
 * put the same two lines there.
 *
 * The strip in the toolbar stays: it is this screen's own record of what
 * arrived, and unlike a notification it is still there four minutes later.
 */
function useArrivalNotice(arrival: CrashReport | null) {
  const { notifyIfBackgrounded } = useNotifications()
  // Which crash has been announced, so a re-render cannot announce it twice.
  const announced = useRef<string | null>(null)
  useEffect(() => {
    if (arrival === null || announced.current === arrival.id) return
    announced.current = arrival.id
    notifyIfBackgrounded(systemTitle("error"), `New crash: ${arrival.title}`, true)
  }, [arrival, notifyIfBackgrounded])
}

/**
 * "No crashes" and "couldn't read" and "still reading" look the same on screen
 * unless the empty state distinguishes them, and a failure that reads as
 * "still checking" never resolves.
 */
function phaseOf(failed: boolean, fetched: boolean, shown: number): CrashPhase {
  if (failed) return "failed"
  if (shown > 0) return "ready"
  return fetched ? "empty" : "checking"
}

/**
 * Clear Buffer: empty the device's crash buffer, then remember where the line
 * was so the main-buffer fallback cannot resurface what was just cleared.
 */
function useClearBuffer({
  serial,
  buffer,
  setCleared,
  setSelectedID,
  setNotice,
}: {
  serial: string | null
  buffer: ReturnType<typeof useCrashBuffer>
  setCleared: (mark: ClearMark | null) => void
  setSelectedID: (id: string | null) => void
  setNotice: (notice: string | null) => void
}): () => void {
  const { latest, refresh, setError } = buffer
  return useCallback(() => {
    if (serial === null) return
    setNotice(null)
    void (async () => {
      try {
        const result = await clearCrashes(serial)
        if (!result.ok) {
          setError({ code: "clear_failed", message: result.message, detail: null })
          return
        }
        setCleared(markAfterClear(serial, latest.current))
        setSelectedID(null)
        setNotice(result.message)
        refresh()
      } catch (thrown) {
        setError(asDaemonError(thrown))
      }
    })()
  }, [serial, latest, refresh, setError, setCleared, setSelectedID, setNotice])
}
