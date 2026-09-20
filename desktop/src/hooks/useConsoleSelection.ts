import { useCallback, useEffect, useMemo, useRef, useState } from "react"

import { useNotifications } from "@/hooks/useNotifications"
import { consoleJson } from "@/lib/console-export"
import { rowText, type ConsoleRow } from "@/lib/console-feed"
import { asDaemonError, copyText } from "@/lib/daemon"
import { hasModifier } from "@/lib/platform"
import {
  emptySelection,
  extend,
  isEmpty,
  retain,
  selectRange,
  toggle,
  type RowSelection,
} from "@/lib/row-selection"

export interface ConsoleSelection {
  count: number
  has: (id: number) => boolean
  /** A row's pointer-down: the modifiers decide, and a drag may follow. */
  onPointerDown: (id: number, event: { ctrlKey: boolean; metaKey: boolean; shiftKey: boolean }) => void
  /** The pointer moving onto a row while the button is down. */
  onPointerEnter: (id: number) => void
  /**
   * True while a drag is sweeping rows.
   *
   * The feed turns text selection off for the duration: without it the browser
   * selects the *text* under the sweep at the same time, and two selections
   * fight over one gesture.
   */
  dragging: boolean
  copy: () => void
  copyAsJson: () => void
  clear: () => void
}

/**
 * Picking rows out of the console, and copying them.
 *
 * **A plain click clears rather than selects**, which is the Mac's rule and not
 * an omission: a row is something you click to read, so selection is the
 * deliberate gesture — Ctrl-click for one, Shift-click or a drag for a range.
 * Where the Mac says ⌘ this says Ctrl, the standing shortcut exception.
 */
export function useConsoleSelection(shown: readonly ConsoleRow[]): ConsoleSelection {
  const { show } = useNotifications()
  const [selection, setSelection] = useState<RowSelection<number>>(emptySelection)
  const order = useMemo(() => shown.map((row) => row.id), [shown])
  /** The row a drag began on, while the button is still down. */
  const dragFrom = useRef<number | null>(null)
  /** Set when a drag actually swept, so the click that ends it does not clear. */
  const swept = useRef(false)
  const [dragging, setDragging] = useState(false)

  // Rows leave the feed — trimmed, filtered out, cleared — and a selection that
  // kept them would count and copy events the reader cannot see.
  useEffect(() => {
    setSelection((current) => retain(current, order))
  }, [order])

  useWhileDragging(dragFrom, setDragging)

  const onPointerDown = useCallback(
    (id: number, event: { ctrlKey: boolean; metaKey: boolean; shiftKey: boolean }) => {
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

  const copyPicked = useCallback(
    (asJson: boolean) => {
      const rows = shown.filter((row) => selection.ids.has(row.id))
      if (rows.length === 0) return
      copyRows(rows, asJson, show)
    },
    [selection, shown, show],
  )

  const copy = useCallback(() => {
    copyPicked(false)
  }, [copyPicked])
  const copyAsJson = useCallback(() => {
    copyPicked(true)
  }, [copyPicked])

  useCopyShortcut(!isEmpty(selection), copy)

  return {
    count: selection.ids.size,
    has: (id) => selection.ids.has(id),
    onPointerDown,
    onPointerEnter,
    dragging,
    copy,
    copyAsJson,
    clear,
  }
}

/**
 * Put the picked rows on the clipboard and say how many went.
 *
 * Blank lines between entries for the plain copy, as the Mac joins them: a
 * console line can wrap, so single newlines would read as one long event.
 */
function copyRows(
  rows: readonly ConsoleRow[],
  asJson: boolean,
  show: (outcome: { ok: boolean; message: string }) => void,
): void {
  const text = asJson ? consoleJson(rows) : rows.map((row) => rowText(row)).join("\n\n")
  const what = asJson ? "logs as JSON" : "logs"
  copyText(text).then(
    () => {
      show({ message: `Copied ${String(rows.length)} ${what}`, ok: true })
    },
    (thrown: unknown) => {
      show({ message: `Copy failed: ${asDaemonError(thrown).message}`, ok: false })
    },
  )
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
 * The Mac's reason: bound unconditionally it shadows copying text out of the
 * prompt, the filter, or a line someone highlighted with the mouse.
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
