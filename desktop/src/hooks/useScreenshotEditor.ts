import { useCallback, useState, type Dispatch, type SetStateAction } from "react"
import {
  commitDraft,
  committedText,
  DEFAULT_SETTINGS,
  pushUndo,
  type DrawSettings,
  type Snapshot,
} from "@/lib/screenshot-editor"
import { cropped, flatten, turned } from "@/lib/screenshot-export"
import type { Annotation, Point, Rect, Size } from "@/lib/screenshot-markup"

/**
 * The base image.
 *
 * Both halves of the union are a `CanvasImageSource` carrying its own pixel
 * dimensions: a capture decodes to an `ImageBitmap`, and a crop or a rotate
 * produces a canvas. Casting one to the other would be a lie the compiler
 * would stop catching.
 */
export type EditorImage = ImageBitmap | HTMLCanvasElement

type Setter = (stack: Snapshot[]) => void

/**
 * The screenshot being annotated.
 *
 * The Mac keeps this in a `ScreenshotEditorModel` held by the window rather
 * than by the view, because everything in it is unsaved work — the capture,
 * the markup, and the undo history that can take either back. This app has no
 * tab-moving to lose it to, so it is ordinary state; what it keeps from the
 * Mac is *which* state exists and what each transition does to it.
 */
export interface ScreenshotEditor {
  image: EditorImage | null
  size: Size
  annotations: Annotation[]
  settings: DrawSettings
  canUndo: boolean
  canRedo: boolean
  dirty: boolean
  lastSavedPath: string | null

  open: (image: EditorImage) => void
  close: () => void
  setSettings: (settings: DrawSettings) => void
  /** Add a finished draft, unless it was too small to have been meant. */
  commit: (draft: Annotation) => void
  /** Add a text label, unless it is blank. */
  placeText: (at: Point, text: string) => void
  /** Replace one annotation in place — a move, resize or rotate. */
  replace: (annotation: Annotation, recordUndo: boolean) => void
  remove: (id: string) => void
  clearAll: () => void
  /** Burn the markup in and cut to a normalized rect. */
  applyCrop: (rect: Rect, rotation: number) => void
  /** A quarter-turn. Markup does not survive it — see `rotateImage`. */
  rotateImage: (clockwise: boolean) => void
  undo: () => void
  redo: () => void
  markSaved: (path: string | null) => void
}

export function useScreenshotEditor(): ScreenshotEditor {
  const [image, setImage] = useState<EditorImage | null>(null)
  const [size, setSize] = useState<Size>({ width: 0, height: 0 })
  const [annotations, setAnnotations] = useState<Annotation[]>([])
  const [settings, setSettings] = useState<DrawSettings>(DEFAULT_SETTINGS)
  const [undoStack, setUndoStack] = useState<Snapshot[]>([])
  const [redoStack, setRedoStack] = useState<Snapshot[]>([])
  const [dirty, setDirty] = useState(false)
  const [lastSavedPath, setLastSavedPath] = useState<string | null>(null)

  /**
   * Record the current state, then let the caller change it.
   *
   * A snapshot is the (image, annotations) pair rather than the annotations
   * alone, so undo also reverses a crop or a rotate — the Mac's `EditorSnapshot`
   * makes the same choice, and it is what stops Undo after a crop looking like
   * it did nothing.
   */
  const snapshot = useCallback(() => {
    if (image === null) return
    setUndoStack((stack) => pushUndo(stack, { image, size, annotations }))
    setRedoStack([])
    setDirty(true)
  }, [annotations, image, size])

  /** Start over, on a capture or on nothing — "New" is the second. */
  const reset = useCallback((next: EditorImage | null) => {
    setImage(next)
    setSize(next === null ? { width: 0, height: 0 } : { width: next.width, height: next.height })
    setAnnotations([])
    setUndoStack([])
    setRedoStack([])
    setDirty(false)
    setLastSavedPath(null)
  }, [])

  const open = useCallback(
    (next: EditorImage) => {
      reset(next)
    },
    [reset],
  )

  const close = useCallback(() => {
    reset(null)
  }, [reset])

  const replaceImage = useCallback(
    (canvas: HTMLCanvasElement) => {
      snapshot()
      setImage(canvas)
      setSize({ width: canvas.width, height: canvas.height })
      // Markup does not survive: a crop has already burned it into the new
      // image, and a quarter-turn would leave every annotation positioned for
      // an orientation that no longer exists. Both are the Mac's behaviour.
      setAnnotations([])
    },
    [snapshot],
  )

  const markupEdits = useMarkupEdits(settings, snapshot, setAnnotations, setDirty, annotations)
  const imageEdits = useImageEdits({
    image,
    size,
    annotations,
    undoStack,
    redoStack,
    replaceImage,
    setImage,
    setSize,
    setAnnotations,
    setUndoStack,
    setRedoStack,
    setDirty,
  })

  return {
    image,
    size,
    annotations,
    settings,
    canUndo: undoStack.length > 0,
    canRedo: redoStack.length > 0,
    dirty,
    lastSavedPath,
    open,
    close,
    setSettings,
    ...markupEdits,
    ...imageEdits,
    markSaved: useCallback((path: string | null) => {
      setDirty(false)
      if (path !== null) setLastSavedPath(path)
    }, []),
  }
}

