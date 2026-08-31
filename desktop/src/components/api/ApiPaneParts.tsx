import { useCallback, useEffect, useRef, useState } from "react"
import { CircleAlert, TriangleAlert } from "lucide-react"

import { ApiSidebar, type SidebarActions, type SidebarSection } from "@/components/api/ApiSidebar"
import type { ApiClientData } from "@/lib/api/model"
import { leadingLength, SIDEBAR_MAX, SIDEBAR_MIN, sidebarWidth } from "@/lib/api/layout"
import { cn } from "@/lib/cn"

/**
 * The API pane's own furniture: its two strips, its split, its seams, and the
 * measurement the layout thresholds read.
 *
 * Split from `ApiClientPane` so that file stays what it is — an arrangement of
 * the four regions and nothing else.
 */

/**
 * The two strips above the split.
 *
 * A failed save used to be swallowed, so collections and history would quietly
 * not be there at the next launch; the warnings are the builder's own notes
 * about what it did with the request.
 */
export function ApiStrips({
  persistFailure,
  onRetry,
  warnings,
}: {
  persistFailure: string | null
  onRetry: () => void
  warnings: string[]
}) {
  return (
    <>
      {persistFailure === null ? null : (
        <div className="flex items-start gap-1.5 bg-danger/10 px-3 py-1.5">
          <CircleAlert size={12} className="mt-0.5 shrink-0 text-danger" />
          <span data-selectable className="text-[12px] text-text-primary">
            {persistFailure}
          </span>
          <button
            type="button"
            onClick={onRetry}
            className="ml-auto text-[12px] text-accent hover:underline"
          >
            Retry
          </button>
        </div>
      )}
      {warnings.length === 0 ? null : (
        <div className="space-y-0.5 bg-warn/10 px-3 py-1.5">
          {warnings.map((warning) => (
            <p key={warning} className="flex items-start gap-1.5 text-[12px] text-text-secondary">
              <TriangleAlert size={11} className="mt-0.5 shrink-0 text-warn" />
              {warning}
            </p>
          ))}
        </div>
      )}
    </>
  )
}

/**
 * The editor/response seam. Stacked when narrow, so it runs the other way and
 * the fraction is of height rather than width — as the Mac's `splitBody` does.
 */
export function ApiSplit({
  narrow,
  width,
  fraction,
  onBeginDrag,
  editor,
  response,
}: {
  narrow: boolean
  width: number
  fraction: number
  onBeginDrag: (position: number) => void
  editor: React.ReactNode
  response: React.ReactNode
}) {
  if (narrow) {
    return (
      <div className="flex min-h-0 flex-1 flex-col">
        <div className="min-h-0 flex-1">{editor}</div>
        <div className="h-px bg-border-subtle" />
        <div className="min-h-0 flex-1">{response}</div>
      </div>
    )
  }
  return (
    <div className="flex min-h-0 flex-1">
      <div style={{ width: leadingLength(width, fraction) }} className="min-w-0 shrink-0">
        {editor}
      </div>
      <Seam axis="vertical" label="Resize the request pane" onBegin={onBeginDrag} />
      <div className="min-w-0 flex-1">{response}</div>
    </div>
  )
}

/**
 * A draggable divider.
 *
 * A button rather than a bare div so it is reachable and named; the drag is
 * pointer events, because that is the one gesture a webview reports the same
 * way on both platforms.
 */
export function Seam({
  axis,
  label,
  onBegin,
}: {
  axis: "vertical" | "horizontal"
  label: string
  onBegin: (position: number) => void
}) {
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      onPointerDown={(event) => {
        event.preventDefault()
        onBegin(axis === "vertical" ? event.clientX : event.clientY)
      }}
      className={cn(
        "shrink-0 bg-border-subtle transition hover:bg-accent",
        axis === "vertical" ? "w-px cursor-col-resize hover:w-0.5" : "h-px cursor-row-resize",
      )}
    />
  )
}

/** The pane's own width, for the two layout thresholds. */
export function useMeasuredWidth() {
  const ref = useRef<HTMLDivElement | null>(null)
  const [width, setWidth] = useState(0)

  const measure = useCallback(() => {
    if (ref.current !== null) setWidth(ref.current.clientWidth)
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

  return { width, ref }
}

/**
 * The sidebar and the seam that resizes it.
 *
 * On a narrow pane it overlays instead of taking width, which is what the
 * Mac's `narrowSidebarOverlay` does — below about 760 points there is not
 * enough room for three columns.
 */
export function ApiSidebarRegion({
  data,
  section,
  onSection,
  actions,
  shown,
  narrow,
  width,
  storedWidth,
  onBeginDrag,
}: {
  data: ApiClientData
  section: SidebarSection
  onSection: (section: SidebarSection) => void
  actions: SidebarActions
  shown: boolean
  narrow: boolean
  width: number
  storedWidth: number
  onBeginDrag: (position: number, resolve: (start: number, moved: number) => number) => void
}) {
  if (!shown) return null
  return (
    <>
      <div
        style={{ width: sidebarWidth(storedWidth, width) }}
        className={cn("shrink-0", narrow ? "absolute left-0 top-0 z-30 h-full shadow-xl" : "")}
      >
        <ApiSidebar data={data} section={section} onSection={onSection} actions={actions} />
      </div>
      {narrow ? null : (
        <Seam
          axis="vertical"
          label="Resize the sidebar"
          onBegin={(position) => {
            onBeginDrag(position, (start, moved) =>
              Math.min(SIDEBAR_MAX, Math.max(SIDEBAR_MIN, start + moved)),
            )
          }}
        />
      )}
    </>
  )
}

/** Re-exported so the pane names the region and its section in one import. */
export type { SidebarSection }
