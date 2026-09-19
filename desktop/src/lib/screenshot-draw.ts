import {
  blurRegions,
  bounds,
  midX,
  midY,
  textFontSize,
  type Annotation,
  type BlurRegion,
  type Rect,
  type Size,
  type TextMeasurer,
} from "@/lib/screenshot-markup"

/**
 * Rendering for the screenshot editor.
 *
 * One code path for the on-screen canvas and the full-resolution export, which
 * is the Mac's arrangement and the reason markup is WYSIWYG: `ScreenshotMarkup`
 * there takes a normalized annotation list and a target size, and so does
 * everything here. A second renderer for the export is how a blur that looks
 * right on screen ends up the wrong radius in the saved PNG.
 */

const FONT_STACK =
  '-apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI Variable Text", "Segoe UI", ui-sans-serif, system-ui, Roboto, sans-serif'

/** The canvas's own text measurement, as the editor's `TextMeasurer`. */
export function canvasMeasurer(ctx: CanvasRenderingContext2D): TextMeasurer {
  return (text, fontSizePx) => {
    ctx.save()
    ctx.font = `600 ${fontSizePx}px ${FONT_STACK}`
    const metrics = ctx.measureText(text)
    ctx.restore()
    return {
      width: metrics.width,
      // `actualBoundingBox*` is the drawn extent; falling back to the font size
      // keeps a measurement on engines that report neither.
      height:
        metrics.actualBoundingBoxAscent + metrics.actualBoundingBoxDescent || fontSizePx * 1.2,
    }
  }
}

/**
 * Paint every annotation, plus the one being dragged, at `size`.
 *
 * Solid redactions fill here. Blur ones do not: a 2-D context cannot sample
 * what is under a shape, so they are a second pass over the base image —
 * `drawBlurRedactions`, called *before* this — which is the same split the Mac
 * makes between its `Canvas` and `RedactBlurLayer`.
 */
export function drawMarkup(
  ctx: CanvasRenderingContext2D,
  annotations: readonly Annotation[],
  draft: Annotation | null,
  size: Size,
): void {
  for (const a of annotations) drawOne(ctx, a, size)
  if (draft !== null) drawOne(ctx, draft, size)
}

function drawOne(ctx: CanvasRenderingContext2D, a: Annotation, size: Size): void {
  const pts = a.points.map((p) => ({ x: p.x * size.width, y: p.y * size.height }))
  const first = pts[0]
  if (first === undefined) return
  const weight = Math.max(1, (a.width * size.width) / 1000)

  ctx.save()
  if (a.rotation !== 0) {
    const b = bounds(a, size, canvasMeasurer(ctx))
    ctx.translate(midX(b) * size.width, midY(b) * size.height)
    ctx.rotate(a.rotation)
    ctx.translate(-midX(b) * size.width, -midY(b) * size.height)
  }
  ctx.lineCap = "round"
  ctx.lineJoin = "round"
  ctx.strokeStyle = a.color
  ctx.fillStyle = a.color
  ctx.lineWidth = weight

  const second = pts[1]
  switch (a.tool) {
    case "pen":
      strokePolyline(ctx, pts)
      break
    case "highlighter":
      ctx.globalAlpha = 0.35
      ctx.lineWidth = weight * 3.5
      strokePolyline(ctx, pts)
      break
    case "line":
      if (second === undefined) break
      ctx.beginPath()
      ctx.moveTo(first.x, first.y)
      ctx.lineTo(second.x, second.y)
      ctx.stroke()
      break
    case "arrow":
      if (second === undefined) break
      drawArrow(ctx, first, second, weight)
      break
    case "rectangle": {
      if (second === undefined) break
      const r = pixelRect(first, second)
      ctx.beginPath()
      roundedRect(ctx, r, weight)
      ctx.stroke()
      break
    }
    case "ellipse": {
      if (second === undefined) break
      const r = pixelRect(first, second)
      ctx.beginPath()
      ctx.ellipse(r.x + r.width / 2, r.y + r.height / 2, r.width / 2, r.height / 2, 0, 0, Math.PI * 2)
      ctx.stroke()
      break
    }
    case "redact":
      // Solid only; a blur region was already painted underneath.
      if (second === undefined || a.redactStyle !== "solid") break
      ctx.globalAlpha = a.fillOpacity
      {
        const r = pixelRect(first, second)
        ctx.fillRect(r.x, r.y, r.width, r.height)
      }
      break
    case "text": {
      ctx.font = `600 ${textFontSize(a, size)}px ${FONT_STACK}`
      ctx.textBaseline = "top"
      ctx.textAlign = "left"
      ctx.fillText(a.text.length === 0 ? "Text" : a.text, first.x, first.y)
      break
    }
  }
  ctx.restore()
}

