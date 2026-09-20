import { useCallback, useMemo, useRef } from "react"

import { useRowPicking, type Modifiers } from "@/hooks/useRowPicking"
import { copyEventsAsJson, copyLine } from "@/lib/reactotron-copy"
import type { TimelineRow } from "@/lib/reactotron-rows"

export interface ReactotronSelection {
  count: number
  has: (id: number) => boolean
  onPointerDown: (id: number, event: Modifiers) => void
  onPointerEnter: (id: number) => void
  dragging: boolean
  copy: () => void
  copyAsJson: () => void
  clear: () => void
}

/**
 * Picking rows out of the timeline, and copying them.
 *
 * The gestures are `useRowPicking`, shared with the JS Console because the Mac
 * shares `RowSelection` between the two screens. Only the copy differs: a
 * timeline row copies as the line you can read, or as the frames the app sent
 * — the same two verbs `copyLine` and `copyEventsAsJson` already back.
 */
export function useReactotronSelection(
  rows: readonly TimelineRow[],
  onCopy: (text: string, count: number, asJson: boolean) => void,
): ReactotronSelection {
  const order = useMemo(() => rows.map((row) => row.id), [rows])

  // Read through a ref so the copy handed to `useRowPicking` stays stable: it
  // gates a keydown listener, and a new function per render would rebuild that
  // listener on every frame the app sends.
  const latest = useRef({ rows, onCopy, picked: [] as number[] })
  latest.current.rows = rows
  latest.current.onCopy = onCopy

  const copyPicked = useCallback((asJson: boolean) => {
    const ids = new Set(latest.current.picked)
    const picked = latest.current.rows.filter((row) => ids.has(row.id))
    if (picked.length === 0) return
    // Blank lines between entries, as the Mac joins them: a timeline line can
    // wrap, so single newlines would read as one long event.
    const text = asJson
      ? copyEventsAsJson(picked)
      : picked.map((row) => copyLine(row)).join("\n\n")
    latest.current.onCopy(text, picked.length, asJson)
  }, [])

  const copy = useCallback(() => {
    copyPicked(false)
  }, [copyPicked])
  const copyAsJson = useCallback(() => {
    copyPicked(true)
  }, [copyPicked])

  const picking = useRowPicking(order, copy)
  latest.current.picked = picking.picked

  return {
    count: picking.count,
    has: picking.has,
    onPointerDown: picking.onPointerDown,
    onPointerEnter: picking.onPointerEnter,
    dragging: picking.dragging,
    copy,
    copyAsJson,
    clear: picking.clear,
  }
}
