import { useCallback, useEffect, useMemo, useRef, useState } from "react"

import { hasModifier } from "@/lib/platform"
import {
  emptySelection,
  extend,
  isEmpty,
  ordered,
  retain,
  selectRange,
  toggle,
  type RowSelection,
} from "@/lib/row-selection"

/** The modifiers a pointer-down carried — a `PointerEvent`, or a stand-in. */
export interface Modifiers {
  ctrlKey: boolean
  metaKey: boolean
  shiftKey: boolean
}

export interface RowPicking {
  count: number
  has: (id: number) => boolean
  /** The picked ids in display order, which is what a copy needs. */
  picked: number[]
  /** A row's pointer-down: the modifiers decide, and a drag may follow. */
  onPointerDown: (id: number, event: Modifiers) => void
  /** The pointer moving onto a row while the button is down. */
  onPointerEnter: (id: number) => void
  /**
   * True while a drag is sweeping rows.
   *
   * A feed turns text selection off for the duration: without it the browser
   * selects the *text* under the sweep at the same time, and two selections
   * fight over one gesture.
   */
  dragging: boolean
  clear: () => void
}

/**
 * Picking rows out of a feed: the gestures, and the shortcut that copies them.
 *
 * Shared because the Mac shares it — `RowSelection` backs both the JS Console
 * and the Reactotron timeline, and the two screens differ only in what a copy
 * produces, which is why `copy` is a parameter rather than something this
 * knows. Where the Mac says ⌘ this says Ctrl, the standing shortcut exception.
 *
 * **A plain click clears rather than selects.** That is the Mac's rule and not
 * an omission: a row is something you click to read or expand, so picking is
 * the deliberate gesture — Ctrl-click for one, Shift-click or a drag for a
 * range.
 */
export function useRowPicking(order: readonly number[], copy: () => void): RowPicking {
  const [selection, setSelection] = useState<RowSelection<number>>(emptySelection)
  /** The row a drag began on, while the button is still down. */
  const dragFrom = useRef<number | null>(null)
  /** Set when a drag actually swept, so the click that ends it does not clear. */
  const swept = useRef(false)
  const [dragging, setDragging] = useState(false)

  // Rows leave a feed — trimmed, filtered out, cleared — and a selection that
  // kept them would count and copy events the reader cannot see.
  useEffect(() => {
    setSelection((current) => retain(current, order))
  }, [order])

  useWhileDragging(dragFrom, setDragging)
  useCopyShortcut(!isEmpty(selection), copy)

  const onPointerDown = useCallback(
    (id: number, event: Modifiers) => {
      dragFrom.current = id
      if (event.shiftKey) {
        setSelection((current) => extend(current, id, order))
        return
      }
      if (event.ctrlKey || event.metaKey) {
        setSelection((current) => toggle(current, id))
        return
      }
      if (swept.current) {
        // The click that ended a sweep, not a new one.
        swept.current = false
        return
      }
      setSelection((current) => (isEmpty(current) ? current : emptySelection()))
    },
    [order],
  )

  const onPointerEnter = useCallback(
    (id: number) => {
      const from = dragFrom.current
      // Only once the pointer has left the row it went down on: otherwise a
      // plain click would select the row it landed on, and a plain click is
      // how you clear.
      if (from === null || from === id) return
      swept.current = true
      setDragging(true)
      setSelection((current) => selectRange(current, from, id, order))
    },
    [order],
  )

  const clear = useCallback(() => {
    setSelection(emptySelection())
  }, [])

  const picked = useMemo(() => ordered(selection, order), [selection, order])

  return {
    count: selection.ids.size,
    has: (id) => selection.ids.has(id),
    picked,
    onPointerDown,
    onPointerEnter,
    dragging,
    clear,
  }
}

/** Ends the sweep wherever the button comes up, inside the feed or outside it. */
function useWhileDragging(
  dragFrom: React.RefObject<number | null>,
  setDragging: (dragging: boolean) => void,
): void {
  useEffect(() => {
    const end = () => {
      dragFrom.current = null
      setDragging(false)
    }
    globalThis.addEventListener("pointerup", end)
    return () => {
      globalThis.removeEventListener("pointerup", end)
    }
  }, [dragFrom, setDragging])
}

/**
 * Ctrl+C, and **only while rows are picked**.
 *
 * The Mac's reason: bound unconditionally it shadows copying text out of a
 * prompt, a search field, or a line someone highlighted with the mouse.
 */
function useCopyShortcut(enabled: boolean, copy: () => void): void {
  useEffect(() => {
    if (!enabled) return
    const onKeyDown = (event: KeyboardEvent) => {
      if (!hasModifier(event) || event.shiftKey || event.altKey || event.key !== "c") return
      event.preventDefault()
      copy()
    }
    globalThis.addEventListener("keydown", onKeyDown)
    return () => {
      globalThis.removeEventListener("keydown", onKeyDown)
    }
  }, [enabled, copy])
}
