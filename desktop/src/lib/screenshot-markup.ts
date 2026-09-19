/**
 * The screenshot editor's geometry, ported from the Mac's `ScreenshotMarkup`
 * and `Annotation`.
 *
 * Every point is **normalized (0…1) to the image**, which is the decision the
 * whole editor rests on: the on-screen canvas and the full-resolution export
 * then share one set of numbers, and an annotation drawn at a third of the size
 * lands in the same place in the saved PNG.
 *
 * Nothing here draws. Drawing is `screenshot-draw.ts`, which takes these
 * shapes and a 2-D context; keeping them apart is what makes the part that is
 * easy to get subtly wrong — where a handle sits after a rotation, which
 * annotation a click picks — testable without a canvas.
 */

export type MarkupTool =
  | "pen"
  | "highlighter"
  | "arrow"
  | "line"
  | "rectangle"
  | "ellipse"
  | "text"
  | "redact"

export const MARKUP_TOOLS: readonly MarkupTool[] = [
  "pen",
  "highlighter",
  "arrow",
  "line",
  "rectangle",
  "ellipse",
  "text",
  "redact",
]

/** The Mac's `MarkupTool.label`. */
export const TOOL_LABELS: Record<MarkupTool, string> = {
  pen: "Pen",
  highlighter: "Highlighter",
  arrow: "Arrow",
  line: "Line",
  rectangle: "Rectangle",
  ellipse: "Ellipse",
  text: "Text",
  redact: "Redact",
}

/** Tools dragged from a start point to an end point (two-point geometry). */
export function isDragShape(tool: MarkupTool): boolean {
  return tool === "arrow" || tool === "line" || tool === "rectangle" || tool === "ellipse" || tool === "redact"
}

export type RedactStyle = "blur" | "solid"

export interface Point {
  x: number
  y: number
}

export interface Rect {
  x: number
  y: number
  width: number
  height: number
}

export interface Size {
  width: number
  height: number
}

/** One markup element. */
export interface Annotation {
  id: string
  tool: MarkupTool
  /** A CSS colour. */
  color: string
  /**
   * Stroke weight in points per 1000px of image width, so it scales with the
   * render size — the Mac's own unit.
   */
  width: number
  points: Point[]
  text: string
  /** Only meaningful for `redact`. */
  redactStyle: RedactStyle
  /** Blur intensity (0…1) for a blur-style redact. */
  blurStrength: number
  /** Fill opacity (0…1) for a solid-style redact. */
  fillOpacity: number
  /** Rotation in radians around the bounding box's centre. */
  rotation: number
}

/** The eight swatches the Mac's toolbar offers, in its order. */
export const PALETTE: readonly string[] = [
  "#ff3b30",
  "#ff9500",
  "#ffcc00",
  "#34c759",
  "#007aff",
  "#af52de",
  "#000000",
  "#ffffff",
]

/** Thin / Medium / Thick, the Mac's three. */
export const WIDTHS: readonly { label: string; value: number }[] = [
  { label: "Thin", value: 3 },
  { label: "Medium", value: 6 },
  { label: "Thick", value: 12 },
]

/**
 * How many (image, annotations) snapshots the undo history keeps.
 *
 * The Mac's cap, for the Mac's reason: a crop replaces the base image, so a
 * snapshot can hold a full-resolution copy and an uncapped history grows
 * without bound over a long session.
 */
export const MAX_UNDO = 50

export function annotation(over: Partial<Annotation> & { tool: MarkupTool }): Annotation {
  return {
    id: crypto.randomUUID(),
    color: "#ff3b30",
    width: 6,
    points: [],
    text: "",
    redactStyle: "solid",
    blurStrength: 0.4,
    fillOpacity: 1,
    rotation: 0,
    ...over,
  }
}

/**
 * Measures a text annotation's rendered extent, normalized to the image.
 *
 * Injected rather than computed here: measuring needs a font, which needs a
 * canvas, and a pure module that reached for one could not be tested. The
 * editor passes a real measurer; `bounds` falls back to the approximation
 * `boundingBox` uses when none is given, which is what the Mac's own
 * `Annotation.boundingBox` does before a render size is known.
 */
