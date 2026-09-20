import { captureStamp } from "@/lib/capture-stamp"
import {
  annotation,
  isDragShape,
  MAX_UNDO,
  type Annotation,
  type MarkupTool,
  type Point,
  type RedactStyle,
} from "@/lib/screenshot-markup"

/**
 * The screenshot editor's decisions, kept out of the component.
 *
 * Everything here is a rule the Mac's `ScreenshotEditorView` applies, and the
 * ones worth having in a test are the ones that are invisible when they go
 * wrong: a drag too small to have been meant is thrown away, a rotate discards
 * markup positioned for the old orientation, and the undo history is capped
 * because a snapshot can hold a full-resolution image.
 */

/** The settings new markup is made with. */
export interface DrawSettings {
  tool: MarkupTool
  color: string
  width: number
  redactStyle: RedactStyle
  blurStrength: number
  fillOpacity: number
}

export const DEFAULT_SETTINGS: DrawSettings = {
  tool: "pen",
  color: "#ff3b30",
  width: 6,
  // The Mac defaults a redaction to blur: solid loses the shape of what was
  // hidden, which is usually why someone is hiding it rather than cropping.
  redactStyle: "blur",
  blurStrength: 0.4,
  fillOpacity: 1,
}

/** One point in the undo history: the image *and* its markup. */
export interface Snapshot {
  /**
   * The base image, which crop and rotate replace — an `ImageBitmap` from a
   * capture, or a canvas from an edit.
   */
  image: ImageBitmap | HTMLCanvasElement
  size: { width: number; height: number }
  annotations: Annotation[]
}

/**
 * Push a snapshot, dropping the oldest once the history is full.
 *
 * Capped for the Mac's reason: a crop replaces the base image, so a snapshot
 * can hold a full-resolution copy of it and an uncapped history grows without
 * bound over a long session.
 */
export function pushUndo(stack: readonly Snapshot[], snapshot: Snapshot): Snapshot[] {
  const next = [...stack, snapshot]
  return next.length > MAX_UNDO ? next.slice(next.length - MAX_UNDO) : next
}

/** The zoom steps behind the − and + buttons, clamped as the Mac clamps them. */
export function zoomOut(zoom: number): number {
  return Math.max(0.2, zoom / 1.25)
}

export function zoomIn(zoom: number): number {
  return Math.min(8, zoom * 1.25)
}

/**
 * A drag shorter than this (normalized) is a click that missed, not a shape.
 *
 * The Mac's threshold. Without it, every stray click on the canvas leaves a
 * zero-size annotation that is invisible but still selectable and still in the
 * undo history.
 */
export const MIN_DRAG = 0.004

/** The annotation a pointer-down starts. */
export function startDraft(settings: DrawSettings, at: Point): Annotation {
  return annotation({
    tool: settings.tool,
    color: settings.color,
    width: settings.width,
    redactStyle: settings.redactStyle,
    blurStrength: settings.blurStrength,
    fillOpacity: settings.fillOpacity,
    points: isDragShape(settings.tool) ? [at, at] : [at],
  })
}

/** The draft after the pointer moves to `at`. */
export function extendDraft(draft: Annotation, at: Point): Annotation {
  if (isDragShape(draft.tool)) {
    const [start] = draft.points
    return { ...draft, points: start === undefined ? [at, at] : [start, at] }
  }
  return { ...draft, points: [...draft.points, at] }
}

/**
 * The draft as it should be kept, or null to throw it away.
 *
 * A two-point shape whose ends are all but touching is a click, and keeping it
 * would leave an invisible annotation in the picture and in the undo history.
 */
export function commitDraft(draft: Annotation): Annotation | null {
  if (!isDragShape(draft.tool)) return draft.points.length > 0 ? draft : null
  const [start, end] = draft.points
  if (start === undefined || end === undefined) return null
  return Math.hypot(start.x - end.x, start.y - end.y) < MIN_DRAG ? null : draft
}

/**
 * The text annotation a committed label becomes, or null for an empty one.
 *
 * Trimmed, and an all-whitespace label is nothing — the Mac's `placeText`
 * guards on the trimmed string for the same reason.
 */
export function committedText(settings: DrawSettings, at: Point, text: string): Annotation | null {
  const trimmed = text.trim()
  if (trimmed.length === 0) return null
  return annotation({
    tool: "text",
    color: settings.color,
    width: settings.width,
    points: [at],
    text: trimmed,
  })
}

/**
 * Whether markup survives an edit that replaces the base image.
 *
 * It does not, and that is the Mac's behaviour rather than an omission: a crop
 * burns the annotations into the new image, and a quarter-turn would leave
 * every one of them positioned for an orientation that no longer exists.
 */
export const MARKUP_SURVIVES_AN_IMAGE_EDIT = false

/** What the trash button does, and what its tooltip says it does. */
export function trashAction(
  selecting: boolean,
  selectedID: string | null,
  annotations: readonly Annotation[],
): { action: "delete" | "clear"; label: string; enabled: boolean } {
  if (selecting && selectedID !== null) {
    return { action: "delete", label: "Delete selection", enabled: true }
  }
  return {
    action: "clear",
    label: "Clear all markup",
    enabled: !selecting && annotations.length > 0,
  }
}

/** The redact controls show only while a redaction is the subject. */
export function showsRedactControls(
  settings: DrawSettings,
  selecting: boolean,
  selected: Annotation | null,
): boolean {
  if (selecting) return selected?.tool === "redact"
  return settings.tool === "redact"
}

/**
 * The file name a save suggests.
 *
 * `ScreenCaptureService.stamp()`'s format exactly, so a folder holding captures
 * from both apps sorts as one set rather than two interleaved naming schemes.
 */
export function suggestedName(now: Date): string {
  return `screenshot_${captureStamp(now)}.png`
}
