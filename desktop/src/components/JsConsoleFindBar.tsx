import { ChevronDown, ChevronUp, Search, X } from "lucide-react"
import { useEffect, useRef } from "react"

/**
 * The strip Ctrl+F opens, as the Mac's find bar.
 *
 * Its own row above the feed rather than a second box in the filter bar: find
 * carries a counter and two arrows, and the Mac gives it the room. Enter walks
 * forward, Escape closes and clears — the console's own conventions, not the
 * browser's find.
 */
export function JsConsoleFindBar({
  query,
  onQuery,
  count,
  hasMatches,
  onNext,
  onPrev,
  onClose,
}: {
  query: string
  onQuery: (query: string) => void
  /** "", "No matches", or "3 of 12". */
  count: string
  hasMatches: boolean
  onNext: () => void
  onPrev: () => void
  onClose: () => void
}) {
  const field = useRef<HTMLInputElement | null>(null)

  // Focused on open. The bar only exists while find is open, so mounting is
  // the transition — no need to watch a flag the way the Mac's `onChange` does.
  useEffect(() => {
    field.current?.focus()
  }, [])

  return (
    <div className="flex shrink-0 items-center gap-2 border-b border-border-subtle bg-amber-400/[0.07] px-3 py-1.5">
      <Search size={13} className="shrink-0 text-text-tertiary" />
      <input
        ref={field}
        value={query}
        aria-label="Find in console"
        placeholder="Find in console"
        onChange={(event) => {
          onQuery(event.target.value)
        }}
        onKeyDown={(event) => {
          if (event.key === "Enter") {
            event.preventDefault()
            // Shift walks back, the way every find field does.
            if (event.shiftKey) onPrev()
            else onNext()
          }
          if (event.key === "Escape") {
            event.preventDefault()
            onClose()
          }
        }}
        className="min-w-0 flex-1 bg-transparent text-text-primary outline-none"
      />
      <span className="shrink-0 tabular-nums text-text-tertiary">{count}</span>
      <button
        type="button"
        aria-label="Previous match"
        disabled={!hasMatches}
        onClick={onPrev}
        className="shrink-0 rounded p-1 text-text-secondary enabled:hover:bg-bg-surface disabled:opacity-40"
      >
        <ChevronUp size={13} />
      </button>
      <button
        type="button"
        aria-label="Next match"
        disabled={!hasMatches}
        onClick={onNext}
        className="shrink-0 rounded p-1 text-text-secondary enabled:hover:bg-bg-surface disabled:opacity-40"
      >
        <ChevronDown size={13} />
      </button>
      <button
        type="button"
        aria-label="Close find"
        onClick={onClose}
        className="shrink-0 rounded p-1 text-text-secondary hover:bg-bg-surface"
      >
        <X size={13} />
      </button>
    </div>
  )
}
