import { useCallback, useRef, useState } from "react"
import { extendDraft, startDraft, type DrawSettings } from "@/lib/screenshot-editor"
import {
  clampCrop,
  cropGrab,
  moveCrop,
  resizeCrop,
  rotateCrop,
  type CropGrab,
} from "@/lib/screenshot-crop"
import {
  handlePoints,
  hitTest,
  moved,
  resizing,
  rotated,
  rotationHandle,
} from "@/lib/screenshot-handles"
import { rectBetween, type Annotation, type Point, type Rect, type Size } from "@/lib/screenshot-markup"

/** How near, in display pixels, a pointer must be to take hold of a handle. */
const GRAB_TOLERANCE = 9

/** How near a click must be to a stroke to pick it. */
const PICK_TOLERANCE = 8

export type Mode = "draw" | "select" | "crop"

interface Grab {
  kind: "move" | "handle" | "rotate"
  index: number
  from: Point
  original: Annotation
}

export interface Gestures {
  draft: Annotation | null
  down: (at: Point, display: Size) => void
  move: (at: Point, display: Size) => void
  up: (at: Point, display: Size) => void
}

export interface GestureHost {
  mode: Mode
  settings: DrawSettings
  annotations: readonly Annotation[]
  selectedID: string | null
  onSelect: (id: string | null) => void
  /** A finished shape, or a text point to type at. */
  onCommit: (draft: Annotation) => void
  onPlaceText: (at: Point) => void
  onReplace: (annotation: Annotation, recordUndo: boolean) => void
  cropRect: Rect | null
  cropRotation: number
  onCrop: (rect: Rect | null, rotation: number) => void
}

/**
 * What the pointer does on the canvas, in each of the three modes.
 *
 * Kept out of the components because it is the part with hidden state — a
 * half-drawn shape, a handle being held — and because each mode's rules are
 * the Mac's: a drag draws, a click in select mode picks the top-most thing
 * under it, and a crop box is drawn, moved, resized or turned depending on
 * what the pointer went down on.
 */
export function useScreenshotGestures(host: GestureHost): Gestures {
  const [draft, setDraft] = useState<Annotation | null>(null)
  const grab = useRef<Grab | null>(null)
  const crop = useRef<{ grab: CropGrab; from: Point; original: Rect } | null>(null)
  const drawing = useRef(false)

  const selected = host.annotations.find((a) => a.id === host.selectedID) ?? null

  const down = useCallback(
    (at: Point, display: Size) => {
      if (host.mode === "crop") {
        crop.current = beginCrop(at, display, host)
        return
      }
      if (host.mode === "select") {
        grab.current = beginGrab(at, display, host, selected)
        return
      }
      if (host.settings.tool === "text") {
        host.onPlaceText(at)
        return
      }
      drawing.current = true
      setDraft(startDraft(host.settings, at))
    },
    [host, selected],
  )

  const move = useCallback(
    (at: Point, display: Size) => {
      if (host.mode === "crop") {
        applyCropDrag(at, display, host, crop.current)
        return
      }
      if (host.mode === "select") {
        applyGrab(at, display, host, grab.current)
        return
      }
      if (!drawing.current) return
      setDraft((current) => (current === null ? null : extendDraft(current, at)))
    },
    [host],
  )

  const up = useCallback(
    (at: Point, display: Size) => {
      if (host.mode === "crop") {
        applyCropDrag(at, display, host, crop.current)
        crop.current = null
        return
      }
      if (host.mode === "select") {
        applyGrab(at, display, host, grab.current)
        grab.current = null
        return
      }
      drawing.current = false
      setDraft((current) => {
        if (current !== null) host.onCommit(extendDraft(current, at))
        return null
      })
    },
    [host],
  )

  return { draft, down, move, up }
}

function beginCrop(at: Point, display: Size, host: GestureHost) {
  if (host.cropRect !== null) {
    const grabbed = cropGrab(
      { x: at.x * display.width, y: at.y * display.height },
      host.cropRect,
      host.cropRotation,
      display,
      GRAB_TOLERANCE,
    )
    if (grabbed.kind !== "none") {
      return { grab: grabbed, from: at, original: host.cropRect }
    }
  }
  // Nothing grabbed: this drag draws a new box from here.
  const fresh = { x: at.x, y: at.y, width: 0, height: 0 }
  host.onCrop(fresh, 0)
  return { grab: { kind: "corner", index: 2 } as CropGrab, from: at, original: fresh }
}

function applyCropDrag(
  at: Point,
  display: Size,
  host: GestureHost,
  state: { grab: CropGrab; from: Point; original: Rect } | null,
): void {
  if (state === null) return
  switch (state.grab.kind) {
    case "move":
      host.onCrop(
        moveCrop(state.original, { x: at.x - state.from.x, y: at.y - state.from.y }),
        host.cropRotation,
      )
      break
    case "rotate":
      host.onCrop(host.cropRect, rotateCrop(state.original, at, display))
      break
    case "corner":
      // A box drawn from nothing has no anchor to resize from, so the first
      // drag spans the two points directly.
      host.onCrop(
        state.original.width === 0 && state.original.height === 0
          ? clampCrop(rectBetween(state.from, at))
          : resizeCrop(state.original, state.grab.index, at, host.cropRotation, display),
        host.cropRotation,
      )
      break
    case "none":
      break
  }
}

function beginGrab(
  at: Point,
  display: Size,
  host: GestureHost,
  selected: Annotation | null,
): Grab | null {
  const px = { x: at.x * display.width, y: at.y * display.height }
  if (selected !== null) {
    const spin = rotationHandle(selected, display)
    if (spin !== null && near(px, spin, display)) {
      return { kind: "rotate", index: 0, from: at, original: selected }
    }
    const handles = handlePoints(selected, display)
    for (const [index, handle] of handles.entries()) {
      if (near(px, handle, display)) return { kind: "handle", index, from: at, original: selected }
    }
  }
  const index = hitTest(host.annotations, px, display, PICK_TOLERANCE)
  if (index === null) {
    host.onSelect(null)
    return null
  }
  const picked = host.annotations[index]
  if (picked === undefined) return null
  host.onSelect(picked.id)
  return { kind: "move", index: 0, from: at, original: picked }
}

function applyGrab(at: Point, display: Size, host: GestureHost, grab: Grab | null): void {
  if (grab === null) return
  switch (grab.kind) {
    case "move":
      host.onReplace(moved(grab.original, { x: at.x - grab.from.x, y: at.y - grab.from.y }), false)
      break
    case "handle":
      host.onReplace(resizing(grab.original, grab.index, at, display), false)
      break
    case "rotate":
      host.onReplace(rotated(grab.original, at, display), false)
      break
  }
}

function near(px: Point, handle: Point, display: Size): boolean {
  return (
    Math.hypot(px.x - handle.x * display.width, px.y - handle.y * display.height) <= GRAB_TOLERANCE
  )
}
