import { useRef, useState } from "react"
import { ArrowDownUp, Eraser, ListFilter, Search, Upload } from "lucide-react"
import { useDismissOnOutside } from "@/hooks/useDismissOnOutside"
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
  onExport,
  onCopyAll,
  trailing,
}: {
  filter: TimelineFilter
  onFilter: (filter: TimelineFilter) => void
  visible: number
  total: number
  newestFirst: boolean
  onNewestFirst: (newestFirst: boolean) => void
  onOpenFilters: () => void
  onClear: () => void
  /** Save what is shown as a JSON file. */
  onExport: () => void
  /** Copy what is shown as JSON. */
  onCopyAll: () => void
  /** The restart control, which the pane owns because it needs a device. */
  trailing?: React.ReactNode
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
      <ExportMenu disabled={visible === 0} onExport={onExport} onCopy={onCopyAll} />
      <IconButton
        icon={Eraser}
        label="Clear the timeline"
        disabled={total === 0}
        onClick={onClear}
      />
      {trailing}
    </div>
  )
}

/**
 * Save-or-copy, as one menu.
 *
 * Both hand over the same thing — the raw wire commands of what is *shown*, so
 * a filter narrows the export as well as the view. Disabled when nothing is
 * shown: an empty file is not a useful answer to "export this".
 */
function ExportMenu({
  disabled,
  onExport,
  onCopy,
}: {
  disabled: boolean
  onExport: () => void
  onCopy: () => void
}) {
  const [open, setOpen] = useState(false)
  const menu = useRef<HTMLDivElement | null>(null)

  useDismissOnOutside(menu, setOpen)

  return (
    <div ref={menu} className="relative shrink-0">
      <IconButton
        icon={Upload}
        label="Export what is shown — save as JSON, or copy to the clipboard"
        disabled={disabled}
        active={open}
        onClick={() => {
          setOpen(!open)
        }}
      />
      {open ? (
        <div
          role="menu"
          className="absolute top-full right-0 z-40 mt-1 min-w-[180px] rounded-md border border-border-subtle bg-bg-raised py-1 shadow-2xl"
        >
          {[
            { label: "Save as JSON…", run: onExport },
            { label: "Copy to clipboard", run: onCopy },
          ].map((entry) => (
            <button
              key={entry.label}
              type="button"
              role="menuitem"
              onClick={() => {
                setOpen(false)
                entry.run()
              }}
              className="block w-full px-3 py-1 text-left text-[12.5px] text-text-primary hover:bg-accent/20"
            >
              {entry.label}
            </button>
          ))}
        </div>
      ) : null}
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
