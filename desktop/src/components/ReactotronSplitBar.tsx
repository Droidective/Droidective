import { Columns2, Trash2 } from "lucide-react"

/**
 * The strip above a split timeline: what both panes share.
 *
 * Only in split mode. In one pane these controls ride the pane's own toolbar,
 * because a timeline topped by two stacked strips wastes the room the rows
 * want.
 */
export function ReactotronSplitBar({
  events,
  onToggleSplit,
  onClearAll,
  trailing,
}: {
  events: number
  onToggleSplit: () => void
  onClearAll: () => void
  trailing: React.ReactNode
}) {
  return (
    <div className="flex shrink-0 items-center gap-2 border-b border-border-subtle px-3 py-1.5">
      <span className="text-text-tertiary">{events.toLocaleString()} events</span>
      <div className="flex-1" />
      {trailing}
      <button
        type="button"
        title="Back to a single pane"
        aria-label="Back to a single pane"
        onClick={onToggleSplit}
        className="shrink-0 rounded p-1 text-accent hover:bg-bg-surface"
      >
        <Columns2 size={13} />
      </button>
      <button
        type="button"
        // The Mac's wording, and it earns its length: this frees the shared
        // buffer, so it empties both panes rather than the one you are looking
        // at. Each pane's own trash clears only itself.
        title="Clear the whole timeline — both panes"
        aria-label="Clear the whole timeline — both panes"
        disabled={events === 0}
        onClick={onClearAll}
        className="shrink-0 rounded p-1 text-text-secondary enabled:hover:bg-bg-surface disabled:opacity-40"
      >
        <Trash2 size={13} />
      </button>
    </div>
  )
}
