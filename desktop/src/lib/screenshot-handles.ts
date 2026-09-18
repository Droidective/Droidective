import {
  boundingBox,
  bounds,
  midX,
  midY,
  rotate,
  type Annotation,
  type Point,
  type Size,
  type TextMeasurer,
} from "@/lib/screenshot-markup"

/**
 * Handles, resizing, rotation and hit-testing.
 *
 * Split from `screenshot-markup.ts` when it outgrew its line budget, and split
 * *here* because these five are the operations that have to reason about a
 * rotation: a handle is drawn on the turned shape, so a drag has to be mapped
 * back into the upright frame before it means anything. The shapes themselves
 * — what an annotation is, where its points are — stay next door.
 */

function rotatedHandle(a: Annotation, normalized: Point, size: Size, measure?: TextMeasurer): Point {
  if (a.rotation === 0) return normalized
  const b = bounds(a, size, measure)
  const centre = { x: midX(b) * size.width, y: midY(b) * size.height }
  const px = { x: normalized.x * size.width, y: normalized.y * size.height }
  const spun = rotate(px, centre, a.rotation)
  return { x: spun.x / size.width, y: spun.y / size.height }
}

/**
 * Normalized resize-handle positions.
 *
 * Two-point shapes expose their two defining points; freehand strokes expose
 * their bounding-box corners; text exposes one corner that scales its font.
 */
export function handlePoints(a: Annotation, size: Size, measure?: TextMeasurer): Point[] {
  let raw: Point[] = []
  switch (a.tool) {
    case "line":
    case "arrow":
    case "rectangle":
    case "ellipse":
    case "redact": {
      const [start, end] = a.points
      raw = start !== undefined && end !== undefined ? [start, end] : []
      break
    }
    case "pen":
    case "highlighter": {
      const b = boundingBox(a)
      raw = [
        { x: b.x, y: b.y },
        { x: b.x + b.width, y: b.y },
        { x: b.x + b.width, y: b.y + b.height },
        { x: b.x, y: b.y + b.height },
      ]
      break
    }
    case "text": {
      const b = bounds(a, size, measure)
      raw = [{ x: b.x + b.width, y: b.y + b.height }]
      break
    }
  }
  return raw.map((p) => rotatedHandle(a, p, size, measure))
}

/** The handle dragged to rotate, sitting above the top edge. */
export function rotationHandle(a: Annotation, size: Size, measure?: TextMeasurer): Point | null {
  const b = bounds(a, size, measure)
  if (b.width <= 0 && b.height <= 0) return null
  const offset = 26 / Math.max(size.height, 1)
  return rotatedHandle(a, { x: midX(b), y: b.y - offset }, size, measure)
}

/**
 * Translate every point, clamped so the bounding box stays inside 0…1.
 *
 * The shape moves rigidly and stops at the edge rather than deforming, which
 * is what makes dragging one to the border feel like moving a sticker.
 */
export function moved(a: Annotation, delta: Point): Annotation {
  const b = boundingBox(a)
  const dx = Math.min(Math.max(delta.x, -b.x), 1 - (b.x + b.width))
  const dy = Math.min(Math.max(delta.y, -b.y), 1 - (b.y + b.height))
  return { ...a, points: a.points.map((p) => ({ x: p.x + dx, y: p.y + dy })) }
}

/**
 * Move handle `index` to `target` (normalized).
 *
 * Two-point shapes move that endpoint; freehand strokes scale every point away
 * from the opposite corner; text scales its font so the handle tracks the
 * cursor.
 */
