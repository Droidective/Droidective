import { useCallback, useEffect, useMemo, useRef, useState } from "react"

import { useConnectedDevices } from "@/hooks/useConnectedDevices"
import {
  autoColumns,
  canAdd,
  manualColumns,
  moved,
  quality,
  reconciled,
  toggled,
  type Quality,
} from "@/lib/mirror-wall"
import type { Device } from "@/lib/wire"

/** `auto` follows the pane width; a number is the user overruling it. */
export type ColumnMode = "auto" | number

export interface MirrorWallState {
  /** Every connected device, for the picker. */
  devices: Device[]
  /** The devices this wall is showing, in the order it shows them. */
  selection: string[]
  /** Whether another device can join, so the picker can say why not. */
  canAddMore: boolean
  toggle: (serial: string) => void
  reorder: (from: number, to: number) => void
  columns: number
  columnMode: ColumnMode
  setColumnMode: (mode: ColumnMode) => void
  /** What each tile should ask its device for, given how many there are. */
  quality: Quality
  /** Measures the grid, which is what the auto layout follows. */
  measure: (element: HTMLElement | null) => void
}

/**
 * The Mirror Wall's own state.
 *
 * It subscribes to the device list itself rather than taking the device bar's
 * selection, because that is what the wall *is* on the Mac: it picks its own
 * devices from a header menu and does not follow the bar. A second subscription
 * to a snapshot topic is cheap — the daemon serves every one of them from the
 * same `DeviceMonitor`.
 *
 * The arithmetic is all `lib/mirror-wall.ts`, which is a port of ADBKit's
 * `MirrorWall`; this only holds the pieces that need a lifetime.
 */
export function useMirrorWall(): MirrorWallState {
  const devices = useConnectedDevices()
  // `null` means nobody has picked yet, which is what fills the wall with the
  // connected devices on first open. An explicitly emptied selection is `[]`
  // and stays that way.
  const [picked, setPicked] = useState<string[] | null>(null)
  const [columnMode, setColumnMode] = useState<ColumnMode>("auto")
  const [paneWidth, setPaneWidth] = useState(0)

  const observer = useRef<ResizeObserver | null>(null)

  const connected = useMemo(() => devices.map((device) => device.serial), [devices])
  // Recomputed rather than stored, so a device leaving drops its tile without
  // anything having to notice the departure.
  const selection = useMemo(() => reconciled(picked, connected), [picked, connected])

  const measure = useCallback((element: HTMLElement | null) => {
    observer.current?.disconnect()
    if (element === null) {
      observer.current = null
      return
    }
    setPaneWidth(element.clientWidth)
    const watcher = new ResizeObserver((entries) => {
      const entry = entries[0]
      if (entry !== undefined) setPaneWidth(entry.contentRect.width)
    })
    watcher.observe(element)
    observer.current = watcher
  }, [])

  useEffect(() => () => observer.current?.disconnect(), [])

  return {
    devices,
    selection,
    canAddMore: canAdd(selection),
    columns:
      columnMode === "auto"
        ? autoColumns(paneWidth, selection.length)
        : manualColumns(columnMode, selection.length),
    columnMode,
    setColumnMode,
    // Every tile asks for the same thing, and it steps down as tiles are added:
    // a tile is a fraction of the pane, so full resolution is decode work
    // nobody can see.
    quality: quality(selection.length),
    measure,

    toggle: useCallback(
      (serial: string) => {
        // Against the *reconciled* list, not the stored one: toggling has to
        // act on what is on screen, and a stale entry for an unplugged device
        // would otherwise consume one of the six slots.
        setPicked((current) => toggled(serial, reconciled(current, connected)))
      },
      [connected],
    ),

    reorder: useCallback(
      (from: number, to: number) => {
        setPicked((current) => moved(reconciled(current, connected), from, to))
      },
      [connected],
    ),
  }
}
