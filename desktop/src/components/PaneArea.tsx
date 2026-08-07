import { Fragment, useCallback, useEffect, useRef, useState } from "react"
import { FeaturePane } from "@/components/FeaturePane"
import { TabStrip } from "@/components/TabStrip"
import { cn } from "@/lib/cn"
import { DIVIDER_WIDTH, fractionForDrag, leftWidth } from "@/lib/panes"
import type { TabState } from "@/lib/tabs"
import type { Device, FeatureSummary } from "@/lib/wire"
import { isSplit, type Workspace } from "@/lib/workspace"

export interface PaneAreaProps {
  workspace: Workspace
  features: FeatureSummary[]
  featureByID: (id: string) => FeatureSummary | null
  device: Device | null
  packageId: string | null
  onSelectPackage: (packageId: string | null) => void
  onOpen: (id: string) => void
  onClose: (id: string) => void
  onDrop: (id: string, pane: number, target: string | null) => void
  onSplit: (id: string) => void
  onFocusPane: (pane: number) => void
  onContextMenu: (id: string, x: number, y: number) => void
  onNewTab: (pane: number) => void
  sidebarOrder: string[]
  categoryOrder: string[]
  favorites: string[]
  disabledFeatures: string[]
  onSetEnabled: (id: string, enabled: boolean) => void
  onSetGroupEnabled: (members: FeatureSummary[], enabled: boolean) => void
  splitFraction: number
  onSplitFraction: (fraction: number) => void
}

/** The panes, and the seam between them when there are two. */
export function PaneArea(props: PaneAreaProps) {
  const [dragging, setDragging] = useState<string | null>(null)
  const area = useRef<HTMLDivElement>(null)
  const split = isSplit(props.workspace)
  const [width, setWidth] = useState(0)

  useEffect(() => {
    const element = area.current
    if (element === null) return
    const observer = new ResizeObserver(([entry]) => {
      setWidth(entry?.contentRect.width ?? 0)
    })
    observer.observe(element)
    return () => {
      observer.disconnect()
    }
  }, [])

  const onSplitFraction = props.onSplitFraction
  const onDividerDrag = useCallback(
    (event: React.PointerEvent<HTMLElement>) => {
      const box = area.current?.getBoundingClientRect()
      if (box === undefined) return
      // Deliberately no `setPointerCapture`: the divider is re-rendered on
      // every move, and a capture held by a node React may replace is a
      // capture that can be left behind. Window listeners see the whole drag
      // either way, and removing them on pointerup is the only cleanup needed.
      event.preventDefault()
      const onMove = (move: PointerEvent) => {
        onSplitFraction(fractionForDrag(move.clientX - box.left, box.width))
      }
      const onUp = () => {
        globalThis.removeEventListener("pointermove", onMove)
        globalThis.removeEventListener("pointerup", onUp)
      }
      globalThis.addEventListener("pointermove", onMove)
      globalThis.addEventListener("pointerup", onUp)
    },
    [onSplitFraction],
  )

  const first = leftWidth(width, props.splitFraction)
  const divider = (
    <hr
      aria-orientation="vertical"
      aria-label="Resize the panes"
      onPointerDown={onDividerDrag}
      style={{ width: DIVIDER_WIDTH }}
      className="m-0 h-auto shrink-0 cursor-col-resize border-0 border-l border-border-subtle bg-transparent hover:border-accent hover:bg-accent/20"
    />
  )

  return (
    <div ref={area} className="flex min-h-0 min-w-0 flex-1">
      {props.workspace.groups.map((group, pane) => (
        <Fragment key={pane}>
          {pane === 1 ? divider : null}
        <div
          className="flex min-h-0 min-w-0 flex-col"
          style={split && pane === 0 && width > 0 ? { width: first, flex: "none" } : { flex: 1 }}
          onPointerDownCapture={() => {
            props.onFocusPane(pane)
          }}
        >
          <TabStrip
            pane={pane}
            tabs={group}
            focused={pane === props.workspace.focusedGroup}
            featureByID={props.featureByID}
            onSelect={props.onOpen}
            onClose={props.onClose}
            onDrop={props.onDrop}
            onContextMenu={props.onContextMenu}
            onNewTab={props.onNewTab}
            dragging={dragging}
            onDragState={setDragging}
          />
          <PaneBody
            group={group}
            props={props}
            splitZone={
              split || dragging === null
                ? null
                : () => {
                    const dragged = dragging
                    setDragging(null)
                    props.onSplit(dragged)
                  }
            }
          />
        </div>
        </Fragment>
      ))}
    </div>
  )
}

/**
 * Drop a tab on the trailing edge of the only pane to split there. Scoped to a
 * strip along the edge and only rendered while a tab is in flight, so it can
 * never swallow a drop meant for the feature underneath.
 */
function SplitZone({ onDrop }: { onDrop: () => void }) {
  const [over, setOver] = useState(false)
  return (
    <div
      className={cn(
        "absolute inset-y-0 right-0 z-10 w-1/3 border-l-2 transition-colors",
        over ? "border-accent bg-accent/10" : "border-transparent",
      )}
      onDragOver={(event) => {
        event.preventDefault()
        setOver(true)
      }}
      onDragLeave={() => {
        setOver(false)
      }}
      onDrop={(event) => {
        event.preventDefault()
        setOver(false)
        onDrop()
      }}
    />
  )
}

/**
 * One pane's stack of tabs. Every open tab stays mounted and the inactive ones
 * are hidden rather than unmounted: a tab that re-read the app list or dropped
 * its log stream every time you looked away would not be a tab.
 */
function PaneBody({
  group,
  props,
  splitZone,
}: {
  group: TabState
  props: PaneAreaProps
  /** Non-null when dropping on this pane's trailing edge would split it. */
  splitZone: (() => void) | null
}) {
  return (
    <div className="relative flex min-h-0 flex-1 flex-col">
      {group.openTabs.map((id) => (
        <div
          key={id}
          className={cn(
            "min-h-0 flex-1",
            id === group.activeTab ? "flex flex-col bg-bg-root" : "hidden",
          )}
        >
          <FeaturePane
            id={id}
            feature={props.featureByID(id)}
            features={props.features}
            device={props.device}
            packageId={props.packageId}
            onSelectPackage={props.onSelectPackage}
            onOpen={props.onOpen}
            sidebarOrder={props.sidebarOrder}
            categoryOrder={props.categoryOrder}
            favorites={props.favorites}
            disabledFeatures={props.disabledFeatures}
            onSetEnabled={props.onSetEnabled}
            onSetGroupEnabled={props.onSetGroupEnabled}
          />
        </div>
      ))}
      {splitZone === null ? null : <SplitZone onDrop={splitZone} />}
    </div>
  )
}
