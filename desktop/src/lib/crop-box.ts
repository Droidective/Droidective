import { midX, midY, rotate, type Point, type Rect, type Size } from "@/lib/screenshot-markup"

/**
 * A crop box: the normalized rect, its handles, and what a drag on it does.
 *
 * Shared by the screenshot editor and the video editor, which is why it is not
 * named for either. A crop is not an annotation — no colour, no undo entry of
 * its own, gone at Apply — but it carries the awkward part of one: a rotation,
 * and handles that have to be hit-tested in the rotated frame. The video
 * editor passes rotation 0, since its own rotation is the quarter-turn control
 * rather than a tilted box.
 */

/** What a pointer-down on the crop box has taken hold of. */
export type CropGrab =
  | { kind: "none" }
  | { kind: "move" }
  | { kind: "rotate" }
  | { kind: "corner"; index: number }

/** How far, in display pixels, the rotation handle floats above the box. */
const ROTATE_OFFSET = 26

/** The four corners, in the order top-left, top-right, bottom-right, bottom-left. */
export function cropHandles(rect: Rect, rotation: number, size: Size): Point[] {
  const corners: Point[] = [
    { x: rect.x, y: rect.y },
    { x: rect.x + rect.width, y: rect.y },
    { x: rect.x + rect.width, y: rect.y + rect.height },
    { x: rect.x, y: rect.y + rect.height },
  ]
  return corners.map((p) => spin(p, rect, rotation, size))
}

/** Where the rotation handle sits. */
export function cropRotationHandle(rect: Rect, rotation: number, size: Size): Point {
  return spin({ x: midX(rect), y: rect.y - ROTATE_OFFSET / Math.max(size.height, 1) }, rect, rotation, size)
}

function spin(p: Point, rect: Rect, rotation: number, size: Size): Point {
  if (rotation === 0) return p
  const centre = { x: midX(rect) * size.width, y: midY(rect) * size.height }
  const px = { x: p.x * size.width, y: p.y * size.height }
  const spun = rotate(px, centre, rotation)
  return { x: spun.x / size.width, y: spun.y / size.height }
}

/**
 * What a pointer at `at` (display pixels) has grabbed.
 *
 * Handles are tested before the box, so a corner inside the box still resizes
 * rather than moving — otherwise a box big enough to cover its own handles
 * could never be resized.
 */
export function cropGrab(
  at: Point,
  rect: Rect,
  rotation: number,
  size: Size,
  tolerance: number,
): CropGrab {
  const rotateAt = cropRotationHandle(rect, rotation, size)
  if (near(at, rotateAt, size, tolerance)) return { kind: "rotate" }
  const handles = cropHandles(rect, rotation, size)
  for (const [index, handle] of handles.entries()) {
    if (near(at, handle, size, tolerance)) return { kind: "corner", index }
  }
  // Inside the box, in its own frame.
  const centre = { x: midX(rect) * size.width, y: midY(rect) * size.height }
  const local = rotation === 0 ? at : rotate(at, centre, -rotation)
  const inside =
    local.x >= rect.x * size.width &&
    local.x <= (rect.x + rect.width) * size.width &&
    local.y >= rect.y * size.height &&
    local.y <= (rect.y + rect.height) * size.height
  return inside ? { kind: "move" } : { kind: "none" }
}

function near(at: Point, handle: Point, size: Size, tolerance: number): boolean {
  return Math.hypot(at.x - handle.x * size.width, at.y - handle.y * size.height) <= tolerance
}

/** The smallest crop worth applying, normalized. */
export const MIN_CROP = 0.02

/** A rect kept inside the image and above the minimum size. */
export function clampCrop(rect: Rect): Rect {
  const width = Math.max(MIN_CROP, Math.min(1, rect.width))
  const height = Math.max(MIN_CROP, Math.min(1, rect.height))
  return {
    x: Math.min(Math.max(0, rect.x), 1 - width),
    y: Math.min(Math.max(0, rect.y), 1 - height),
    width,
    height,
  }
}

/** Move the box by a normalized delta, stopping at the image's edge. */
export function moveCrop(rect: Rect, delta: Point): Rect {
  return clampCrop({ ...rect, x: rect.x + delta.x, y: rect.y + delta.y })
}

/**
 * Drag one corner to `target`.
 *
 * The opposite corner is the anchor, so the box grows away from what is being
 * held — and the target is mapped back through the rotation first, for the
 * reason an annotation's resize is.
 */
export function resizeCrop(
  rect: Rect,
  index: number,
  target: Point,
  rotation: number,
  size: Size,
): Rect {
  const centre = { x: midX(rect) * size.width, y: midY(rect) * size.height }
  const px = { x: target.x * size.width, y: target.y * size.height }
  const local = rotation === 0 ? px : rotate(px, centre, -rotation)
  const p = {
    x: Math.min(1, Math.max(0, local.x / size.width)),
    y: Math.min(1, Math.max(0, local.y / size.height)),
  }
  const corners: Point[] = [
    { x: rect.x, y: rect.y },
    { x: rect.x + rect.width, y: rect.y },
    { x: rect.x + rect.width, y: rect.y + rect.height },
    { x: rect.x, y: rect.y + rect.height },
  ]
  // Range-checked rather than left to the modulo: `(9 + 2) % 4` is a valid
  // corner, so a wrong index would silently resize from the wrong anchor
  // instead of doing nothing.
  if (index < 0 || index > 3) return rect
  const anchor = corners[(index + 2) % 4]
  if (anchor === undefined) return rect
  return clampCrop({
    x: Math.min(anchor.x, p.x),
    y: Math.min(anchor.y, p.y),
    width: Math.abs(p.x - anchor.x),
    height: Math.abs(p.y - anchor.y),
  })
}

/** Turn the box so its handle points at `target`. */
export function rotateCrop(rect: Rect, target: Point, size: Size): number {
  const cx = midX(rect) * size.width
  const cy = midY(rect) * size.height
  return Math.atan2(target.y * size.height - cy, target.x * size.width - cx) + Math.PI / 2
}
