import { useEffect, useMemo, useState } from "react"
import { Pin, Search } from "lucide-react"
import { cn } from "@/lib/cn"
import { iconForFeature } from "@/lib/icons"
import { moveHighlight, paletteResults } from "@/lib/palette"
import { IS_MAC, shortcutLabel } from "@/lib/platform"
import type { FeatureSummary } from "@/lib/wire"

/**
 * The palette: everything openable, one keystroke away.
 *
 * Opened with Ctrl/⌘+K or Ctrl/⌘+T, and by the tab strip's `+`. Arrow keys
 * move, Enter opens in the pane that asked, Ctrl/⌘+P pins or unpins whatever
 * is highlighted — the same pinned list the sidebar's top section shows.
 */
export function CommandPalette({
  features,
  favorites,
  onOpen,
  onTogglePinned,
  onDismiss,
}: {
  features: FeatureSummary[]
  favorites: string[]
  onOpen: (id: string) => void
  onTogglePinned: (id: string) => void
  onDismiss: () => void
}) {
  const [query, setQuery] = useState("")
  const [highlight, setHighlight] = useState(0)

  const results = useMemo(
    () => paletteResults(features, query, favorites),
    [features, query, favorites],
  )
  // Typing narrows the list; the highlight follows it rather than pointing at
  // a row that is no longer there.
  const index = Math.min(highlight, Math.max(results.length - 1, 0))
  const current = results[index]

  useEffect(() => {
    setHighlight(0)
  }, [query])

  const onKeyDown = (event: React.KeyboardEvent<HTMLInputElement>) => {
    const modifier = IS_MAC ? event.metaKey : event.ctrlKey
    if (event.key === "Escape") {
      event.preventDefault()
      onDismiss()
    } else if (event.key === "ArrowDown") {
      event.preventDefault()
      setHighlight(moveHighlight(results.length, index, 1))
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      setHighlight(moveHighlight(results.length, index, -1))
    } else if (modifier && event.key === "p") {
      event.preventDefault()
      if (current) onTogglePinned(current.id)
    } else if (event.key === "Enter" && current) {
      event.preventDefault()
      onOpen(current.id)
      onDismiss()
    }
  }

  return (
    <>
      <div className="fixed inset-0 z-40 bg-black/40" onPointerDown={onDismiss} />
      <div className="fixed inset-x-0 top-[12vh] z-50 mx-auto w-[560px] max-w-[90vw] overflow-hidden rounded-xl border border-border-subtle bg-bg-raised shadow-2xl">
        <div className="flex items-center gap-2.5 border-b border-border-subtle px-3.5 py-3">
          <Search size={15} className="shrink-0 text-text-tertiary" />
          <input
            value={query}
            // The palette exists to be typed into; landing anywhere else
            // costs a keystroke every time it opens.
            // oxlint-disable-next-line jsx-a11y/no-autofocus
            autoFocus
            aria-label="Search features"
            placeholder="Open a feature…"
            onChange={(event) => {
              setQuery(event.target.value)
            }}
            onKeyDown={onKeyDown}
            className="min-w-0 flex-1 bg-transparent text-[15px] text-text-primary outline-none placeholder:text-text-tertiary"
          />
          <span className="shrink-0 text-[11px] text-text-tertiary">
            {shortcutLabel("p", IS_MAC)} to pin
          </span>
        </div>

        <div className="max-h-[52vh] overflow-y-auto py-1.5">
          {results.length === 0 ? (
            <p className="px-4 py-8 text-center text-text-tertiary">Nothing matches “{query}”.</p>
          ) : (
            results.map((feature, row) => (
              <Row
                key={feature.id}
                feature={feature}
                pinned={favorites.includes(feature.id)}
                highlighted={row === index}
                onHover={() => {
                  setHighlight(row)
                }}
                onSelect={() => {
                  onOpen(feature.id)
                  onDismiss()
                }}
              />
            ))
          )}
        </div>
      </div>
    </>
  )
}

function Row({
  feature,
  pinned,
  highlighted,
  onHover,
  onSelect,
}: {
  feature: FeatureSummary
  pinned: boolean
  highlighted: boolean
  onHover: () => void
  onSelect: () => void
}) {
  const Icon = iconForFeature(feature.id, feature.category)
  return (
    <button
      type="button"
      onClick={onSelect}
      onPointerMove={onHover}
      className={cn(
        "flex w-full items-center gap-2.5 px-3.5 py-1.5 text-left",
        highlighted ? "bg-accent/15" : "",
      )}
    >
      <Icon size={16} className="shrink-0 text-accent" />
      <span className="min-w-0 flex-1">
        <span className="block truncate text-[13.5px] text-text-primary">{feature.title}</span>
        {feature.subtitle ? (
          <span className="block truncate text-[11.5px] text-text-secondary">
            {feature.subtitle}
          </span>
        ) : null}
      </span>
      {pinned ? <Pin size={12} className="shrink-0 text-accent" /> : null}
    </button>
  )
}
