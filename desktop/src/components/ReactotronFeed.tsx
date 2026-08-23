import { useRef, useState } from "react"
import { ReactotronRow } from "@/components/ReactotronRow"
import type { TimelineRow } from "@/lib/reactotron-rows"

/** How many rows go into the DOM. The buffer holds more; this is what renders. */
export const RENDER_WINDOW = 600

/**
 * The rows, and the scroll behaviour around them.
 *
 * Newest-first reverses what is *rendered*, never what is stored: the window is
 * taken off the newest end either way, so flipping the order cannot change
 * which rows are in the DOM — only which end of the pane they start from.
 */
export function ReactotronFeed({
  rows,
  newestFirst,
  total,
}: {
  rows: readonly TimelineRow[]
  newestFirst: boolean
  /** Everything buffered, so an empty result can say what it is hiding. */
  total: number
}) {
  const [following, setFollowing] = useState(true)
  const scroller = useRef<HTMLDivElement | null>(null)
  const window = rows.slice(Math.max(0, rows.length - RENDER_WINDOW))
  const rendered = newestFirst ? window.toReversed() : window

  return (
    <div
      ref={(element) => {
        scroller.current = element
        // Newest-first pins to the top, which is where the newest row now is.
        if (element && following) element.scrollTop = newestFirst ? 0 : element.scrollHeight
      }}
      onScroll={(event) => {
        // Following is a decision about intent, so it is read from a real
        // scroll position rather than inferred from a programmatic pin.
        const element = event.currentTarget
        const distance = newestFirst
          ? element.scrollTop
          : element.scrollHeight - element.scrollTop - element.clientHeight
        setFollowing(distance < 24)
      }}
      className="min-h-0 flex-1 overflow-y-auto"
      data-selectable
    >
      {rendered.map((row) => (
        <ReactotronRow key={row.id} row={row} hit={false} />
      ))}
      {rows.length === 0 ? (
        <p className="p-8 text-center text-text-tertiary">
          Nothing matches. {total.toLocaleString()} events are hidden by the filter.
        </p>
      ) : null}
    </div>
  )
}
