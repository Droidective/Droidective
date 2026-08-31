import { useCallback, useEffect, useRef, useState } from "react"

/**
 * A draggable seam whose value survives a reopen.
 *
 * `@AppStorage` on the Mac; `localStorage` here, which is what this app
 * already uses for the appearance settings. The in-flight drag lives in state
 * and the commit happens once on release — the same two-value shape `RootView`
 * uses for its own seams, so a drag never writes a hundred times.
 */
export function useApiSeam(
  key: string,
  fallback: number,
): {
  value: number
  /** Start a drag from this pointer position. */
  begin: (clientPosition: number, resolve: (start: number, moved: number) => number) => void
  dragging: boolean
} {
  const [stored, setStored] = useState(() => read(key, fallback))
  const [live, setLive] = useState<number | null>(null)
  const drag = useRef<{
    origin: number
    start: number
    resolve: (start: number, moved: number) => number
  } | null>(null)

  useEffect(() => {
    if (live === null) return
    const move = (event: PointerEvent) => {
      const active = drag.current
      if (active === null) return
      setLive(active.resolve(active.start, event.clientX + event.clientY - active.origin))
    }
    const up = () => {
      setLive((settled) => {
        if (settled !== null) {
          setStored(settled)
          write(key, settled)
        }
        return null
      })
      drag.current = null
    }
    globalThis.addEventListener("pointermove", move)
    globalThis.addEventListener("pointerup", up)
    return () => {
      globalThis.removeEventListener("pointermove", move)
      globalThis.removeEventListener("pointerup", up)
    }
  }, [live, key])

  const begin = useCallback(
    (clientPosition: number, resolve: (start: number, moved: number) => number) => {
      drag.current = { origin: clientPosition, start: stored, resolve }
      setLive(stored)
    },
    [stored],
  )

  return { value: live ?? stored, begin, dragging: live !== null }
}

function read(key: string, fallback: number): number {
  try {
    const raw = globalThis.localStorage.getItem(key)
    if (raw === null) return fallback
    const parsed = Number(raw)
    return Number.isFinite(parsed) ? parsed : fallback
  } catch {
    return fallback
  }
}

function write(key: string, value: number) {
  try {
    globalThis.localStorage.setItem(key, String(value))
  } catch {
    // A private window or a locked profile: the seam still works, it just
    // starts where it started next time. Not worth a message.
  }
}
