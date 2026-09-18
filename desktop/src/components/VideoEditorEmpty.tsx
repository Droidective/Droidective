import { FileVideo } from "lucide-react"
import { Button } from "@/components/Controls"

/** What the video editor shows before a file has been chosen. */
export function VideoEditorEmpty({ onChoose }: { onChoose: () => void }) {
  return (
    <div className="flex h-full flex-col items-center justify-center gap-5 p-6 text-center">
      <div className="flex flex-col items-center gap-2.5">
        <FileVideo size={42} className="text-text-tertiary" />
        <h2 className="text-[17px] font-semibold text-text-primary">Edit a video</h2>
        <p className="max-w-md text-text-secondary">
          Trim, rotate, crop and compress a recording — the original is never changed, and nothing
          is written until you export.
        </p>
      </div>
      <Button tone="primary" onClick={onChoose}>
        Open a video…
      </Button>
    </div>
  )
}
