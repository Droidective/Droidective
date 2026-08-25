import { useRef } from "react"

import { MirrorControls } from "@/components/MirrorControls"
import { NoDevice } from "@/components/NoDevice"
import { useMirror } from "@/hooks/useMirror"
import { useMirrorPointer } from "@/hooks/useMirrorPointer"
import { cn } from "@/lib/cn"
import type { Device } from "@/lib/wire"

/**
 * Mirror Screen: the device's own screen, live and interactive.
 *
 * The video is a `<canvas>` the webview decodes into rather than a native
 * surface, which is what lets it sit in the layout like any other element — a
 * split pane, a resize, and later the Mirror Wall's grid — instead of being a
 * window positioned over one. Backlog 25's step 0 has the reasoning and the
 * measurement behind it.
 */
export function MirrorPane({ device }: { device: Device | null }) {
  const mirror = useMirror(device?.serial ?? null)
  const surface = useRef<HTMLDivElement | null>(null)
  const pointer = useMirrorPointer(surface, mirror.size, mirror.send)

  if (device === null) {
    return <NoDevice feature="scrcpy" title="Mirror Screen" />
  }

  if (mirror.error !== null) {
    return (
      <div className="flex h-full flex-col items-center justify-center gap-3 p-8 text-center">
        <h2 className="text-[15px] font-medium text-text-primary">
          The mirror could not start
        </h2>
        <p className="max-w-md text-text-secondary">{mirror.error.message}</p>
      </div>
    )
  }

  // The first frame is what proves there is anything to tap.
  const live = mirror.size.width > 0
  return (
    <div className="flex h-full flex-col">
      <div
        ref={surface}
        onPointerDown={pointer.onPointerDown}
        onPointerMove={pointer.onPointerMove}
        onPointerUp={pointer.onPointerUp}
        onPointerCancel={pointer.onPointerUp}
        onWheel={pointer.onWheel}
        className={cn(
          "relative flex min-h-0 flex-1 items-center justify-center bg-black/90",
          live ? "cursor-pointer touch-none" : "cursor-default",
        )}
      >
        <canvas
          ref={mirror.attach}
          // `contain`, so the aspect ratio is preserved and the letterbox is
          // real — `pointFromPointer` maps taps against exactly this fit.
          className="max-h-full max-w-full object-contain"
          style={{ display: live ? "block" : "none" }}
        />
        {!live && (
          <p className="text-text-secondary">
            {mirror.streaming ? "Waiting for the first frame…" : "Starting the mirror…"}
          </p>
        )}
      </div>
      <MirrorControls send={mirror.send} dropped={mirror.dropped} />
    </div>
  )
}
