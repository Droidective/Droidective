import { useMemo, useState } from "react"
import { Search } from "lucide-react"
import {
  SidebarSection,
  type Dragging,
  type DropSlot,
} from "@/components/SidebarSection"
import { applyDrop } from "@/lib/ordering"
import { sidebarSections } from "@/lib/sidebar"
import type { FeatureSummary } from "@/lib/wire"

export interface SidebarProps {
  features: FeatureSummary[]
  activeID: string | null
  onOpen: (id: string) => void
  sidebarOrder: string[]
  categoryOrder: string[]
  collapsedCategories: string[]
  onSidebarOrder: (order: string[]) => void
  onCategoryOrder: (order: string[]) => void
  onToggleCollapsed: (category: string) => void
}

/**
 * The grouped feature sidebar: search over category sections, each collapsible,
 * with rows that drag to reorder inside their group and headers that drag the
 * whole group.
 *
 * A feature drag is deliberately confined to its own category. Letting one
 * cross would mean overriding the category the registry assigned, which is not
 * something this app can persist — so the drop is refused rather than landing
 * somewhere the next render undoes.
 */
export function Sidebar(props: SidebarProps) {
  const [query, setQuery] = useState("")
  const [dragging, setDragging] = useState<Dragging | null>(null)
  const [slot, setSlot] = useState<DropSlot | null>(null)

  const searching = query.trim() !== ""
  const sections = useMemo(
    () =>
      sidebarSections(props.features, {
        query,
        sidebarOrder: props.sidebarOrder,
        categoryOrder: props.categoryOrder,
        collapsedCategories: props.collapsedCategories,
      }),
    [props.features, props.sidebarOrder, props.categoryOrder, props.collapsedCategories, query],
  )

  const endDrag = () => {
    setDragging(null)
    setSlot(null)
  }

  /**
   * `group` is the section's rows as displayed, which is what resolves a drop
   * past the last one; the move is written to the global order, so the other
   * groups keep their positions — `SidebarOrdering.reorder` on the Mac.
   *
   * Until something has been dragged there is no stored order to move within,
   * so the registry order stands in as the starting arrangement.
   */
  const dropFeature = (target: string, after: boolean, group: readonly string[]) => {
    if (dragging?.kind !== "feature") return
    const dragged = dragging.id
    endDrag()
    const order =
      props.sidebarOrder.length === 0
        ? props.features.map((feature) => feature.id)
        : props.sidebarOrder
    const moved = applyDrop(dragged, target, after, group, order)
    if (moved !== null) props.onSidebarOrder(moved)
  }

  const dropCategory = (target: string, after: boolean) => {
    if (dragging?.kind !== "category") return
    const dragged = dragging.id
    endDrag()
    const order = sections.map((section) => section.category)
    const moved = applyDrop(dragged, target, after, order, order)
    if (moved !== null) props.onCategoryOrder(moved)
  }

  return (
    <aside className="flex w-[260px] shrink-0 flex-col border-r border-border-subtle bg-bg-chrome">
      <div className="px-3 py-2.5">
        <SearchField value={query} onChange={setQuery} />
      </div>

      {/* Dropping outside every row still ends the drag, so a guideline cannot
          be left painted where nothing landed. */}
      <div className="min-h-0 flex-1 overflow-y-auto pb-3" onDragEnd={endDrag}>
        {sections.length === 0 ? (
          <p className="px-4 py-8 text-center text-text-tertiary">Nothing matches “{query}”.</p>
        ) : (
          sections.map((section) => (
            <SidebarSection
              key={section.category}
              section={section}
              activeID={props.activeID}
              dragging={dragging}
              slot={slot}
              draggable={!searching}
              onOpen={props.onOpen}
              onToggle={props.onToggleCollapsed}
              onDragStart={setDragging}
              onHover={setSlot}
              onDropFeature={dropFeature}
              onDropCategory={dropCategory}
            />
          ))
        )}
      </div>
    </aside>
  )
}

function SearchField({ value, onChange }: { value: string; onChange: (value: string) => void }) {
  return (
    <div className="flex items-center gap-2 rounded-lg bg-bg-raised px-2.5 py-1.5 focus-within:ring-1 focus-within:ring-accent/60">
      <Search size={13} className="shrink-0 text-text-tertiary" />
      <input
        value={value}
        placeholder="Search features…"
        aria-label="Search features"
        onChange={(event) => {
          onChange(event.target.value)
        }}
        onKeyDown={(event) => {
          if (event.key === "Escape") onChange("")
        }}
        className="min-w-0 flex-1 bg-transparent text-[13px] text-text-primary outline-none placeholder:text-text-tertiary"
      />
    </div>
  )
}
