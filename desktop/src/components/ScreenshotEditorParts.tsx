import { ZoomIn, ZoomOut } from "lucide-react"
import { useCallback, useEffect, useRef, useState } from "react"
import { Button } from "@/components/Controls"
import { IconButton } from "@/components/Hub"
import type { ScreenshotEditor as Editor } from "@/hooks/useScreenshotEditor"
import { zoomIn, zoomOut } from "@/lib/screenshot-editor"
import type { Point, Rect, Size } from "@/lib/screenshot-markup"

/**
 * The editor's smaller pieces: the zoom trio, the label field, the undo
 * shortcuts, and the arithmetic that decides how big the picture is drawn.
 *
 * Split from `ScreenshotEditor` so the shell stays a layout rather than a
 * grab-bag; nothing here knows about the others.
 */

export function ZoomControls({ zoom, onZoom }: { zoom: number; onZoom: (zoom: number) => void }) {
  return (
    <div className="flex items-center gap-1">
      <IconButton
        icon={<ZoomOut size={14} />}
        label="Zoom out"
        onClick={() => {
          onZoom(zoomOut(zoom))
        }}
      />
      <Button
        onClick={() => {
          onZoom(1)
        }}
      >
        Fit
      </Button>
      <IconButton
        icon={<ZoomIn size={14} />}
        label="Zoom in"
        onClick={() => {
          onZoom(zoomIn(zoom))
        }}
      />
      <span className="w-11 text-right text-[11.5px] text-text-tertiary">
        {Math.round(zoom * 100)}%
      </span>
    </div>
  )
}

export function TextEntry({
  value,
  onChange,
  onCommit,
  onCancel,
}: {
  value: string
  onChange: (value: string) => void
  onCommit: () => void
  onCancel: () => void
}) {
  // Focused on appearing: the overlay exists only to take a label, and it came
  // up because someone clicked where they want to type. A ref rather than
  // `autoFocus`, which moves focus on every render the element survives.
  const field = useRef<HTMLInputElement>(null)
  useEffect(() => {
    field.current?.focus()
  }, [])

  return (
    <div className="absolute inset-x-0 bottom-2 mx-auto flex w-[min(420px,90%)] items-center gap-2 rounded-lg border border-border-subtle bg-bg-raised p-2 shadow-xl">
      <input
        ref={field}
        aria-label="Label text"
        value={value}
        placeholder="Label…"
        onChange={(event) => {
          onChange(event.target.value)
        }}
        onKeyDown={(event) => {
          if (event.key === "Enter") onCommit()
          if (event.key === "Escape") onCancel()
        }}
        className="min-w-0 flex-1 rounded-md border border-border-subtle bg-bg-root px-2 py-1 text-[13px] text-text-primary outline-none focus:border-accent"
      />
      <Button onClick={onCancel}>Cancel</Button>
      <Button tone="primary" onClick={onCommit}>
        Add
      </Button>
    </div>
  )
}

/** ⌘Z / ⇧⌘Z, which the Mac binds through its Edit menu. */
export function useUndoShortcuts(editor: Editor) {
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (!(event.metaKey || event.ctrlKey) || event.key.toLowerCase() !== "z") return
      // Not while a field has focus: ⌘Z there belongs to the text being typed.
      if (document.activeElement instanceof HTMLInputElement) return
      event.preventDefault()
      if (event.shiftKey) editor.redo()
      else editor.undo()
    }
    globalThis.addEventListener("keydown", onKeyDown)
    return () => {
      globalThis.removeEventListener("keydown", onKeyDown)
    }
  }, [editor])
}

/**
 * The size the image is drawn at: fit-to-view, times the zoom.
 *
 * 1.0 is fit rather than 100% of the pixels, which is the Mac's meaning — a
 * phone screenshot is taller than any window, so "actual size" as a starting
 * point would open every capture scrolled.
 */
export function fitted(image: Size, box: Size, zoom: number): Size {
  if (image.width <= 0 || image.height <= 0 || box.width <= 0 || box.height <= 0) {
    return { width: 0, height: 0 }
  }
  const fit = Math.min(box.width / image.width, box.height / image.height)
  return { width: image.width * fit * zoom, height: image.height * fit * zoom }
}

export function useMeasuredBox() {
  const ref = useRef<HTMLDivElement | null>(null)
  const [size, setSize] = useState({ width: 0, height: 0 })

  const measure = useCallback(() => {
    const element = ref.current
    if (element !== null) {
      setSize({ width: element.clientWidth - 24, height: element.clientHeight - 24 })
    }
  }, [])

  useEffect(() => {
    measure()
    const element = ref.current
    if (element === null) return
    const observer = new ResizeObserver(measure)
    observer.observe(element)
    return () => {
      observer.disconnect()
    }
  }, [measure])

  return { ...size, ref }
}

/**
 * Which mode the editor is in, and what is picked.
 *
 * Its own hook because the three modes are mutually exclusive and the
 * transitions between them clear things: choosing a tool leaves select mode,
 * opening the crop box drops the selection. Spreading those rules across the
 * shell is how a stale selection survives into a mode that has no use for one.
 */
export function useEditorModes() {
  const [zoom, setZoom] = useState(1)
  const [selecting, setSelecting] = useState(false)
  const [selectedID, setSelectedID] = useState<string | null>(null)
  const [cropping, setCropping] = useState(false)
  const [cropRect, setCropRect] = useState<Rect | null>(null)
  const [cropRotation, setCropRotation] = useState(0)
  const [textAt, setTextAt] = useState<Point | null>(null)
  const [textValue, setTextValue] = useState("")

  const endCrop = useCallback(() => {
    setCropping(false)
    setCropRect(null)
    setCropRotation(0)
  }, [])

  return {
    zoom,
    setZoom,
    selecting,
    selectedID,
    cropping,
    cropRect,
    cropRotation,
    textAt,
    textValue,
    setTextValue,
    select: setSelectedID,
    endCrop,
    chooseSelect: useCallback((on: boolean) => {
      setSelecting(on)
      setCropping(false)
      if (!on) setSelectedID(null)
    }, []),
    chooseCrop: useCallback(
      (on: boolean) => {
        endCrop()
        setCropping(on)
        setSelecting(false)
        setSelectedID(null)
      },
      [endCrop],
    ),
    setCrop: useCallback((rect: Rect | null, rotation: number) => {
      setCropRect(rect)
      setCropRotation(rotation)
    }, []),
    openText: useCallback((at: Point) => {
      setTextAt(at)
      setTextValue("")
    }, []),
    closeText: useCallback(() => {
      setTextAt(null)
      setTextValue("")
    }, []),
  }
}
