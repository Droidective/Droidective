import { useCallback, useRef, useState } from "react"
import { VideoEditorControls } from "@/components/VideoEditorControls"
import { VideoEditorHeader } from "@/components/VideoEditorHeader"
import { VideoEditorEmpty } from "@/components/VideoEditorEmpty"
import { VideoStage } from "@/components/VideoStage"
import { useNotifications } from "@/hooks/useNotifications"
import { useVideoEditor } from "@/hooks/useVideoEditor"
import { asDaemonError, pickFile } from "@/lib/daemon"
import { videoFormats } from "@/lib/daemon-video"
import { hasEdits } from "@/lib/video-edit"

/**
 * The Mac's `VideoEditorPane`: trim, rotate, flip, crop, speed, mute, format
 * and compression over a video, exported through ffmpeg.
 *
 * Nothing is written until Export. The edit is non-destructive by construction
 * — it is a set of options handed to `VideoEditing`, which turns them into an
 * ffmpeg invocation — so the source file is never touched, and an export always
 * reads it rather than whatever the player happens to be showing.
 */
export function VideoEditorPane() {
  const editor = useVideoEditor()
  const [duration, setDuration] = useState(0)
  const [position, setPosition] = useState(0)
  const [cropping, setCropping] = useState(false)
  const { show } = useNotifications()
  const formats = useRef<string[] | null>(null)

  const choose = useCallback(() => {
    void (async () => {
      formats.current ??= await videoFormats()
      const picked = await pickFile("Video", formats.current)
      if (picked !== null) editor.open(picked)
    })().catch((thrown: unknown) => {
      show({ message: asDaemonError(thrown).message, ok: false })
    })
  }, [editor, show])

  if (editor.path === null) return <VideoEditorEmpty onChoose={choose} />

  const unsaved = hasEdits(editor.edit) && editor.edit !== editor.exportedEdit
  return (
    <div className="flex h-full flex-col">
      <VideoEditorHeader
        editor={editor}
        duration={duration}
        onOpen={choose}
        onExported={(written) => {
          editor.markExported()
          show({ message: "Video exported", ok: true, revealPath: written })
        }}
        onFailed={(message) => {
          show({ message, ok: false })
        }}
      />

      <VideoStage
        editor={editor}
        cropping={cropping}
        onCropping={setCropping}
        onDuration={setDuration}
        onPosition={setPosition}
      />

      <VideoEditorControls
        edit={editor.edit}
        apply={editor.apply}
        duration={duration}
        position={position}
        cropping={cropping}
        onCropping={setCropping}
      />

      {unsaved ? (
        <p className="border-t border-border-subtle px-3 py-1.5 text-[11.5px] text-text-tertiary">
          Edits are applied when you export — the original file is never changed.
        </p>
      ) : null}
    </div>
  )
}
