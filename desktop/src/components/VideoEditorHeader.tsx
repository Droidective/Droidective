import { Download, FileVideo, Redo2, Undo2 } from "lucide-react"
import { useState } from "react"
import { Button } from "@/components/Controls"
import { IconButton } from "@/components/Hub"
import type { VideoEditor } from "@/hooks/useVideoEditor"
import { asDaemonError } from "@/lib/daemon"
import { exportVideo } from "@/lib/daemon-video"
import { outputSeconds, timecode } from "@/lib/video-edit"

/**
 * The editor's top row: what is open, how long the result will run, undo/redo,
 * Open… and Export.
 *
 * The running time is the *output's*, not the source's — trimming and a speed
 * change both move it, and it is the number someone is usually aiming at.
 */
export function VideoEditorHeader({
  editor,
  duration,
  onOpen,
  onExported,
  onFailed,
}: {
  editor: VideoEditor
  duration: number
  onOpen: () => void
  onExported: (path: string) => void
  onFailed: (message: string) => void
}) {
  const [exporting, setExporting] = useState(false)
  const path = editor.path ?? ""

  return (
    <header className="flex items-center gap-2 border-b border-border-subtle px-3 py-2">
      <FileVideo size={14} className="shrink-0 text-text-tertiary" />
      <span className="min-w-0 flex-1 truncate text-[13px] text-text-primary" title={path}>
        {path.split(/[/\\]/u).pop()}
      </span>
      <span className="shrink-0 text-[11.5px] text-text-tertiary">
        {timecode(outputSeconds(editor.edit, duration))} out
      </span>
      <IconButton
        icon={<Undo2 size={14} />}
        label="Undo"
        disabled={!editor.canUndo}
        onClick={editor.undo}
      />
      <IconButton
        icon={<Redo2 size={14} />}
        label="Redo"
        disabled={!editor.canRedo}
        onClick={editor.redo}
      />
      <Button onClick={onOpen}>Open…</Button>
      <Button
        tone="primary"
        disabled={exporting}
        onClick={() => {
          setExporting(true)
          void exportVideo(path, editor.edit)
            .then((written) => {
              // A cancelled save dialog is a choice, not a failure.
              if (written !== null) onExported(written)
            })
            .catch((thrown: unknown) => {
              onFailed(asDaemonError(thrown).message)
            })
            .finally(() => {
              setExporting(false)
            })
        }}
      >
        <Download size={13} /> {exporting ? "Exporting…" : "Export"}
      </Button>
    </header>
  )
}
