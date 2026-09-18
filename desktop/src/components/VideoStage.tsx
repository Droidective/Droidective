import { useCallback, useRef, useState } from "react"
import { CropBar, CropLayer, Player, Transport } from "@/components/VideoStageParts"
import type { VideoEditor } from "@/hooks/useVideoEditor"
import { clampCrop } from "@/lib/crop-box"
import { rectBetween, type Point, type Rect } from "@/lib/screenshot-markup"

/**
 * The player, its scrubber, and the crop overlay.
 *
 * The transform controls preview live — a rotation and a flip are a CSS
 * transform on the element, so what is on screen is what the export will
 * produce, without ffmpeg running for every click.
 */
export function VideoStage({
  editor,
  cropping,
  onCropping,
  onDuration,
  onPosition,
}: {
  editor: VideoEditor
  cropping: boolean
  onCropping: (on: boolean) => void
  onDuration: (seconds: number) => void
  onPosition: (seconds: number) => void
}) {
  const video = useRef<HTMLVideoElement>(null)
  const [playing, setPlaying] = useState(false)
  const [duration, setDuration] = useState(0)
  const [position, setPosition] = useState(0)
  const drag = useCropDrag()

  const stageNote = noteFor(editor)

  const seek = useCallback((seconds: number) => {
    const element = video.current
    if (element === null) return
    element.currentTime = seconds
  }, [])

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <div className="relative flex min-h-0 flex-1 items-center justify-center bg-black/60 p-3">
        {editor.url === null ? null : (
          <Player
            ref={video}
            url={editor.url}
            edit={editor.edit}
            onDuration={(seconds) => {
              setDuration(seconds)
              onDuration(seconds)
            }}
            onPosition={(seconds) => {
              setPosition(seconds)
              onPosition(seconds)
            }}
            onPlaying={setPlaying}
            onUnplayable={editor.reportUnplayable}
          />
        )}

        {cropping ? <CropLayer crop={drag.draft ?? editor.edit.crop} {...drag.handlers} /> : null}

        {stageNote === null ? null : (
          <p className="pointer-events-none absolute inset-x-0 bottom-4 mx-auto max-w-md text-center text-[12.5px] text-text-secondary">
            {stageNote}
          </p>
        )}
      </div>

      {cropping ? (
        <CropBar
          draft={drag.draft}
          onReset={() => {
            drag.clear()
            editor.apply((current) => ({ ...current, crop: null }))
          }}
          onCancel={() => {
            drag.clear()
            onCropping(false)
          }}
          onApply={() => {
            const chosen = drag.draft
            if (chosen !== null) editor.apply((current) => ({ ...current, crop: chosen }))
            drag.clear()
            onCropping(false)
          }}
        />
      ) : (
        <Transport
          playing={playing}
          position={position}
          duration={duration}
          onToggle={() => {
            const element = video.current
            if (element === null) return
            if (playing) element.pause()
            else void element.play()
          }}
          onSeek={seek}
        />
      )}
    </div>
  )
}

/** What the stage says while it is not showing a picture. */
function noteFor(editor: VideoEditor): string | null {
  if (editor.error !== null) return editor.error
  switch (editor.stage) {
    case "remuxing":
      return "This container needs repackaging before it will play — your export still comes from the original file."
    case "transcoding":
      return "Converting this codec for playback — your export still comes from the original file."
    case "failed":
      return "This file can't be played here. ffmpeg couldn't produce a preview — it may be truncated, or use a codec this build wasn't made with. Exporting may still work."
    default:
      return null
  }
}

/**
 * Drawing a crop box on the video.
 *
 * Simpler than the screenshot editor's: the video's own rotation is the
 * quarter-turn control rather than a tilted box, so a drag is two corners and
 * nothing has to be mapped back through an angle.
 */
function useCropDrag() {
  const [draft, setDraft] = useState<Rect | null>(null)
  const from = useRef<Point | null>(null)

  return {
    draft,
    clear: useCallback(() => {
      setDraft(null)
      from.current = null
    }, []),
    handlers: {
      onDown: useCallback((at: Point) => {
        from.current = at
        setDraft({ x: at.x, y: at.y, width: 0, height: 0 })
      }, []),
      onMove: useCallback((at: Point) => {
        const start = from.current
        if (start !== null) setDraft(clampCrop(rectBetween(start, at)))
      }, []),
      onUp: useCallback(() => {
        from.current = null
      }, []),
    },
  }
}
