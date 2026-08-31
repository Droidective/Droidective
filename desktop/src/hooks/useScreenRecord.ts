import { useCallback } from "react"

import { useNotifications } from "@/hooks/useNotifications"
import { useRecordSession, type RecordSession } from "@/hooks/useRecordSession"
import {
  asDaemonError,
  discardRecording,
  saveRecording,
  type StoppedRecording,
} from "@/lib/daemon"
import { recordingFileName } from "@/lib/record"

export interface ScreenRecord extends RecordSession {
  save: () => void
  discard: () => void
}

/**
 * The screen's whole model — the Mac's `ScreenRecordView` state.
 *
 * Two halves with different lifetimes: `useRecordSession` owns the recording,
 * and the pair below own the *file* it produced, which outlives the session and
 * is the only part that touches disk.
 */
export function useScreenRecord(): ScreenRecord {
  const session = useRecordSession()
  return { ...session, ...useRecordingDecision(session.finished, session.clearFinished) }
}

/**
 * Save and Discard, over a recording that has already stopped.
 *
 * Their own hook because they are the only part of this screen that touches
 * the finished *file* rather than the session — and because nothing is written
 * to the captures folder until Save, which is what makes Discard a real choice
 * rather than a delete.
 */
function useRecordingDecision(
  finished: StoppedRecording | null,
  clear: () => void,
): { save: () => void; discard: () => void } {
  const { show } = useNotifications()

  return {
    save: useCallback(() => {
      if (finished === null) return
      const name = recordingFileName(new Date())
      saveRecording(finished.path, name).then(
        (path) => {
          clear()
          show({ message: "Recording saved", ok: true, revealPath: path, important: true })
        },
        (thrown: unknown) => {
          show({
            message: `Couldn't save recording: ${asDaemonError(thrown).message}`,
            ok: false,
          })
        },
      )
    }, [finished, clear, show]),
    discard: useCallback(() => {
      if (finished === null) return
      void discardRecording(finished.path)
      clear()
    }, [finished, clear]),
  }
}
