import { ChevronRight } from "lucide-react"
import { pastMidpointY, startDrag } from "@/components/dnd"
import { cn } from "@/lib/cn"
import { iconForFeature } from "@/lib/icons"
import type { SidebarSection as Section } from "@/lib/sidebar"
import type { FeatureSummary } from "@/lib/wire"

/** What a sidebar drag is carrying: a feature row, or a whole category header. */
export interface Dragging {
  kind: "feature" | "category"
  id: string
  /** The category a feature drag started in — it may not leave it. */
  category: string
}

/** Where the insertion guideline sits during a drag. */
export interface DropSlot {
  id: string
  after: boolean
}

export interface SectionProps {
  section: Section
  activeID: string | null
  dragging: Dragging | null
  slot: DropSlot | null
  /** Off while searching: relevance order is not an order worth persisting. */
  draggable: boolean
  onOpen: (id: string) => void
  onToggle: (category: string) => void
  onDragStart: (dragging: Dragging) => void
  onHover: (slot: DropSlot) => void
  onDropFeature: (target: string, after: boolean, group: readonly string[]) => void
  onDropCategory: (target: string, after: boolean) => void
}

/** One category of the sidebar: a collapsible header over its feature rows. */
export function SidebarSection(props: SectionProps) {
  const { section, dragging, slot } = props
  const group = section.features.map((feature) => feature.id)
  const takesCategory = dragging?.kind === "category"
  const takesFeature = dragging?.kind === "feature" && dragging.category === section.category

  return (
    <section>
      <button
        type="button"
        draggable={props.draggable}
        onDragStart={(event) => {
          startDrag(event)
          props.onDragStart({
            kind: "category",
            id: section.category,
            category: section.category,
          })
        }}
        onDragOver={(event) => {
          if (!takesCategory) return
          event.preventDefault()
          props.onHover({ id: section.category, after: pastMidpointY(event) })
        }}
        onDrop={(event) => {
          if (!takesCategory) return
          event.preventDefault()
          props.onDropCategory(section.category, pastMidpointY(event))
        }}
        onClick={() => {
          props.onToggle(section.category)
        }}
        aria-expanded={!section.collapsed}
        className={cn(
          "relative flex w-full items-center gap-1 px-3 pb-1 pt-3.5 text-left",
          "text-[10.5px] font-medium uppercase tracking-[0.06em] text-text-tertiary",
          "hover:text-text-secondary",
          takesCategory && dragging.id === section.category ? "opacity-30" : "",
        )}
      >
        <ChevronRight
          size={11}
          className={cn("transition-transform", section.collapsed ? "" : "rotate-90")}
        />
        {section.label}
        {takesCategory && slot?.id === section.category ? <Guideline after={slot.after} /> : null}
      </button>

      {section.collapsed
        ? null
        : section.features.map((feature) => (
            <Row
              key={feature.id}
              feature={feature}
              active={feature.id === props.activeID}
              slot={takesFeature && slot?.id === feature.id ? slot.after : null}
              faded={dragging?.kind === "feature" && dragging.id === feature.id}
              draggable={props.draggable}
              onOpen={() => {
                props.onOpen(feature.id)
              }}
              onDragStart={(event) => {
                startDrag(event)
                props.onDragStart({
                  kind: "feature",
                  id: feature.id,
                  category: feature.category,
                })
              }}
              onDragOver={(event) => {
                // A row only accepts a feature from its own group.
                if (!takesFeature) return
                event.preventDefault()
                props.onHover({ id: feature.id, after: pastMidpointY(event) })
              }}
              onDrop={(event) => {
                if (!takesFeature) return
                event.preventDefault()
                props.onDropFeature(feature.id, pastMidpointY(event), group)
              }}
            />
          ))}
    </section>
  )
}

function Row({
  feature,
  active,
  slot,
  faded,
  draggable,
  onOpen,
  onDragStart,
  onDragOver,
  onDrop,
}: {
  feature: FeatureSummary
  active: boolean
  /** Null for no guideline, else which side of the row it sits on. */
  slot: boolean | null
  faded: boolean
  draggable: boolean
  onOpen: () => void
  onDragStart: (event: React.DragEvent<HTMLElement>) => void
  onDragOver: (event: React.DragEvent<HTMLElement>) => void
  onDrop: (event: React.DragEvent<HTMLElement>) => void
}) {
  const Icon = iconForFeature(feature.id, feature.category)
  return (
    <button
      type="button"
      draggable={draggable}
      onClick={onOpen}
      onDragStart={onDragStart}
      onDragOver={onDragOver}
      onDrop={onDrop}
      title={feature.subtitle ?? feature.title}
      className={cn(
        "relative flex w-full items-start gap-2.5 px-3 py-1.5 text-left transition-colors",
        active ? "bg-accent/12" : "hover:bg-white/[0.04]",
        faded ? "opacity-30" : "",
      )}
    >
      <Icon
        size={16}
        className={cn("mt-[3px] shrink-0", active ? "text-accent" : "text-accent/80")}
      />
      <span className="min-w-0">
        <span className="block truncate text-[13px] text-text-primary">{feature.title}</span>
        {feature.subtitle ? (
          <span className="block truncate text-[11px] text-text-secondary">{feature.subtitle}</span>
        ) : null}
      </span>
      {slot === null ? null : <Guideline after={slot} />}
    </button>
  )
}

/** The accent bar marking where a dragged row will land. */
function Guideline({ after }: { after: boolean }) {
  return (
    <span
      className={cn(
        "pointer-events-none absolute inset-x-1 h-0.5 rounded-full bg-accent",
        after ? "bottom-0" : "top-0",
      )}
    />
  )
}
