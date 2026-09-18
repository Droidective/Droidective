import { canvasMeasurer } from "@/lib/screenshot-draw"
import { bounds, midX, midY, type Annotation, type Rect, type Size } from "@/lib/screenshot-markup"

/**
 * The editor's furniture — the selection box and the crop box.
 *
 * Drawn on the same canvas as the markup rather than as DOM nodes, so it lands
 * in the same coordinate space as the thing it decorates: an overlay
 * positioned in CSS would have to repeat the rotation maths and could drift
 * from it.
 */

/** Half the side of a square handle, in display pixels. */
export const HANDLE_RADIUS = 5

/**
 * The selection furniture: a dashed box, its resize handles, and the rotation
 * handle above it.
 *
 * Drawn on the canvas rather than as DOM nodes so it lands in the same
 * coordinate space as the markup it decorates — an overlay positioned in CSS
 * would have to repeat the rotation maths and could drift from it.
 */
export function drawSelection(
  ctx: CanvasRenderingContext2D,
  a: Annotation,
  size: Size,
  handles: readonly { x: number; y: number }[],
  rotationAt: { x: number; y: number } | null,
): void {
  const b = bounds(a, size, canvasMeasurer(ctx))
  ctx.save()
  if (a.rotation !== 0) {
    ctx.translate(midX(b) * size.width, midY(b) * size.height)
    ctx.rotate(a.rotation)
    ctx.translate(-midX(b) * size.width, -midY(b) * size.height)
  }
  ctx.strokeStyle = "#6ecc1f"
  ctx.lineWidth = 1
  ctx.setLineDash([4, 3])
  ctx.strokeRect(
    b.x * size.width - 2,
    b.y * size.height - 2,
    b.width * size.width + 4,
    b.height * size.height + 4,
  )
  ctx.restore()

  ctx.save()
  ctx.setLineDash([])
  ctx.fillStyle = "#6ecc1f"
  ctx.strokeStyle = "#101010"
  ctx.lineWidth = 1
  for (const h of handles) {
    const x = h.x * size.width
    const y = h.y * size.height
    ctx.fillRect(x - HANDLE_RADIUS, y - HANDLE_RADIUS, HANDLE_RADIUS * 2, HANDLE_RADIUS * 2)
    ctx.strokeRect(x - HANDLE_RADIUS, y - HANDLE_RADIUS, HANDLE_RADIUS * 2, HANDLE_RADIUS * 2)
  }
  if (rotationAt !== null) {
    ctx.beginPath()
    ctx.arc(rotationAt.x * size.width, rotationAt.y * size.height, HANDLE_RADIUS, 0, Math.PI * 2)
    ctx.fill()
    ctx.stroke()
  }
  ctx.restore()
}

/**
 * The crop box: everything outside it dimmed, the box outlined, its corners
 * handled, and a rotation handle above it.
 */
export function drawCropOverlay(
  ctx: CanvasRenderingContext2D,
  rect: Rect,
  rotation: number,
  size: Size,
): void {
  ctx.save()
  ctx.fillStyle = "rgba(0,0,0,0.5)"
  ctx.fillRect(0, 0, size.width, size.height)
  const cx = midX(rect) * size.width
  const cy = midY(rect) * size.height
  ctx.translate(cx, cy)
  ctx.rotate(rotation)
  const w = rect.width * size.width
  const h = rect.height * size.height
  // Punch the box out of the dimming, so what will be kept is at full
  // brightness — the crop is judged on the picture, not on an outline.
  ctx.globalCompositeOperation = "destination-out"
  ctx.fillRect(-w / 2, -h / 2, w, h)
  ctx.globalCompositeOperation = "source-over"
  ctx.strokeStyle = "#6ecc1f"
  ctx.lineWidth = 1
  ctx.strokeRect(-w / 2, -h / 2, w, h)
  ctx.fillStyle = "#6ecc1f"
  const corners: { dx: number; dy: number }[] = [
    { dx: -w / 2, dy: -h / 2 },
    { dx: w / 2, dy: -h / 2 },
    { dx: w / 2, dy: h / 2 },
    { dx: -w / 2, dy: h / 2 },
  ]
  for (const { dx, dy } of corners) {
    ctx.fillRect(dx - HANDLE_RADIUS, dy - HANDLE_RADIUS, HANDLE_RADIUS * 2, HANDLE_RADIUS * 2)
  }
  ctx.beginPath()
  ctx.arc(0, -h / 2 - 26, HANDLE_RADIUS, 0, Math.PI * 2)
  ctx.fill()
  ctx.restore()
}