function strokePolyline(ctx: CanvasRenderingContext2D, pts: readonly { x: number; y: number }[]): void {
  const first = pts[0]
  if (first === undefined) return
  ctx.beginPath()
  ctx.moveTo(first.x, first.y)
  for (const p of pts.slice(1)) ctx.lineTo(p.x, p.y)
  // A single tap is a dot, not nothing — otherwise the pen looks broken for
  // anyone who clicks rather than drags.
  if (pts.length === 1) ctx.lineTo(first.x + 0.01, first.y)
  ctx.stroke()
}

function drawArrow(
  ctx: CanvasRenderingContext2D,
  start: { x: number; y: number },
  end: { x: number; y: number },
  weight: number,
): void {
  ctx.beginPath()
  ctx.moveTo(start.x, start.y)
  ctx.lineTo(end.x, end.y)
  ctx.stroke()
  const angle = Math.atan2(end.y - start.y, end.x - start.x)
  const head = Math.max(10, weight * 4)
  ctx.beginPath()
  ctx.moveTo(end.x, end.y)
  ctx.lineTo(end.x - Math.cos(angle - Math.PI / 7) * head, end.y - Math.sin(angle - Math.PI / 7) * head)
  ctx.moveTo(end.x, end.y)
  ctx.lineTo(end.x - Math.cos(angle + Math.PI / 7) * head, end.y - Math.sin(angle + Math.PI / 7) * head)
  ctx.stroke()
}

function pixelRect(a: { x: number; y: number }, b: { x: number; y: number }): Rect {
  return {
    x: Math.min(a.x, b.x),
    y: Math.min(a.y, b.y),
    width: Math.abs(a.x - b.x),
    height: Math.abs(a.y - b.y),
  }
}

function roundedRect(ctx: CanvasRenderingContext2D, r: Rect, radius: number): void {
  const capped = Math.max(0, Math.min(radius, Math.min(r.width, r.height) / 2))
  ctx.moveTo(r.x + capped, r.y)
  ctx.arcTo(r.x + r.width, r.y, r.x + r.width, r.y + r.height, capped)
  ctx.arcTo(r.x + r.width, r.y + r.height, r.x, r.y + r.height, capped)
  ctx.arcTo(r.x, r.y + r.height, r.x, r.y, capped)
  ctx.arcTo(r.x, r.y, r.x + r.width, r.y, capped)
  ctx.closePath()
}

/**
 * Paint the blur-style redactions: a blurred copy of the base image, clipped to
 * each region.
 *
 * The whole image is drawn each time rather than the region alone, which is
 * what clamps the edges — blurring a cropped piece fades it to transparent at
 * the borders and the sharp original leaks through, the defect the Mac's
 * `opaque: true` exists to prevent.
 */
export function drawBlurRedactions(
  ctx: CanvasRenderingContext2D,
  image: CanvasImageSource,
  annotations: readonly Annotation[],
  draft: Annotation | null,
  size: Size,
): void {
  const regions = blurRegions(annotations, draft)
  for (const region of regions) drawBlurRegion(ctx, image, region, size)
}

function drawBlurRegion(
  ctx: CanvasRenderingContext2D,
  image: CanvasImageSource,
  region: BlurRegion,
  size: Size,
): void {
  const r = region.rect
  if (r.width <= 0 || r.height <= 0) return
  ctx.save()
  const cx = (r.x + r.width / 2) * size.width
  const cy = (r.y + r.height / 2) * size.height
  ctx.translate(cx, cy)
  ctx.rotate(region.rotation)
  ctx.beginPath()
  ctx.rect(
    (-r.width / 2) * size.width,
    (-r.height / 2) * size.height,
    r.width * size.width,
    r.height * size.height,
  )
  ctx.clip()
  ctx.translate(-cx, -cy)
  ctx.filter = `blur(${Math.max(2, region.strength * size.width * 0.06)}px)`
  ctx.drawImage(image, 0, 0, size.width, size.height)
  ctx.restore()
}
