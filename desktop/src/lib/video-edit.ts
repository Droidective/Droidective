import type { Rect } from "@/lib/screenshot-markup"

/**
 * The video editor's edit state and its rules, ported from the Mac's
 * `VideoEditorPane` and `VideoExportOptions`.
 *
 * Nothing here runs ffmpeg. The argument vector is ADBKit's `VideoEditing`,
 * pure and already tested, and both apps go through it — so a rotation or a
 * trim cannot come to mean two different things. What this module owns is
 * everything *above* that: what an edit is, what each control does to it, and
 * when an export can skip ffmpeg entirely.
 */

export type VideoFormat = "mp4" | "mov" | "mkv" | "webm" | "gif"
export type CompressionLevel = "none" | "medium" | "high"

export interface EditState {
  trimStart: number | null
  trimEnd: number | null
  /** Clockwise, normalized to 0/90/180/270 by `normalizedRotation`. */
  rotationDegrees: number
  flipH: boolean
  flipV: boolean
  crop: Rect | null
  /** Playback-rate multiplier; 2 is twice as fast. */
  speed: number
  mute: boolean
  scaleWidth: number | null
  compression: CompressionLevel
  format: VideoFormat
}

export const NO_EDITS: EditState = {
  trimStart: null,
  trimEnd: null,
  rotationDegrees: 0,
  flipH: false,
  flipV: false,
  crop: null,
  speed: 1,
  mute: false,
  scaleWidth: null,
  compression: "none",
  format: "mp4",
}

/** The Mac's five speeds, in its order. */
export const SPEEDS: readonly number[] = [0.25, 0.5, 1, 1.5, 2]

/** The Mac's five export targets, with its labels. */
export const FORMATS: readonly { value: VideoFormat; label: string }[] = [
  { value: "mp4", label: "MP4" },
  { value: "mov", label: "MOV" },
  { value: "mkv", label: "MKV" },
  { value: "webm", label: "WebM" },
  { value: "gif", label: "GIF" },
]

export const COMPRESSIONS: readonly { value: CompressionLevel; label: string }[] = [
  { value: "none", label: "None" },
  { value: "medium", label: "Medium" },
  { value: "high", label: "High" },
]

/** How many edits the undo history keeps. */
export const MAX_UNDO = 50

export function normalizedRotation(degrees: number): number {
  return ((degrees % 360) + 360) % 360
}

/** A crop covering the whole frame within rounding — i.e. not really a crop. */
export function isFullFrame(crop: Rect): boolean {
  return crop.x <= 0.0001 && crop.y <= 0.0001 && crop.width >= 0.9999 && crop.height >= 0.9999
}

/**
 * No edits at all.
 *
 * `VideoExportOptions.isIdentity`'s rule exactly, because it is what decides
 * whether the export can be a file copy rather than a re-encode — the two
 * disagreeing would mean silently re-encoding a file nobody changed, or
 * copying one somebody did.
 */
export function isIdentity(edit: EditState): boolean {
  return (
    edit.trimStart === null &&
    edit.trimEnd === null &&
    normalizedRotation(edit.rotationDegrees) === 0 &&
    !edit.flipH &&
    !edit.flipV &&
    (edit.crop === null || isFullFrame(edit.crop)) &&
    edit.speed === 1 &&
    !edit.mute &&
    edit.scaleWidth === null &&
    edit.compression === "none"
  )
}

/** Whether anything has been changed — what the leave prompt asks. */
export function hasEdits(edit: EditState): boolean {
  return JSON.stringify(edit) !== JSON.stringify({ ...NO_EDITS, format: edit.format })
}

/** A quarter-turn, either way. */
export function turned(edit: EditState, clockwise: boolean): EditState {
  return {
    ...edit,
    rotationDegrees: normalizedRotation(edit.rotationDegrees + (clockwise ? 90 : -90)),
  }
}

/**
 * The trim, kept sane.
 *
 * A start past the end is the drag that crossed over, and an end past the
 * duration is a scrubber rounding up — both are ordinary, so they are clamped
 * rather than refused. A zero-length trim would export an empty file, so the
 * two are kept at least a frame apart.
 */
export const MIN_TRIM = 0.05

export function withTrim(
  edit: EditState,
  start: number | null,
  end: number | null,
  duration: number,
): EditState {
  if (start === null && end === null) return { ...edit, trimStart: null, trimEnd: null }
  const from = Math.min(Math.max(0, start ?? 0), Math.max(0, duration - MIN_TRIM))
  const to = Math.min(Math.max(from + MIN_TRIM, end ?? duration), duration)
  return { ...edit, trimStart: from, trimEnd: to }
}

/** How long the exported clip runs, given the trim and the speed. */
export function outputSeconds(edit: EditState, duration: number): number {
  const from = edit.trimStart ?? 0
  const to = edit.trimEnd ?? duration
  return Math.max(0, (to - from) / (edit.speed === 0 ? 1 : edit.speed))
}

/** `m:ss` for a scrubber, or `h:mm:ss` past an hour. */
export function timecode(seconds: number): string {
  const total = Math.max(0, Math.floor(seconds))
  const s = String(total % 60).padStart(2, "0")
  const m = Math.floor(total / 60) % 60
  const h = Math.floor(total / 3600)
  return h > 0 ? `${h}:${String(m).padStart(2, "0")}:${s}` : `${m}:${s}`
}

/** Push an edit onto the history, dropping the oldest once it is full. */
export function pushUndo(stack: readonly EditState[], state: EditState): EditState[] {
  const next = [...stack, state]
  return next.length > MAX_UNDO ? next.slice(next.length - MAX_UNDO) : next
}

/**
 * The file name an export suggests: the source's, with the chosen extension.
 *
 * Keeping the stem is what makes a folder of exports readable — `recording_…
 * .gif` beside `recording_….mp4` says what it came from, where a fresh
 * timestamp would not.
 */
export function suggestedName(sourcePath: string, format: VideoFormat): string {
  const leaf = sourcePath.split(/[/\\]/u).pop() ?? "video"
  const stem = leaf.includes(".") ? leaf.slice(0, leaf.lastIndexOf(".")) : leaf
  return `${stem === "" ? "video" : stem}.${format}`
}

/** The edit as the daemon's `ExportOptions`. */
export function wireOptions(edit: EditState): Record<string, unknown> {
  return {
    trimStart: edit.trimStart,
    trimEnd: edit.trimEnd,
    rotationDegrees: normalizedRotation(edit.rotationDegrees),
    flipH: edit.flipH,
    flipV: edit.flipV,
    cropX: edit.crop?.x ?? null,
    cropY: edit.crop?.y ?? null,
    cropWidth: edit.crop?.width ?? null,
    cropHeight: edit.crop?.height ?? null,
    speed: edit.speed,
    mute: edit.mute,
    scaleWidth: edit.scaleWidth,
    compression: edit.compression,
    format: edit.format,
  }
}
