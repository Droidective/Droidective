import { Pause, Play } from "lucide-react"
import type { PointerEvent as ReactPointerEvent, RefObject } from "react"
import { Button } from "@/components/Controls"
import { IconButton } from "@/components/Hub"
import type { Point, Rect } from "@/lib/screenshot-markup"
import { timecode, type EditState } from "@/lib/video-edit"

/**
 * The video stage's pieces: the player element, the transport row, the crop
 * bar and the crop overlay.
 *
 * Split from `VideoStage` so that file stays the arrangement rather than the
 * arrangement plus four widgets.
 */

/** What a crop offers while it is being drawn — Reset, Cancel, Apply Crop. */
export function CropBar({
  draft,
  onReset,
  onCancel,
  onApply,
}: {
  draft: Rect | null
  onReset: () => void
  onCancel: () => void
  onApply: () => void
}) {
  return (
    <div className="flex items-center gap-2 border-t border-border-subtle px-3 py-2">
      <span className="text-[12px] text-text-tertiary">
        Drag on the video to choose the area to keep.
      </span>
      <div className="flex-1" />
      <Button onClick={onReset}>Reset</Button>
      <Button onClick={onCancel}>Cancel</Button>
      <Button tone="primary" disabled={draft === null} onClick={onApply}>
        Apply Crop
      </Button>
    </div>
  )
}

/** Play/pause, the scrubber, and the two timecodes. */
export function Transport({
  playing,
  position,
  duration,
  onToggle,
  onSeek,
}: {
  playing: boolean
  position: number
  duration: number
  onToggle: () => void
  onSeek: (seconds: number) => void
}) {
  return (
    <div className="flex items-center gap-2 border-t border-border-subtle px-3 py-2">
      <IconButton
        icon={playing ? <Pause size={14} /> : <Play size={14} />}
        label={playing ? "Pause" : "Play"}
        onClick={onToggle}
      />
      <span className="w-12 shrink-0 text-[11.5px] tabular-nums text-text-tertiary">
        {timecode(position)}
      </span>
      <input
        type="range"
        aria-label="Position"
        min={0}
        max={Math.max(duration, 0.1)}
        step={0.05}
        value={position}
        onChange={(event) => {
          onSeek(Number(event.target.value))
        }}
        className="min-w-0 flex-1 accent-accent"
      />
      <span className="w-12 shrink-0 text-right text-[11.5px] tabular-nums text-text-tertiary">
        {timecode(duration)}
      </span>
    </div>
  )
}


export function CropLayer({
  crop,
  onDown,
  onMove,
  onUp,
}: {
  crop: Rect | null
  onDown: (at: Point) => void
  onMove: (at: Point) => void
  onUp: () => void
}) {
  return (
    <div
      role="presentation"
      className="absolute inset-3 cursor-crosshair touch-none"
      onPointerDown={(event) => {
        event.currentTarget.setPointerCapture(event.pointerId)
        onDown(pointerFraction(event))
      }}
      onPointerMove={(event) => {
        if (event.buttons !== 0) onMove(pointerFraction(event))
      }}
      onPointerUp={(event) => {
        event.currentTarget.releasePointerCapture(event.pointerId)
        onUp()
      }}
    >
      <div className="absolute inset-0 bg-black/40" />
      {crop === null ? null : (
        <div
          className="absolute border border-accent bg-transparent shadow-[0_0_0_9999px_rgba(0,0,0,0.4)]"
          style={{
            left: `${crop.x * 100}%`,
            top: `${crop.y * 100}%`,
            width: `${crop.width * 100}%`,
            height: `${crop.height * 100}%`,
          }}
        />
      )}
    </div>
  )
}

/** Where a pointer is, as a fraction of the overlay. */
function pointerFraction(event: ReactPointerEvent<HTMLDivElement>): Point {
  const box = event.currentTarget.getBoundingClientRect()
  return {
    x: box.width === 0 ? 0 : (event.clientX - box.left) / box.width,
    y: box.height === 0 ? 0 : (event.clientY - box.top) / box.height,
  }
}

/**
 * The `<video>` itself.
 *
 * Rotation and both flips are a CSS transform rather than a re-encode, so the
 * preview follows every click instantly and shows what the export will produce.
 */
export function Player({
  ref,
  url,
  edit,
  onDuration,
  onPosition,
  onPlaying,
  onUnplayable,
}: {
  ref: RefObject<HTMLVideoElement | null>
  url: string
  edit: EditState
  onDuration: (seconds: number) => void
  onPosition: (seconds: number) => void
  onPlaying: (playing: boolean) => void
  onUnplayable: () => void
}) {
  return (
    <video
      ref={ref}
      src={url}
      className="max-h-full max-w-full"
      style={{
        transform:
          `rotate(${edit.rotationDegrees}deg)` +
          ` scaleX(${edit.flipH ? -1 : 1}) scaleY(${edit.flipV ? -1 : 1})`,
      }}
      onLoadedMetadata={(event) => {
        const seconds = event.currentTarget.duration
        if (Number.isFinite(seconds)) onDuration(seconds)
      }}
      onTimeUpdate={(event) => {
        onPosition(event.currentTarget.currentTime)
      }}
      onPlay={() => {
        onPlaying(true)
      }}
      onPause={() => {
        onPlaying(false)
      }}
      onError={onUnplayable}
    >
      {/* No captions exist for a screen recording, and this is a preview rather
          than published media — but an empty track is the honest way to say so. */}
      <track kind="captions" />
    </video>
  )
}
