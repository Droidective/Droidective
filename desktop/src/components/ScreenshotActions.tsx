import { Camera, Copy, FolderOpen, Save } from "lucide-react"
import { useCallback } from "react"
import { Button } from "@/components/Controls"
import { ZoomControls } from "@/components/ScreenshotEditorParts"
import { useNotifications } from "@/hooks/useNotifications"
import type { ScreenshotEditor as Editor } from "@/hooks/useScreenshotEditor"
import { copyImage, revealPath, savePng } from "@/lib/daemon"
import { flatten, pngBytes } from "@/lib/screenshot-export"
import { suggestedName } from "@/lib/screenshot-editor"
import type { Rect } from "@/lib/screenshot-markup"

/**
 * The editor's bottom row.
 *
 * Two rows in one, as the Mac's is: while a crop is being drawn it offers
 * Cancel and Apply Crop, and otherwise New, Show in folder, the zoom trio,
 * Copy and Save. Nothing here writes a file until Copy or Save is pressed —
 * that is the promise the screen makes.
 */
export function ScreenshotActions({
  editor,
  cropping,
  cropRect,
  cropRotation,
  zoom,
  onZoom,
  onNew,
  onEndCrop,
}: {
  editor: Editor
  cropping: boolean
  cropRect: Rect | null
  cropRotation: number
  zoom: number
  onZoom: (zoom: number) => void
  onNew: () => void
  onEndCrop: () => void
}) {
  return (
    <div className="flex items-center gap-2 border-t border-border-subtle px-3 py-2">
      {cropping ? (
        <CropBar
          cropRect={cropRect}
          onCancel={onEndCrop}
          onApply={() => {
            if (cropRect === null) return
            editor.applyCrop(cropRect, cropRotation)
            onEndCrop()
          }}
        />
      ) : (
        <SaveBar editor={editor} zoom={zoom} onZoom={onZoom} onNew={onNew} />
      )}
    </div>
  )
}

function CropBar({
  cropRect,
  onCancel,
  onApply,
}: {
  cropRect: Rect | null
  onCancel: () => void
  onApply: () => void
}) {
  return (
    <>
      <span className="text-[12px] text-text-tertiary">Drag to choose a crop area</span>
      <div className="flex-1" />
      <Button onClick={onCancel}>Cancel</Button>
      <Button tone="primary" disabled={cropRect === null} onClick={onApply}>
        Apply Crop
      </Button>
    </>
  )
}

function SaveBar({
  editor,
  zoom,
  onZoom,
  onNew,
}: {
  editor: Editor
  zoom: number
  onZoom: (zoom: number) => void
  onNew: () => void
}) {
  const { show } = useNotifications()
  const image = editor.image

  /** The picture as it stands, markup burned in, at the image's own size. */
  const flatBytes = useCallback(
    () => (image === null ? null : pngBytes(flatten(image, editor.size, editor.annotations))),
    [editor.annotations, editor.size, image],
  )

  const report = (thrown: unknown) => {
    show({ message: String(thrown), ok: false })
  }

  return (
    <>
      <Button onClick={onNew}>
        <Camera size={13} /> New
      </Button>
      {editor.lastSavedPath === null ? null : (
        <Button
          onClick={() => {
            if (editor.lastSavedPath !== null) void revealPath(editor.lastSavedPath)
          }}
        >
          <FolderOpen size={13} /> Show in folder
        </Button>
      )}
      <div className="flex-1" />
      <ZoomControls zoom={zoom} onZoom={onZoom} />
      <Button
        onClick={() => {
          const bytes = flatBytes()
          if (bytes === null) return
          void bytes
            .then(async (png) => {
              await copyImage(png)
              editor.markSaved(null)
              show({ message: "Screenshot copied", ok: true })
            })
            .catch(report)
        }}
      >
        <Copy size={13} /> Copy
      </Button>
      <Button
        tone="primary"
        onClick={() => {
          const bytes = flatBytes()
          if (bytes === null) return
          void bytes
            .then(async (png) => {
              const path = await savePng(suggestedName(new Date()), png)
              if (path === null) return
              editor.markSaved(path)
              show({ message: "Screenshot saved", ok: true, revealPath: path })
            })
            .catch(report)
        }}
      >
        <Save size={13} /> Save…
      </Button>
    </>
  )
}
