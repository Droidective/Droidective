import { useMemo, useRef } from "react"

/**
 * Drops the answer to a question nobody is asking any more.
 *
 * Every per-device request hook has the same shape: a `load` keyed on the
 * serial, and an effect that clears the pane and calls it when the serial
 * changes. Nothing checked that the answer still belonged to the device on
 * screen, so a `load()` for device A that resolved after the switch to B wrote
 * A's data into B's pane — eight hooks and panes did this. Developer Settings
 * was the worst of them: its optimistic toggle builds from whatever table is
 * displayed and writes with the *current* serial, so a stale table on screen
 * meant flipping a toggle issued `settings put` against a different device.
 * That is an unintended write to someone's phone, not a display glitch.
 *
 * The codebase already had the idea twice, hand-rolled — `MeminfoPane`'s `let
 * live = true` and `usePerformance`'s `cancelled`. This is the same idea as
 * one thing, because eight copies of a three-line flag is eight chances to put
 * the check on the wrong side of an `await`.
 *
 * ```ts
 * const request = useLatestRequest()
 *
 * const load = useCallback(async () => {
 *   if (serial === null) return
 *   const current = request.begin()
 *   const next = await wifi(serial)
 *   if (!current()) return          // the device changed while we waited
 *   setData(next)
 * }, [request, serial])
 *
 * useEffect(() => {
 *   request.restart()
 *   setData(null)
 *   void load()
 * }, [load, request])
 * ```
 *
 * `restart` covers the refresh button too, which the hand-rolled effect flags
 * did not: a refresh answered after a device switch is the same stale write.
 *
 * The returned object is stable for the life of the component, so it can sit
 * in a dependency array without re-running anything.
 */
export interface LatestRequest {
  /** The question changed — abandon every answer still in flight. */
  restart: () => void
  /**
   * Take a token for the request being made now. Call the returned predicate
   * after every `await` and before touching state; it is false once `restart`
   * has been called.
   */
  begin: () => () => boolean
}

export function useLatestRequest(): LatestRequest {
  const generation = useRef(0)
  return useMemo(
    () => ({
      restart: () => {
        generation.current += 1
      },
      begin: () => {
        const mine = generation.current
        return () => generation.current === mine
      },
    }),
    [],
  )
}