export type TextMeasurer = (text: string, fontSizePx: number) => Size

/** The font size a text annotation draws at, for a given render width. */
export function textFontSize(a: Annotation, size: Size): number {
  return Math.max(11, size.width * 0.03 * (a.width / 6))
}

/**
 * Normalized bounding box from the points alone.
 *
 * Text gets an approximate extent — its real size depends on the render width —
 * so it is still selectable and movable before anything has measured it.
 */
export function boundingBox(a: Annotation): Rect {
  const first = a.points[0]
  if (first === undefined) return { x: 0, y: 0, width: 0, height: 0 }
  if (a.tool === "text") {
    const w = Math.max(0.06, Math.max(a.text.length, 4) * 0.011 * (a.width / 6))
    const h = Math.max(0.03, 0.05 * (a.width / 6))
    return { x: first.x, y: first.y, width: w, height: h }
  }
  let minX = first.x
  let minY = first.y
  let maxX = first.x
  let maxY = first.y
  for (const p of a.points) {
    minX = Math.min(minX, p.x)
    minY = Math.min(minY, p.y)
    maxX = Math.max(maxX, p.x)
    maxY = Math.max(maxY, p.y)
  }
  return { x: minX, y: minY, width: maxX - minX, height: maxY - minY }
}

/**
 * Normalized bounding box at a render size — text measured with its real font
 * so the box wraps the glyphs, everything else point-based and therefore
 * render-independent.
 */
export function bounds(a: Annotation, size: Size, measure?: TextMeasurer): Rect {
  const origin = a.points[0]
  if (a.tool !== "text" || origin === undefined || size.width <= 0 || size.height <= 0) {
    return boundingBox(a)
  }
  if (measure === undefined) return boundingBox(a)
  const measured = measure(a.text.length === 0 ? "Text" : a.text, textFontSize(a, size))
  return {
    x: origin.x,
    y: origin.y,
    width: measured.width / size.width,
    height: measured.height / size.height,
  }
}

export function midX(r: Rect): number {
  return r.x + r.width / 2
}

export function midY(r: Rect): number {
  return r.y + r.height / 2
}

/**
 * Rotate `p` around `centre` by `angle` radians.
 *
 * Callers work in **pixels**, not normalized units, so the rotation is
 * isotropic — rotating normalized coordinates on a non-square image shears it.
 */
export function rotate(p: Point, centre: Point, angle: number): Point {
  const s = Math.sin(angle)
  const c = Math.cos(angle)
  const dx = p.x - centre.x
  const dy = p.y - centre.y
  return { x: centre.x + dx * c - dy * s, y: centre.y + dx * s + dy * c }
}

/** A normalized rect spanning two points, in either order. */
export function rectBetween(a: Point, b: Point): Rect {
  return {
    x: Math.min(a.x, b.x),
    y: Math.min(a.y, b.y),
    width: Math.abs(a.x - b.x),
    height: Math.abs(a.y - b.y),
  }
}

/** A blur-style redact region: where, how strong, and how far turned. */
export interface BlurRegion {
  rect: Rect
  strength: number
  rotation: number
}

/**
 * The blur-style redact regions, drawn beneath the markup rather than on it.
 *
 * A 2-D context cannot sample what is under a shape, so a blur has to be a
 * second pass over the base image masked to these rects — the same split the
 * Mac makes between its `Canvas` and `RedactBlurLayer`.
 */
export function blurRegions(
  annotations: readonly Annotation[],
  draft: Annotation | null,
): BlurRegion[] {
  const result: BlurRegion[] = []
  for (const a of [...annotations, ...(draft === null ? [] : [draft])]) {
    const [start, end] = a.points
    if (a.tool !== "redact" || a.redactStyle !== "blur" || start === undefined || end === undefined) {
      continue
    }
    result.push({ rect: rectBetween(start, end), strength: a.blurStrength, rotation: a.rotation })
  }
  return result
}
