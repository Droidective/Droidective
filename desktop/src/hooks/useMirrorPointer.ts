import { useCallback, useRef, type PointerEvent, type RefObject, type WheelEvent } from "react"

import { injectScroll, injectTouch, pointFromPointer } from "@/lib/scrcpy-control"

/** The handlers a mirror surface needs, ready to spread onto the element. */
export interface MirrorPointer {
  onPointerDown: (event: PointerEvent<HTMLElement>) => void
  onPointerMove: (event: PointerEvent<HTMLElement>) => void
  onPointerUp: (event: PointerEvent<HTMLElement>) => void
  onWheel: (event: WheelEvent<HTMLElement>) => void
}

/**
 * Turns pointer events on the video into scrcpy touches.
 *
 * Its own hook rather than four callbacks in the pane, because the state that
 * makes a drag work — whether the button is down — belongs to the gesture and
 * nothing else in the pane reads it.
 */
export function useMirrorPointer(
  surface: RefObject<HTMLElement | null>,
  video: { width: number; height: number },
  send: (bytes: Uint8Array) => void,
): MirrorPointer {
  // Whether the button is down, so a move only counts mid-drag and a release
  // is only sent for a press that actually happened.
  const pressed = useRef(false)

  const pointAt = useCallback(
    (event: { clientX: number; clientY: number }) => {
      const box = surface.current?.getBoundingClientRect()
      if (box === undefined) return null
      return pointFromPointer(event, box, video)
    },
    [surface, video],
  )

  return {
    onPointerDown: useCallback(
      (event: PointerEvent<HTMLElement>) => {
        const point = pointAt(event)
        if (point === null) return
        // Capture, so a drag that leaves the element keeps reporting — without
        // it a swipe off the edge never lifts and the device stays held.
        event.currentTarget.setPointerCapture(event.pointerId)
        pressed.current = true
        send(injectTouch("down", point))
      },
      [pointAt, send],
    ),

    onPointerMove: useCallback(
      (event: PointerEvent<HTMLElement>) => {
        if (!pressed.current) return
        const point = pointAt(event)
        if (point !== null) send(injectTouch("move", point))
      },
      [pointAt, send],
    ),

    onPointerUp: useCallback(
      (event: PointerEvent<HTMLElement>) => {
        if (!pressed.current) return
        pressed.current = false
        const point = pointAt(event)
        if (point !== null) send(injectTouch("up", point))
      },
      [pointAt, send],
    ),

    onWheel: useCallback(
      (event: WheelEvent<HTMLElement>) => {
        const point = pointAt(event)
        if (point === null) return
        // Normalised to the -1…1 the protocol carries; the sign is what decides
        // the direction, so it rides through rather than being taken as a size.
        send(
          injectScroll(point, {
            horizontal: wheelFraction(event.deltaX),
            vertical: wheelFraction(-event.deltaY),
          }),
        )
      },
      [pointAt, send],
    ),
  }
}

/** A wheel delta as the -1…1 fraction the protocol carries. */
function wheelFraction(delta: number): number {
  if (delta === 0) return 0
  return Math.max(-1, Math.min(1, delta / 100))
}
