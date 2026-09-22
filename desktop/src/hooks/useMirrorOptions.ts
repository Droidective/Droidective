import { useCallback, useEffect, useState } from "react"

import { useNotifications } from "@/hooks/useNotifications"
import { FULL_QUALITY, type Quality } from "@/lib/mirror-wall"
import { useWindows } from "@/hooks/useWindows"
import { asDaemonError, writeDevSetting } from "@/lib/daemon"

const SHOW_TOUCHES = "droidective.mirrorShowTouches"
const STREAM_AUDIO = "droidective.mirrorStreamAudio"

/**
 * The mirror's session options — the Mac's ⋯ menu.
 *
 * Stream audio and Show touches. The Mac's third, Microphone, is the device's
 * *own* mic as the captured source; scrcpy carries one audio stream per
 * session, so it and Stream audio are mutually exclusive there. It is not
 * offered here yet, and a toggle with nothing behind it is worse than its
 * absence.
 *
 * **Stream audio restarts the mirror**, and the Mac's label says so, because
 * scrcpy takes audio as a *start* option rather than something a live session
 * can be asked for.
 *
 * Show touches is a *live settings write* on the device, not a scrcpy start
 * option — the same call Developer Options makes, which is why flipping it on
 * mid-recording works and needs no reconnect. The choice is remembered
 * (`mirrorShowTouches` on the Mac) and re-applied when the device changes, so
 * switching devices does not silently leave it off on the new one.
 */
export interface MirrorOptions {
  /**
   * What to hand `useMirror`: the single mirror's quality, carrying the audio
   * choice. Here rather than at the call site so the two cannot disagree about
   * whether sound was asked for.
   */
  quality: Quality
  /** Whether the session carries the device's sound. Restarts it when flipped. */
  streamAudio: boolean
  setStreamAudio: (on: boolean) => void
  showTouches: boolean
  setShowTouches: (on: boolean) => void
}

export function useMirrorOptions(serial: string | null): MirrorOptions {
  const { show } = useNotifications()
  const [showTouches, setStored] = useState(() => readFlag(SHOW_TOUCHES))
  const [streamAudio, setStreamAudio] = useState(() => readFlag(STREAM_AUDIO))

  const write = useCallback(
    (on: boolean) => {
      if (serial === null) return
      writeDevSetting({ serial, id: "show-touches", on }).catch((thrown: unknown) => {
        show({ message: asDaemonError(thrown).message, ok: false })
      })
    },
    [serial, show],
  )

  // Re-applied on a device change, and only when it is on: writing `false` to
  // every device the selection passes through would turn off a setting someone
  // had switched on in Developer Options themselves.
  useEffect(() => {
    if (showTouches) write(true)
  }, [showTouches, write])

  return {
    quality: { ...FULL_QUALITY, audio: streamAudio },
    streamAudio,
    setStreamAudio: (on: boolean) => {
      setStreamAudio(on)
      writeFlag(STREAM_AUDIO, on)
    },
    showTouches,
    setShowTouches: (on: boolean) => {
      setStored(on)
      writeFlag(SHOW_TOUCHES, on)
      write(on)
    },
  }
}

function readFlag(key: string): boolean {
  try {
    return globalThis.localStorage.getItem(key) === "true"
  } catch {
    return false
  }
}

function writeFlag(key: string, on: boolean): void {
  try {
    globalThis.localStorage.setItem(key, String(on))
  } catch {
    // A preference that cannot be saved still applies for this session.
  }
}

/**
 * Open this device's mirror in a window of its own.
 *
 * Pinned to the serial rather than following the device bar: the point of a
 * pop-out is watching one device while the window behind it does something
 * else. Undefined with no device — there would be nothing to pin it to, and a
 * button that opened an empty window reads as broken.
 */
export function useMirrorPopOut(serial: string | null): (() => void) | undefined {
  const windows = useWindows()
  if (serial === null) return undefined
  return () => {
    windows.newWindow(serial, "scrcpy")
  }
}
