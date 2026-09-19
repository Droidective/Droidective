import { useCallback, useRef } from "react"

import { MirrorControls } from "@/components/MirrorControls"
import { NoDevice } from "@/components/NoDevice"
import { ScreenshotEditor } from "@/components/ScreenshotEditor"
import { useMirror } from "@/hooks/useMirror"
import { useMirrorPointer } from "@/hooks/useMirrorPointer"
import { useScreenshotEditor } from "@/hooks/useScreenshotEditor"
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
  const editor = useScreenshotEditor()
  const video = useRef<HTMLCanvasElement | null>(null)

  // One ref callback feeding two owners: the decoder needs the element to draw
  // into, and the camera button needs it to copy out of.
  const attach = useCallback(
    (element: HTMLCanvasElement | null) => {
      video.current = element
      mirror.attach(element)
    },
    [mirror],
  )

  /**
   * The last decoded frame, into the editor.
   *
   * The canvas itself rather than a fresh `screencap`, which is what the Mac
   * does (`MirrorViewModel.takeScreenshot` reads the session's own snapshot):
   * a second capture would be a different moment from the one on screen.
   */
  const capture = useCallback(() => {
    const canvas = video.current
    if (canvas === null || canvas.width === 0) return
    void createImageBitmap(canvas).then(
      (bitmap) => {
        editor.open(bitmap)
      },
      () => {
        // Nothing to say: the only way this fails is a canvas with no frame,
        // and the button is already hidden until one has arrived.
      },
    )
  }, [editor])

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
    <div className="relative flex h-full flex-col">
      {editor.image === null ? null : (
        <div className="absolute inset-0 z-10 bg-bg-root">
          <ScreenshotEditor editor={editor} onNew={editor.close} />
        </div>
      )}
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
          ref={attach}
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
      <MirrorControls
        send={mirror.send}
        dropped={mirror.dropped}
        onCapture={live ? capture : undefined}
      />
    </div>
  )
}
