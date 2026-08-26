import { useRef, type DragEvent } from "react"
import { GripVertical } from "lucide-react"

import { useMirror } from "@/hooks/useMirror"
import { useMirrorPointer } from "@/hooks/useMirrorPointer"
import { cn } from "@/lib/cn"
import type { Quality } from "@/lib/mirror-wall"

/**
 * One device in the wall: its own scrcpy session, its own decoder, interactive.
 *
 * The caption strip is the drag handle and the video is not — an `onDrag` on
 * the video would eat every swipe on the device, which is the whole point of
 * the tile. The Mac learned that one and the note is in its `mirror-wall`
 * description.
 */
export function MirrorTile({
  serial,
  label,
  index,
  quality,
  onReorder,
}: {
  serial: string
  /** What to call it — the device's own name once scrcpy reports one. */
  label: string
  index: number
  quality: Quality
  onReorder: (from: number, to: number) => void
}) {
  const mirror = useMirror(serial, quality)
  const surface = useRef<HTMLDivElement | null>(null)
  const pointer = useMirrorPointer(surface, mirror.size, mirror.send)

  const onDragStart = (event: DragEvent<HTMLDivElement>) => {
    event.dataTransfer.setData("text/plain", String(index))
    event.dataTransfer.effectAllowed = "move"
  }

  const onDrop = (event: DragEvent<HTMLDivElement>) => {
    event.preventDefault()
    const from = Number(event.dataTransfer.getData("text/plain"))
    // A drag from somewhere else entirely carries text that is not an index.
    if (!Number.isInteger(from)) return
    onReorder(from, index)
  }

  const live = mirror.size.width > 0
  return (
    <div
      className="flex min-h-0 flex-col overflow-hidden rounded border border-border-subtle bg-bg-surface"
      onDragOver={(event) => event.preventDefault()}
      onDrop={onDrop}
    >
      <div
        draggable
        onDragStart={onDragStart}
        // The strip, and only the strip. `cursor-grab` says so before anyone
        // tries it on the video.
        className="flex cursor-grab items-center gap-1.5 border-b border-border-subtle px-2 py-1 text-xs text-text-secondary"
        title={serial}
      >
        <GripVertical size={12} className="shrink-0 text-text-tertiary" />
        <span className="truncate">{mirror.deviceName ?? label}</span>
        {mirror.dropped > 0 && (
          <span className="ml-auto shrink-0 text-text-tertiary">{mirror.dropped} dropped</span>
        )}
      </div>

      <div
        ref={surface}
        onPointerDown={pointer.onPointerDown}
        onPointerMove={pointer.onPointerMove}
        onPointerUp={pointer.onPointerUp}
        onPointerCancel={pointer.onPointerUp}
        onWheel={pointer.onWheel}
        className={cn(
          "relative flex min-h-0 flex-1 items-center justify-center bg-black/90 p-1",
          live ? "cursor-pointer touch-none" : "cursor-default",
        )}
      >
        <canvas
          ref={mirror.attach}
          className="max-h-full max-w-full object-contain"
          style={{ display: live ? "block" : "none" }}
        />
        {!live && (
          <p className="px-2 text-center text-xs text-text-tertiary">
            {mirror.error === null
              ? mirror.streaming
                ? "Waiting for the first frame…"
                : "Starting…"
              : mirror.error.message}
          </p>
        )}
      </div>
    </div>
  )
}
