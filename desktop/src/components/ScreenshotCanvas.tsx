import { useEffect, useRef, type PointerEvent as ReactPointerEvent } from "react"
import { canvasMeasurer, drawBlurRedactions, drawMarkup } from "@/lib/screenshot-draw"
import { drawCropOverlay, drawSelection } from "@/lib/screenshot-overlay"
import { handlePoints, rotationHandle } from "@/lib/screenshot-handles"
import type { Annotation, Point, Rect, Size } from "@/lib/screenshot-markup"
import type { EditorImage } from "@/hooks/useScreenshotEditor"

export interface CanvasProps {
  image: EditorImage
  /** The image's own pixel size — what the annotations are normalized to. */
  imageSize: Size
  /** Where it is drawn, in CSS pixels. */
  display: Size
  annotations: readonly Annotation[]
  draft: Annotation | null
  selected: Annotation | null
  cropRect: Rect | null
  cropRotation: number
  onPointerDown: (at: Point, display: Size) => void
  onPointerMove: (at: Point, display: Size) => void
  onPointerUp: (at: Point, display: Size) => void
}

/**
 * The picture and everything drawn on it.
 *
 * One canvas rather than a stack: the blur pass has to read the pixels beneath
 * it, which only works if the base image is already in the same context.
 * Everything is painted at the *display* size from normalized annotations, so
 * this is the same code path the export runs at full resolution.
 */
export function ScreenshotCanvas(props: CanvasProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null)

  useEffect(() => {
    const canvas = canvasRef.current
    if (canvas === null) return
    const ratio = globalThis.devicePixelRatio || 1
    canvas.width = Math.max(1, Math.round(props.display.width * ratio))
    canvas.height = Math.max(1, Math.round(props.display.height * ratio))
    const ctx = canvas.getContext("2d")
    if (ctx === null) return
    ctx.setTransform(ratio, 0, 0, ratio, 0, 0)
    ctx.clearRect(0, 0, props.display.width, props.display.height)
    paint(ctx, props)
  })

  return (
    <canvas
      ref={canvasRef}
      style={{ width: `${props.display.width}px`, height: `${props.display.height}px` }}
      className="touch-none select-none"
      onPointerDown={(event) => {
        // Capture, so a drag that leaves the canvas still reports its moves —
        // without it a stroke stops dead at the edge and the mouse-up never
        // arrives, leaving the editor mid-drag.
        event.currentTarget.setPointerCapture(event.pointerId)
        props.onPointerDown(normalize(event), props.display)
      }}
      onPointerMove={(event) => {
        props.onPointerMove(normalize(event), props.display)
      }}
      onPointerUp={(event) => {
        event.currentTarget.releasePointerCapture(event.pointerId)
        props.onPointerUp(normalize(event), props.display)
      }}
    />
  )
}

/** Where a pointer is, as a fraction of the image. */
function normalize(event: ReactPointerEvent<HTMLCanvasElement>): Point {
  const box = event.currentTarget.getBoundingClientRect()
  return {
    x: box.width === 0 ? 0 : (event.clientX - box.left) / box.width,
    y: box.height === 0 ? 0 : (event.clientY - box.top) / box.height,
  }
}

function paint(ctx: CanvasRenderingContext2D, props: CanvasProps): void {
  const size = props.display
  ctx.drawImage(props.image, 0, 0, size.width, size.height)
  drawBlurRedactions(ctx, props.image, props.annotations, props.draft, size)
  drawMarkup(ctx, props.annotations, props.draft, size)

  if (props.selected !== null) {
    const measure = canvasMeasurer(ctx)
    drawSelection(
      ctx,
      props.selected,
      size,
      handlePoints(props.selected, size, measure),
      rotationHandle(props.selected, size, measure),
    )
  }
  if (props.cropRect !== null) {
    drawCropOverlay(ctx, props.cropRect, props.cropRotation, size)
  }
}
