import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type Dispatch,
  type SetStateAction,
} from "react"
import { readVideo, removeVideoProxy, videoProxy } from "@/lib/daemon-video"
import { NO_EDITS, pushUndo, type EditState } from "@/lib/video-edit"

/**
 * How far the playback ladder has got.
 *
 * The rungs are the Mac's — the original, then a remux, then a transcode — but
 * the *decision* is here rather than in the daemon: only the player can say
 * whether a file plays, and it says so by failing.
 */
export type PlaybackStage = "original" | "remuxing" | "remuxed" | "transcoding" | "transcoded" | "failed"

export interface VideoEditor {
  path: string | null
  /** A blob URL for the `<video>`, or null while one is being prepared. */
  url: string | null
  stage: PlaybackStage
  /** Why the file could not be loaded at all, as opposed to not played. */
  error: string | null
  edit: EditState
  canUndo: boolean
  canRedo: boolean

  open: (path: string) => void
  close: () => void
  /** Change the edit, recording an undo step. */
  apply: (change: (edit: EditState) => EditState) => void
  undo: () => void
  redo: () => void
  /** The player could not play what it was given — climb a rung. */
  reportUnplayable: () => void
  markExported: () => void
  exportedEdit: EditState | null
}

export function useVideoEditor(): VideoEditor {
  const [path, setPath] = useState<string | null>(null)
  const [stage, setStage] = useState<PlaybackStage>("original")
  const [edit, setEdit] = useState<EditState>(NO_EDITS)
  const [undoStack, setUndoStack] = useState<EditState[]>([])
  const [redoStack, setRedoStack] = useState<EditState[]>([])
  const [exportedEdit, setExportedEdit] = useState<EditState | null>(null)

  const playback = usePlayback(path, setStage)
  const history = useEditHistory(setEdit, setUndoStack, setRedoStack)

  /** Start on a file, or on nothing — "Open…" and closing are the same move. */
  const reset = useCallback(
    (next: string | null) => {
      playback.reset()
      setPath(next)
      setStage("original")
      setEdit(NO_EDITS)
      setUndoStack([])
      setRedoStack([])
      setExportedEdit(null)
    },
    [playback],
  )

  return {
    path,
    url: playback.url,
    stage,
    error: playback.error,
    edit,
    exportedEdit,
    canUndo: undoStack.length > 0,
    canRedo: redoStack.length > 0,
    open: useCallback(
      (next: string) => {
        reset(next)
      },
      [reset],
    ),
    close: useCallback(() => {
      reset(null)
    }, [reset]),
    reportUnplayable: useCallback(() => {
      playback.climb(stage)
    }, [playback, stage]),
    ...history,
    markExported: useCallback(() => {
      setExportedEdit(edit)
    }, [edit]),
  }
}

/**
 * Apply, undo and redo over one edit.
 *
 * Its own hook so `useVideoEditor` stays in budget, and because the three are
 * one mechanism: every change pushes the edit it replaced, and the two
 * directions are the same move with the stacks swapped.
 */
function useEditHistory(
  setEdit: Dispatch<SetStateAction<EditState>>,
  setUndoStack: Dispatch<SetStateAction<EditState[]>>,
  setRedoStack: Dispatch<SetStateAction<EditState[]>>,
) {
  const step = useCallback(
    (from: Dispatch<SetStateAction<EditState[]>>, to: Dispatch<SetStateAction<EditState[]>>) => {
      from((stack) => {
        const target = stack.at(-1)
        if (target === undefined) return stack
        setEdit((current) => {
          to((other) => pushUndo(other, current))
          return target
        })
        return stack.slice(0, -1)
      })
    },
    [setEdit],
  )

  return {
    apply: useCallback(
      (change: (edit: EditState) => EditState) => {
        setEdit((current) => {
          setUndoStack((stack) => pushUndo(stack, current))
          setRedoStack([])
          return change(current)
        })
      },
      [setEdit, setRedoStack, setUndoStack],
    ),
    undo: useCallback(() => {
      step(setUndoStack, setRedoStack)
    }, [setRedoStack, setUndoStack, step]),
    redo: useCallback(() => {
      step(setRedoStack, setUndoStack)
    }, [setRedoStack, setUndoStack, step]),
  }
}

/**
 * The blob the player reads from, and the proxy ladder behind it.
 *
 * Separate from the edit because the two change for different reasons: an edit
 * is what the user chose, and this is the machinery that got a picture on
 * screen at all. Both the proxy on disk and the blob in memory are ours to
 * clean up — a transcoded recording is the size of the original.
 */
function usePlayback(path: string | null, setStage: Dispatch<SetStateAction<PlaybackStage>>) {
  const [url, setUrl] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const proxyPath = useRef<string | null>(null)
  const objectUrl = useRef<string | null>(null)

  const releaseUrl = useCallback(() => {
    if (objectUrl.current !== null) URL.revokeObjectURL(objectUrl.current)
    objectUrl.current = null
  }, [])

  const discardProxy = useCallback(() => {
    const previous = proxyPath.current
    proxyPath.current = null
    // Best-effort: a proxy is scratch, and failing to delete one is not worth
    // telling anybody about.
    if (previous !== null) void removeVideoProxy(previous).catch(() => {})
  }, [])

  const load = useCallback(
    async (from: string) => {
      const bytes = await readVideo(from)
      releaseUrl()
      const made = URL.createObjectURL(new Blob([bytes], { type: "video/mp4" }))
      objectUrl.current = made
      setUrl(made)
    },
    [releaseUrl],
  )

  // The source changed: read it, and let the player decide whether it plays.
  useEffect(() => {
    if (path === null) {
      setUrl(null)
      setError(null)
      return
    }
    setError(null)
    void load(path).catch((thrown: unknown) => {
      setError(String(thrown))
    })
  }, [load, path])

  // Both outlive a render, neither outlives the pane.
  useEffect(
    () => () => {
      discardProxy()
      releaseUrl()
    },
    [discardProxy, releaseUrl],
  )

  return {
    url,
    error,
    reset: useCallback(() => {
      discardProxy()
      releaseUrl()
      setUrl(null)
      setError(null)
    }, [discardProxy, releaseUrl]),
    /**
     * Climb a rung.
     *
     * Each step builds a new file and points the player at it; when the last
     * one still will not play, the editor says so rather than showing a black
     * pane — the Mac's `proxyFailed` exactly.
     */
    climb: useCallback(
      (stage: PlaybackStage) => {
        if (path === null) return
        const next = stage === "original" ? "remux" : stage === "remuxed" ? "transcode" : null
        if (next === null) {
          setStage("failed")
          return
        }
        setStage(next === "remux" ? "remuxing" : "transcoding")
        void videoProxy(path, next)
          .then(async (built) => {
            discardProxy()
            proxyPath.current = built
            await load(built)
            setStage(next === "remux" ? "remuxed" : "transcoded")
          })
          .catch(() => {
            setStage("failed")
          })
      },
      [discardProxy, load, path, setStage],
    ),
  }
}
