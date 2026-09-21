import { useCallback, useMemo, useRef } from "react"

import { useNotifications } from "@/hooks/useNotifications"
import { useRowPicking, type Modifiers } from "@/hooks/useRowPicking"
import { consoleJson } from "@/lib/console-export"
import { rowText, type ConsoleRow } from "@/lib/console-feed"
import { asDaemonError, copyText } from "@/lib/daemon"

export interface ConsoleSelection {
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
 * Picking rows out of the JS Console, and copying them.
 *
 * The gestures are `useRowPicking`, shared with the Reactotron timeline the way
 * the Mac shares `RowSelection` between the two screens. What is here is only
 * what a copy of *console* rows produces.
 */
export function useConsoleSelection(shown: readonly ConsoleRow[]): ConsoleSelection {
  const { show } = useNotifications()
  const order = useMemo(() => shown.map((row) => row.id), [shown])

  // The picked ids and the rows behind them, read through refs so the copy
  // handed to `useRowPicking` can be stable. It gates a keydown listener, and a
  // new function on every render would tear that listener down and rebuild it
  // on every incoming log line.
  const latest = useRef({ shown, show, picked: [] as number[] })
  latest.current.shown = shown
  latest.current.show = show

  const copyPicked = useCallback((asJson: boolean) => {
    const ids = new Set(latest.current.picked)
    const rows = latest.current.shown.filter((row) => ids.has(row.id))
    if (rows.length === 0) return
    copyRows(rows, asJson, latest.current.show)
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
