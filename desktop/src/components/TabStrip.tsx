import { useState } from "react"
import { House, X } from "lucide-react"
import { pastMidpointX, startDrag } from "@/components/dnd"
import { cn } from "@/lib/cn"
import { iconForCategory } from "@/lib/icons"
import { HOME_TAB } from "@/lib/layout"
import { dropTarget } from "@/lib/ordering"
import { IS_MAC, shortcutLabel } from "@/lib/platform"
import type { TabState } from "@/lib/tabs"
import type { FeatureSummary } from "@/lib/wire"

export interface TabStripProps {
  tabs: TabState
  /** Feature lookup for a tab's title and icon. */
  featureByID: (id: string) => FeatureSummary | null
  onSelect: (id: string) => void
  onClose: (id: string) => void
  onReorder: (id: string, before: string | null) => void
}

/**
 * The open tabs, left to right.
 *
 * Home leads the strip as a permanent icon button rather than a chip, the way
 * it does on the Mac: it is where a closed last tab lands, so it cannot itself
 * be closed away.
 */
export function TabStrip(props: TabStripProps) {
  const [dragging, setDragging] = useState<string | null>(null)
  const [slot, setSlot] = useState<{ id: string; after: boolean } | null>(null)

  const chips = props.tabs.openTabs.filter((id) => id !== HOME_TAB)
  const endDrag = () => {
    setDragging(null)
    setSlot(null)
  }

  return (
    <div
      className="flex h-9 shrink-0 items-center border-b border-border-subtle bg-bg-surface px-1.5"
      onDragEnd={endDrag}
    >
      <button
        type="button"
        onClick={() => {
          props.onSelect(HOME_TAB)
        }}
        title="Home"
        aria-label="Home"
        aria-current={props.tabs.activeTab === HOME_TAB}
        className={cn(
          "flex size-7 shrink-0 items-center justify-center rounded-md transition-colors",
          props.tabs.activeTab === HOME_TAB
            ? "bg-accent/15 text-accent"
            : "text-text-secondary hover:bg-white/[0.05] hover:text-text-primary",
        )}
      >
        <House size={14} />
      </button>
      <span className="mx-1.5 h-5 w-px shrink-0 bg-border-subtle" />

      <div className="flex min-w-0 flex-1 items-center gap-1 overflow-x-auto">
        {chips.map((id) => (
          <Chip
            key={id}
            id={id}
            feature={props.featureByID(id)}
            active={id === props.tabs.activeTab}
            faded={dragging === id}
            slot={slot?.id === id ? slot.after : null}
            onSelect={() => {
              props.onSelect(id)
            }}
            onClose={() => {
              props.onClose(id)
            }}
            onDragStart={(event) => {
              startDrag(event)
              setDragging(id)
            }}
            onDragOver={(event) => {
              if (dragging === null) return
              event.preventDefault()
              setSlot({ id, after: pastMidpointX(event) })
            }}
            onDrop={(event) => {
              if (dragging === null) return
              event.preventDefault()
              const after = pastMidpointX(event)
              const dragged = dragging
              endDrag()
              if (dragged === id && !after) return
              props.onReorder(dragged, dropTarget(id, after, chips))
            }}
          />
        ))}
      </div>
    </div>
  )
}

function Chip({
  id,
  feature,
  active,
  faded,
  slot,
  onSelect,
  onClose,
  onDragStart,
  onDragOver,
  onDrop,
}: {
  id: string
  feature: FeatureSummary | null
  active: boolean
  faded: boolean
  slot: boolean | null
  onSelect: () => void
  onClose: () => void
  onDragStart: (event: React.DragEvent<HTMLElement>) => void
  onDragOver: (event: React.DragEvent<HTMLElement>) => void
  onDrop: (event: React.DragEvent<HTMLElement>) => void
}) {
  // A tab whose feature has gone is still closable: showing its id beats
  // rendering a blank chip nobody can get rid of.
  const Icon = iconForCategory(feature?.category ?? "")
  return (
    <div
      draggable
      onDragStart={onDragStart}
      onDragOver={onDragOver}
      onDrop={onDrop}
      className={cn(
        "relative flex h-7 max-w-[190px] shrink-0 items-center gap-1.5 rounded-md pl-2.5 pr-1",
        active ? "bg-accent/15" : "hover:bg-white/[0.05]",
        faded ? "opacity-30" : "",
      )}
    >
      <button
        type="button"
        onClick={onSelect}
        aria-current={active}
        className="flex min-w-0 items-center gap-1.5"
      >
        <Icon size={13} className={cn("shrink-0", active ? "text-accent" : "text-text-secondary")} />
        <span
          className={cn(
            "truncate text-[12.5px]",
            active ? "text-text-primary" : "text-text-secondary",
          )}
        >
          {feature?.title ?? id}
        </span>
      </button>
      <button
        type="button"
        onClick={onClose}
        title={`Close tab (${shortcutLabel("w", IS_MAC)})`}
        aria-label={`Close ${feature?.title ?? id}`}
        className="flex size-4 shrink-0 items-center justify-center rounded text-text-tertiary hover:bg-white/10 hover:text-text-primary"
      >
        <X size={10} strokeWidth={3} />
      </button>
      {slot === null ? null : (
        <span
          className={cn(
            "pointer-events-none absolute inset-y-1 w-0.5 rounded-full bg-accent",
            slot ? "right-0" : "left-0",
          )}
        />
      )}
    </div>
  )
}
