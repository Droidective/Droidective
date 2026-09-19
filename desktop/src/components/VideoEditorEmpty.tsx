import { FileVideo } from "lucide-react"
import { Button } from "@/components/Controls"

/**
 * What the video editor shows before a file has been chosen.
 *
 * The heading, the sentence and the button are `VideoEditorView.emptyState`'s,
 * word for word. They were rewritten here when the screen was ported, which is
 * the drift the parity rule exists to stop: the Mac's copy says what the editor
 * can *do* and where a clip comes from, and an empty state is the one screen
 * whose only job is to say that.
 */
export function VideoEditorEmpty({ onChoose }: { onChoose: () => void }) {
  return (
    <div className="flex h-full flex-col items-center justify-center gap-5 p-6 text-center">
      <div className="flex flex-col items-center gap-2.5">
        <FileVideo size={42} className="text-text-tertiary" />
        <h2 className="text-[17px] font-semibold text-text-primary">Edit a video</h2>
        <p className="max-w-md whitespace-pre-line text-text-secondary">
          {"Open a video to trim, rotate, crop, change speed, convert, and compress —\nor record one from Screen Record."}
        </p>
      </div>
      <Button tone="primary" onClick={onChoose}>
        Open video…
      </Button>
    </div>
  )
}
