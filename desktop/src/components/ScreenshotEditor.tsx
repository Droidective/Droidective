import { ScreenshotActions } from "@/components/ScreenshotActions"
import { ScreenshotCanvas } from "@/components/ScreenshotCanvas"
import {
  fitted,
  TextEntry,
  useEditorModes,
  useMeasuredBox,
  useUndoShortcuts,
} from "@/components/ScreenshotEditorParts"
import { ScreenshotToolbar } from "@/components/ScreenshotToolbar"
import { useScreenshotGestures, type Mode } from "@/hooks/useScreenshotGestures"
import type { ScreenshotEditor as Editor } from "@/hooks/useScreenshotEditor"
import { trashAction } from "@/lib/screenshot-editor"

/**
 * The Mac's `ScreenshotEditorView`.
 *
 * A toolbar, the picture, and an action bar. Nothing is written to disk until
 * Save or Copy, which is the promise the screen makes and the reason the
 * capture arrives as bytes rather than a path.
 */
export function ScreenshotEditor({ editor, onNew }: { editor: Editor; onNew: () => void }) {
  const modes = useEditorModes()
  const { width, height, ref } = useMeasuredBox()

  const image = editor.image
  const selected = editor.annotations.find((a) => a.id === modes.selectedID) ?? null
  const mode: Mode = modes.cropping ? "crop" : modes.selecting ? "select" : "draw"

  const gestures = useScreenshotGestures({
    mode,
    settings: editor.settings,
    annotations: editor.annotations,
    selectedID: modes.selectedID,
    onSelect: modes.select,
    onCommit: editor.commit,
    onPlaceText: modes.openText,
    onReplace: editor.replace,
    cropRect: modes.cropRect,
    cropRotation: modes.cropRotation,
    onCrop: modes.setCrop,
  })

  useUndoShortcuts(editor)

  if (image === null) return null
  const display = fitted(editor.size, { width, height }, modes.zoom)

  return (
    <div className="flex h-full flex-col">
      <ScreenshotToolbar
        settings={editor.settings}
        onSettings={editor.setSettings}
        selecting={modes.selecting}
        onSelecting={modes.chooseSelect}
        selected={selected}
        cropping={modes.cropping}
        onCropping={modes.chooseCrop}
        annotations={editor.annotations}
        canUndo={editor.canUndo}
        canRedo={editor.canRedo}
        onUndo={editor.undo}
        onRedo={editor.redo}
        onRotate={editor.rotateImage}
        onReplaceSelected={editor.replace}
        onBack={onNew}
        onTrash={() => {
          const what = trashAction(modes.selecting, modes.selectedID, editor.annotations)
          if (what.action === "delete" && modes.selectedID !== null) {
            editor.remove(modes.selectedID)
            modes.select(null)
          } else editor.clearAll()
        }}
      />

      <div ref={ref} className="relative min-h-0 flex-1 overflow-auto bg-black/25 p-3">
        <div className="flex min-h-full items-center justify-center">
          <ScreenshotCanvas
            image={image}
            imageSize={editor.size}
            display={display}
            annotations={editor.annotations}
            draft={gestures.draft}
            selected={selected}
            cropRect={modes.cropRect}
            cropRotation={modes.cropRotation}
            onPointerDown={gestures.down}
            onPointerMove={gestures.move}
            onPointerUp={gestures.up}
          />
        </div>
        {modes.textAt === null ? null : (
          <TextEntry
            value={modes.textValue}
            onChange={modes.setTextValue}
            onCommit={() => {
              if (modes.textAt !== null) editor.placeText(modes.textAt, modes.textValue)
              modes.closeText()
            }}
            onCancel={modes.closeText}
          />
        )}
      </div>

      <ScreenshotActions
        editor={editor}
        cropping={modes.cropping}
        cropRect={modes.cropRect}
        cropRotation={modes.cropRotation}
        zoom={modes.zoom}
        onZoom={modes.setZoom}
        onNew={onNew}
        onEndCrop={modes.endCrop}
      />
    </div>
  )
}