/**
 * The edits that only touch the markup.
 *
 * Its own hook so `useScreenshotEditor` stays inside its line budget, and
 * because these five share one property the image edits do not: every one of
 * them records an undo step and leaves the base image alone.
 */
function useMarkupEdits(
  settings: DrawSettings,
  snapshot: () => void,
  setAnnotations: Dispatch<SetStateAction<Annotation[]>>,
  setDirty: Dispatch<SetStateAction<boolean>>,
  annotations: readonly Annotation[],
) {
  return {
    commit: useCallback(
      (draft: Annotation) => {
        const kept = commitDraft(draft)
        if (kept === null) return
        snapshot()
        setAnnotations((current) => [...current, kept])
      },
      [setAnnotations, snapshot],
    ),
    placeText: useCallback(
      (at: Point, text: string) => {
        const made = committedText(settings, at, text)
        if (made === null) return
        snapshot()
        setAnnotations((current) => [...current, made])
      },
      [setAnnotations, settings, snapshot],
    ),
    replace: useCallback(
      (next: Annotation, recordUndo: boolean) => {
        if (recordUndo) snapshot()
        setAnnotations((current) => current.map((a) => (a.id === next.id ? next : a)))
        setDirty(true)
      },
      [setAnnotations, setDirty, snapshot],
    ),
    remove: useCallback(
      (id: string) => {
        snapshot()
        setAnnotations((current) => current.filter((a) => a.id !== id))
      },
      [setAnnotations, snapshot],
    ),
    clearAll: useCallback(() => {
      if (annotations.length === 0) return
      snapshot()
      setAnnotations([])
    }, [annotations.length, setAnnotations, snapshot]),
  }
}

interface ImageEditDeps {
  image: EditorImage | null
  size: Size
  annotations: Annotation[]
  undoStack: Snapshot[]
  redoStack: Snapshot[]
  replaceImage: (canvas: HTMLCanvasElement) => void
  setImage: Dispatch<SetStateAction<EditorImage | null>>
  setSize: Dispatch<SetStateAction<Size>>
  setAnnotations: Dispatch<SetStateAction<Annotation[]>>
  setUndoStack: Dispatch<SetStateAction<Snapshot[]>>
  setRedoStack: Dispatch<SetStateAction<Snapshot[]>>
  setDirty: Dispatch<SetStateAction<boolean>>
}

/**
 * The edits that replace the base image, and the two that step through the
 * history.
 *
 * All four are the same shape — swap in a different image, size and annotation
 * list together — which is why they live here rather than beside the markup
 * edits: undo and redo differ only in which stack they move from.
 */
function useImageEdits(deps: ImageEditDeps) {
  const { image, size, annotations, replaceImage } = deps

  const step = useCallback(
    (from: Snapshot[], to: Snapshot[], setFrom: Setter, setTo: Setter) => {
      const target = from.at(-1)
      if (target === undefined || image === null) return
      setFrom(from.slice(0, -1))
      setTo(pushUndo(to, { image, size, annotations }))
      deps.setImage(target.image)
      deps.setSize(target.size)
      deps.setAnnotations(target.annotations)
      deps.setDirty(true)
    },
    [annotations, deps, image, size],
  )

  return {
    applyCrop: useCallback(
      (rect: Rect, rotation: number) => {
        if (image === null) return
        replaceImage(cropped(flatten(image, size, annotations), size, rect, rotation))
      },
      [annotations, image, replaceImage, size],
    ),
    rotateImage: useCallback(
      (clockwise: boolean) => {
        if (image === null) return
        replaceImage(turned(flatten(image, size, annotations), size, clockwise))
      },
      [annotations, image, replaceImage, size],
    ),
    undo: useCallback(() => {
      step(deps.undoStack, deps.redoStack, deps.setUndoStack, deps.setRedoStack)
    }, [deps, step]),
    redo: useCallback(() => {
      step(deps.redoStack, deps.undoStack, deps.setRedoStack, deps.setUndoStack)
    }, [deps, step]),
  }
}
