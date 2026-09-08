import { useState } from "react"
import { House, Plus } from "lucide-react"
import { pastMidpointX, startDrag } from "@/components/dnd"
import { TabChip } from "@/components/TabChip"
import { cn } from "@/lib/cn"
import { HOME_TAB } from "@/lib/layout"
import { dropLanding, markerSlot } from "@/lib/pinning"
import { IS_MAC, shortcutLabel } from "@/lib/platform"
import { pinnedTabs, type TabState } from "@/lib/tabs"
import type { FeatureSummary } from "@/lib/wire"

export interface TabStripProps {
  /** Which pane this strip drives. */
  pane: number
  tabs: TabState
  /** True when this pane has keyboard focus — its strip is the lit one. */
  focused: boolean
  /** Feature lookup for a tab's title and icon. */
  featureByID: (id: string) => FeatureSummary | null
  onSelect: (id: string) => void
  onClose: (id: string) => void
  /** Unpin a pinned tab — the pin glyph sitting where its × would. */
  onUnpin: (id: string) => void
  /** A drop landing in this pane, before `target` (null = the end). */
  onDrop: (id: string, pane: number, target: string | null) => void
  onContextMenu: (id: string, x: number, y: number) => void
  /** Open the palette with this pane focused, so the choice lands here. */
  onNewTab: (pane: number) => void
  /** The tab being dragged anywhere in the window, so a strip can accept it. */
  dragging: string | null
  onDragState: (id: string | null) => void
}

/**
 * One pane's open tabs, left to right.
 *
 * Home leads the first pane as a permanent icon button rather than a chip, the
 * way it does on the Mac: it is where a closed last tab lands, so it cannot be
 * closed away.
 */
export function TabStrip(props: TabStripProps) {
  const [slot, setSlot] = useState<{ id: string; after: boolean } | null>(null)

  const chips = props.tabs.openTabs.filter((id) => id !== HOME_TAB)
  // The prefix length of `chips`. The drop clamp runs over the chips, not the
  // pane's own list, because Home is in the pane and is never a chip: clamped
  // against the pane, the boundary can come back as Home, and a marker on a
  // chip that is not drawn is no marker at all. Home is never pinned, so
  // dropping it from the list leaves the pinned tabs leading and this exact.
  const pinnedCount = pinnedTabs(props.tabs).length
  const endDrag = () => {
    props.onDragState(null)
    setSlot(null)
  }
  const strip = { chips, pinnedCount, props, setSlot }

  return (
    <div
      className={cn(
        "flex h-9 shrink-0 items-center border-b border-border-subtle px-1.5",
        props.focused ? "bg-bg-surface" : "bg-bg-chrome",
      )}
      onDragEnd={endDrag}
      // The dead space past the last chip accepts a drop too: it is the
      // natural way to drag a tab into the other pane.
      onDragOver={(event) => {
        if (props.dragging === null) return
        event.preventDefault()
      }}
      onDrop={(event) => {
        if (props.dragging === null) return
        event.preventDefault()
        const dragged = props.dragging
        endDrag()
        props.onDrop(dragged, props.pane, null)
      }}
    >
      {props.pane === 0 ? (
        <HomeButton
          active={props.tabs.activeTab === HOME_TAB}
          onSelect={() => {
            props.onSelect(HOME_TAB)
          }}
        />
      ) : null}

      <div className="flex min-w-0 flex-1 items-center gap-1 overflow-x-auto">
        {chips.map((id, index) => (
          <TabChip
            key={id}
            id={id}
            feature={props.featureByID(id)}
            active={id === props.tabs.activeTab}
            faded={props.dragging === id}
            pinned={index < pinnedCount}
            slot={slot?.id === id ? slot.after : null}
            onSelect={() => {
              props.onSelect(id)
            }}
            onClose={() => {
              props.onClose(id)
            }}
            onUnpin={() => {
              props.onUnpin(id)
            }}
            onContextMenu={(event) => {
              event.preventDefault()
              props.onContextMenu(id, event.clientX, event.clientY)
            }}
            {...chipDragProps(id, strip)}
          />
        ))}
        <NewTabButton
          onSelect={() => {
            props.onNewTab(props.pane)
          }}
        />
      </div>
    </div>
  )
}

/**
 * A chip's drag wiring — the only logic in what is otherwise a layout, and the
 * one place the marker and the drop are made to agree: both read the same
 * `dropLanding`, so the strip cannot promise a slot the drop then corrects.
 */
function chipDragProps(
  id: string,
  strip: {
    chips: readonly string[]
    pinnedCount: number
    props: TabStripProps
    setSlot: (slot: { id: string; after: boolean } | null) => void
  },
) {
  const { chips, pinnedCount, props, setSlot } = strip
  const landingAt = (event: React.DragEvent<HTMLElement>, dragged: string) =>
    dropLanding(dragged, id, pastMidpointX(event), chips, pinnedCount)
  return {
    onDragStart: (event: React.DragEvent<HTMLElement>) => {
      startDrag(event)
      props.onDragState(id)
    },
    onDragOver: (event: React.DragEvent<HTMLElement>) => {
      if (props.dragging === null) return
      event.preventDefault()
      setSlot(markerSlot(props.dragging, landingAt(event, props.dragging), chips))
    },
    onDrop: (event: React.DragEvent<HTMLElement>) => {
      if (props.dragging === null) return
      event.preventDefault()
      event.stopPropagation()
      const dragged = props.dragging
      const landing = landingAt(event, dragged)
      props.onDragState(null)
      setSlot(null)
      // A drop that resolves to the tab itself would not move it.
      if (landing === dragged) return
      props.onDrop(dragged, props.pane, landing)
    },
  }
}

/** The trailing +, which opens the palette with this pane focused. */
function NewTabButton({ onSelect }: { onSelect: () => void }) {
  return (
    <button
      type="button"
      onClick={onSelect}
      title={`New tab (${shortcutLabel("t", IS_MAC)})`}
      aria-label="New tab"
      className="flex size-7 shrink-0 items-center justify-center rounded-md text-text-tertiary transition-colors hover:bg-white/[0.05] hover:text-text-primary"
    >
      <Plus size={14} />
    </button>
  )
}

/** Home rides a permanent button, so it cannot be closed away or lost in the
 *  tab overflow — the same place it sits on the Mac. */
function HomeButton({ active, onSelect }: { active: boolean; onSelect: () => void }) {
  return (
    <>
      <button
        type="button"
        onClick={onSelect}
        title="Home"
        aria-label="Home"
        aria-current={active}
        className={cn(
          "flex size-7 shrink-0 items-center justify-center rounded-md transition-colors",
          active
            ? "bg-accent/15 text-accent"
            : "text-text-secondary hover:bg-white/[0.05] hover:text-text-primary",
        )}
      >
        <House size={14} />
      </button>
      <span className="mx-1.5 h-5 w-px shrink-0 bg-border-subtle" />
    </>
  )
}
