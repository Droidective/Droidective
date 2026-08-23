import { useEffect, useState } from "react"
import { Check } from "lucide-react"
import { Button } from "@/components/Controls"
import { ReactotronApiFilters } from "@/components/ReactotronApiFilters"
import { cn } from "@/lib/cn"
import { EVENT_KINDS, KIND_GROUPS, KIND_LABELS, type EventKind } from "@/lib/reactotron-rows"
import type { StatusClass, TimelineFilter } from "@/lib/reactotron-filter"

/**
 * Reactotron's Timeline Filter dialog, as grouped event-kind cards with the API
 * method and status refinements nested under the API group.
 *
 * Two behaviours carried over from the Mac deliberately. It edits a **draft**,
 * so Cancel, Esc and the backdrop discard while Done applies the whole
 * selection in one commit — the timeline behind the modal never flickers
 * mid-edit. And it is hide-what-you-untick, which is upstream's model: a ticked
 * kind is shown, and an empty hidden set shows everything.
 */
export function ReactotronFilterSheet({
  filter,
  seenMethods,
  onApply,
  onDismiss,
}: {
  filter: TimelineFilter
  seenMethods: string[]
  onApply: (filter: TimelineFilter) => void
  onDismiss: () => void
}) {
  const [hidden, setHidden] = useState<readonly EventKind[]>(filter.hiddenKinds)
  const [method, setMethod] = useState<string | null>(filter.method)
  const [status, setStatus] = useState<StatusClass | null>(filter.status)

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") onDismiss()
    }
    globalThis.addEventListener("keydown", onKeyDown)
    return () => {
      globalThis.removeEventListener("keydown", onKeyDown)
    }
  }, [onDismiss])

  const toggle = (kind: EventKind) => {
    setHidden((current) =>
      current.includes(kind) ? current.filter((name) => name !== kind) : [...current, kind],
    )
  }

  const apiShown = !hidden.includes("api")

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-8">
      <button
        type="button"
        aria-label="Close"
        onClick={onDismiss}
        className="absolute inset-0 cursor-default"
      />
      <dialog
        open
        aria-label="Filter the timeline"
        className={cn(
          "relative m-0 flex max-h-full w-[430px] max-w-full flex-col gap-3.5 overflow-y-auto p-5",
          "rounded-xl border border-border-subtle bg-bg-raised text-text-primary shadow-2xl",
        )}
      >
        <div>
          <h2 className="text-[15px] font-semibold">Timeline Filter</h2>
          <p className="mt-0.5 text-[12px] text-text-secondary">
            Untick what you do not want to see. Events with no toggle here — REPL
            answers, custom commands, state responses — always show.
          </p>
        </div>

        <Groups
          hidden={hidden}
          onToggle={toggle}
          refinements={
            apiShown ? (
              <ReactotronApiFilters
                method={method}
                status={status}
                seenMethods={seenMethods}
                onMethod={setMethod}
                onStatus={setStatus}
              />
            ) : null
          }
        />

        <Footer
          hiddenCount={hidden.length}
          onShowAll={() => {
            setHidden([])
            setMethod(null)
            setStatus(null)
          }}
          onCancel={onDismiss}
          onDone={() => {
            onApply({ ...filter, hiddenKinds: hidden, method, status })
          }}
        />
      </dialog>
    </div>
  )
}

/** Show all, what is hidden, and the two-button commit. */
function Footer({
  hiddenCount,
  onShowAll,
  onCancel,
  onDone,
}: {
  hiddenCount: number
  onShowAll: () => void
  onCancel: () => void
  onDone: () => void
}) {
  return (
    <div className="flex items-center gap-2 border-t border-border-subtle pt-3.5">
      <Button onClick={onShowAll} title="Show every event again">
        Show all
      </Button>
      <span className="flex-1 text-[11.5px] text-text-tertiary">
        {hiddenCount === 0
          ? "Showing everything"
          : `${hiddenCount} of ${EVENT_KINDS.length} hidden`}
      </span>
      <Button onClick={onCancel}>Cancel</Button>
      <Button tone="primary" onClick={onDone}>
        Done
      </Button>
    </div>
  )
}

/**
 * The kind toggles, in Reactotron's own four sections.
 *
 * `refinements` rides under the group that owns them rather than being a fifth
 * section: a method or status narrows API rows and nothing else, and a control
 * that far from what it affects reads as a global filter.
 */
function Groups({
  hidden,
  onToggle,
  refinements,
}: {
  hidden: readonly EventKind[]
  onToggle: (kind: EventKind) => void
  refinements: React.ReactNode
}) {
  return KIND_GROUPS.map((group) => (
    <section key={group.name} className="flex flex-col gap-1.5">
      <h3 className="text-[11px] tracking-wide text-text-tertiary uppercase">{group.name}</h3>
      <div className="flex flex-wrap gap-1.5">
        {group.kinds.map((kind) => (
          <KindChip
            key={kind}
            label={KIND_LABELS[kind]}
            shown={!hidden.includes(kind)}
            onToggle={() => {
              onToggle(kind)
            }}
          />
        ))}
      </div>
      {group.kinds.includes("api") ? refinements : null}
    </section>
  ))
}

function KindChip({
  label,
  shown,
  onToggle,
}: {
  label: string
  shown: boolean
  onToggle: () => void
}) {
  return (
    <button
      type="button"
      onClick={onToggle}
      aria-pressed={shown}
      className={cn(
        "flex items-center gap-1.5 rounded-full py-1 pr-2.5 pl-2 text-[12px] transition-colors",
        shown
          ? "bg-accent/20 text-accent"
          : "bg-bg-root text-text-tertiary hover:text-text-secondary",
      )}
    >
      <Check size={11} strokeWidth={3} className={shown ? "" : "opacity-0"} />
      {label}
    </button>
  )
}
