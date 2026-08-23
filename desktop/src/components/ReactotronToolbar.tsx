import { ArrowDownUp, Eraser, ListFilter, Search } from "lucide-react"
import { cn } from "@/lib/cn"
import { isFiltering, type TimelineFilter } from "@/lib/reactotron-filter"

/**
 * The timeline's own controls: the filter dialog, search, the sort direction,
 * and Clear — in the Mac's order, so the two toolbars read the same left to
 * right.
 *
 * The count only appears while something is narrowing the list. A permanent
 * "N of M" would be noise on an unfiltered feed, where the number is just how
 * many events the app has sent.
 */
export function ReactotronToolbar({
  filter,
  onFilter,
  visible,
  total,
  newestFirst,
  onNewestFirst,
  onOpenFilters,
  onClear,
}: {
  filter: TimelineFilter
  onFilter: (filter: TimelineFilter) => void
  visible: number
  total: number
  newestFirst: boolean
  onNewestFirst: (newestFirst: boolean) => void
  onOpenFilters: () => void
  onClear: () => void
}) {
  const narrowing = isFiltering(filter) || filter.search.trim() !== ""
  return (
    <div className="flex shrink-0 items-center gap-2 border-b border-border-subtle bg-bg-chrome px-3 py-2">
      <IconButton
        icon={ListFilter}
        label="Filter the timeline by event type"
        active={isFiltering(filter)}
        onClick={onOpenFilters}
      />

      <div className="flex min-w-0 max-w-[260px] flex-1 items-center gap-2 rounded-md border border-border-subtle bg-bg-raised px-2.5 py-1 focus-within:border-accent">
        <Search size={13} className="shrink-0 text-text-tertiary" />
        <input
          value={filter.search}
          aria-label="Search the timeline"
          placeholder="Search…"
          onChange={(event) => {
            onFilter({ ...filter, search: event.target.value })
          }}
          onKeyDown={(event) => {
            if (event.key === "Escape") onFilter({ ...filter, search: "" })
          }}
          className="min-w-0 flex-1 bg-transparent text-[13px] text-text-primary outline-none placeholder:text-text-tertiary"
        />
      </div>

      {narrowing ? (
        <span className="shrink-0 text-[11.5px] text-text-tertiary tabular-nums">
          {visible.toLocaleString()} of {total.toLocaleString()}
        </span>
      ) : null}

      <span className="flex-1" />

      <IconButton
        icon={ArrowDownUp}
        label={
          newestFirst
            ? "Newest at top — click to show newest at bottom"
            : "Newest at bottom — click to show newest at top"
        }
        active={newestFirst}
        onClick={() => {
          onNewestFirst(!newestFirst)
        }}
      />
      <IconButton
        icon={Eraser}
        label="Clear the timeline"
        disabled={total === 0}
        onClick={onClear}
      />
    </div>
  )
}

function IconButton({
  icon: Icon,
  label,
  active = false,
  disabled = false,
  onClick,
}: {
  icon: typeof Search
  label: string
  active?: boolean
  disabled?: boolean
  onClick: () => void
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      title={label}
      aria-label={label}
      aria-pressed={active}
      className={cn(
        "flex size-7 shrink-0 items-center justify-center rounded-md disabled:opacity-40",
        active
          ? "bg-accent/20 text-accent"
          : "bg-bg-raised text-text-secondary enabled:hover:bg-border-subtle enabled:hover:text-text-primary",
      )}
    >
      <Icon size={13} />
    </button>
  )
}
