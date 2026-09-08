import { Pin, X } from "lucide-react"
import { cn } from "@/lib/cn"
import { iconForFeature } from "@/lib/icons"
import { IS_MAC, shortcutLabel } from "@/lib/platform"
import type { FeatureSummary } from "@/lib/wire"

/**
 * One tab in the strip.
 *
 * Split from `TabStrip` so that file stays about the strip's layout and its
 * drag wiring; this is what a single tab looks like, which is the Mac's
 * `TabChip` in `TabStripView.swift`.
 */
export function TabChip({
  id,
  feature,
  active,
  faded,
  pinned,
  slot,
  onSelect,
  onClose,
  onUnpin,
  onContextMenu,
  onDragStart,
  onDragOver,
  onDrop,
}: {
  id: string
  feature: FeatureSummary | null
  active: boolean
  faded: boolean
  pinned: boolean
  slot: boolean | null
  onSelect: () => void
  onClose: () => void
  onUnpin: () => void
  onContextMenu: (event: React.MouseEvent<HTMLElement>) => void
  onDragStart: (event: React.DragEvent<HTMLElement>) => void
  onDragOver: (event: React.DragEvent<HTMLElement>) => void
  onDrop: (event: React.DragEvent<HTMLElement>) => void
}) {
  // A tab whose feature has gone is still closable: showing its id beats
  // rendering a blank chip nobody can get rid of.
  const Icon = iconForFeature(id, feature?.category ?? "")
  return (
    <div
      draggable
      onDragStart={onDragStart}
      onDragOver={onDragOver}
      onDrop={onDrop}
      onContextMenu={onContextMenu}
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
      {/* A pin sits where the × would: out of accidental-click range is half
          of what pinning is for. It is not a lock — Ctrl/⌘W and the menu's
          Close Tab still close a pinned tab. */}
      {pinned ? (
        <button
          type="button"
          onClick={onUnpin}
          title="Unpin this tab"
          aria-label={`Unpin ${feature?.title ?? id}`}
          className={cn(
            "flex size-4 shrink-0 items-center justify-center rounded hover:bg-white/10",
            active ? "text-accent" : "text-text-tertiary hover:text-text-primary",
          )}
        >
          <Pin size={10} strokeWidth={2.5} className="fill-current" />
        </button>
      ) : (
        <button
          type="button"
          onClick={onClose}
          title={`Close tab (${shortcutLabel("w", IS_MAC)})`}
          aria-label={`Close ${feature?.title ?? id}`}
          className="flex size-4 shrink-0 items-center justify-center rounded text-text-tertiary hover:bg-white/10 hover:text-text-primary"
        >
          <X size={10} strokeWidth={3} />
        </button>
      )}
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