export function resizing(
  a: Annotation,
  index: number,
  target: Point,
  size: Size,
  measure?: TextMeasurer,
): Annotation {
  // Handles live on the *rotated* shape, so map the cursor back into the
  // un-rotated frame before applying an edit that knows nothing about rotation.
  let local = target
  if (a.rotation !== 0) {
    const b = bounds(a, size, measure)
    const centre = { x: midX(b) * size.width, y: midY(b) * size.height }
    const px = { x: target.x * size.width, y: target.y * size.height }
    const un = rotate(px, centre, -a.rotation)
    local = { x: un.x / size.width, y: un.y / size.height }
  }
  const p = { x: Math.min(1, Math.max(0, local.x)), y: Math.min(1, Math.max(0, local.y)) }

  switch (a.tool) {
    case "line":
    case "arrow":
    case "rectangle":
    case "ellipse":
    case "redact": {
      if (index < 0 || index >= a.points.length) return a
      const points = [...a.points]
      points[index] = p
      return { ...a, points }
    }
    case "pen":
    case "highlighter": {
      const b = boundingBox(a)
      const corners: Point[] = [
        { x: b.x, y: b.y },
        { x: b.x + b.width, y: b.y },
        { x: b.x + b.width, y: b.y + b.height },
        { x: b.x, y: b.y + b.height },
      ]
      const anchor = corners[(index + 2) % 4]
      if (anchor === undefined) return a
      const sx = Math.abs(p.x - anchor.x) / Math.max(b.width, 0.0001)
      const sy = Math.abs(p.y - anchor.y) / Math.max(b.height, 0.0001)
      return {
        ...a,
        points: a.points.map((q) => ({
          x: Math.min(1, Math.max(0, anchor.x + (q.x - anchor.x) * sx)),
          y: Math.min(1, Math.max(0, anchor.y + (q.y - anchor.y) * sy)),
        })),
      }
    }
    case "text": {
      const anchor = a.points[0]
      if (anchor === undefined) return a
      const currentHeight = bounds(a, size, measure).height
      const newHeight = Math.max(0.01, p.y - anchor.y)
      if (currentHeight <= 0.0001) return a
      return { ...a, width: Math.min(80, Math.max(2, (a.width * newHeight) / currentHeight)) }
    }
  }
}

/**
 * Rotate so the handle — which sits above the shape — points at `target`.
 *
 * The angle is computed in pixel space for the reason `rotate` is.
 */
export function rotated(a: Annotation, target: Point, size: Size, measure?: TextMeasurer): Annotation {
  const b = bounds(a, size, measure)
  const cx = midX(b) * size.width
  const cy = midY(b) * size.height
  const tx = target.x * size.width
  const ty = target.y * size.height
  return { ...a, rotation: Math.atan2(ty - cy, tx - cx) + Math.PI / 2 }
}

/**
 * The top-most annotation under `point` (in display pixels), or null.
 *
 * Area shapes hit inside their box; strokes and lines hit near their path. The
 * search runs newest-first, so a shape drawn over another picks up the click.
 */
export function hitTest(
  annotations: readonly Annotation[],
  point: Point,
  display: Size,
  tolerance: number,
  measure?: TextMeasurer,
): number | null {
  for (let index = annotations.length - 1; index >= 0; index -= 1) {
    const candidate = annotations[index]
    if (candidate !== undefined && hits(candidate, point, display, tolerance, measure)) return index
  }
  return null
}

function hits(a: Annotation, point: Point, display: Size, tol: number, measure?: TextMeasurer): boolean {
  let p = point
  if (a.rotation !== 0) {
    const b = bounds(a, display, measure)
    const centre = { x: midX(b) * display.width, y: midY(b) * display.height }
    p = rotate(point, centre, -a.rotation)
  }
  switch (a.tool) {
    case "rectangle":
    case "ellipse":
    case "redact":
    case "text": {
      const b = bounds(a, display, measure)
      return (
        p.x >= b.x * display.width - tol &&
        p.x <= (b.x + b.width) * display.width + tol &&
        p.y >= b.y * display.height - tol &&
        p.y <= (b.y + b.height) * display.height + tol
      )
    }
    case "pen":
    case "highlighter":
    case "line":
    case "arrow": {
      const pts = a.points.map((q) => ({ x: q.x * display.width, y: q.y * display.height }))
      return distanceToPolyline(pts, p) <= tol
    }
  }
}

function distanceToPolyline(pts: readonly Point[], p: Point): number {
  const first = pts[0]
  if (first === undefined) return Number.POSITIVE_INFINITY
  if (pts.length === 1) return Math.hypot(p.x - first.x, p.y - first.y)
  let best = Number.POSITIVE_INFINITY
  for (let i = 0; i < pts.length - 1; i += 1) {
    const a = pts[i]
    const b = pts[i + 1]
    if (a === undefined || b === undefined) continue
    best = Math.min(best, distanceToSegment(p, a, b))
  }
  return best
}

function distanceToSegment(p: Point, a: Point, b: Point): number {
  const dx = b.x - a.x
  const dy = b.y - a.y
  const lengthSquared = dx * dx + dy * dy
  if (lengthSquared < 1e-9) return Math.hypot(p.x - a.x, p.y - a.y)
  const t = Math.min(1, Math.max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
  return Math.hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
}
