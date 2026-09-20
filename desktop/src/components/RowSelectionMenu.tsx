import { Copy } from "lucide-react"
import { useRef, useState } from "react"

import { useDismissOnOutside } from "@/hooks/useDismissOnOutside"

/**
 * What the Mac shows once rows are picked: the count, and a menu of the three
 * things you can do with them.
 *
 * Only while something is selected, as the Mac renders it — a Copy that is
 * disabled nine times out of ten is noise in the bar. One component for both
 * feeds, because the Mac's two `selectionControls` differ by a single word:
 * the console copies *logs*, the timeline copies *events*.
 */
export function RowSelectionMenu({
  count,
  noun,
  onCopy,
  onCopyAsJson,
  onDeselect,
}: {
  count: number
  /** "logs" or "events" — the one word the Mac's two versions differ by. */
  noun: string
  onCopy: () => void
  onCopyAsJson: () => void
  onDeselect: () => void
}) {
  const [open, setOpen] = useState(false)
  const box = useRef<HTMLDivElement | null>(null)
  useDismissOnOutside(box, setOpen)

  const pick = (run: () => void) => {
    setOpen(false)
    run()
  }

  return (
    <div ref={box} className="relative flex shrink-0 items-center gap-1.5">
      <span className="text-text-tertiary">{count} selected</span>
      <button
        type="button"
        aria-label="Selection actions"
        aria-expanded={open}
        // The Mac's sentence, with Ctrl for its ⌘. It is also the only place
        // the gestures are written down anywhere in either app.
        title={`Copy the selected ${noun} (Ctrl+C) — Ctrl-click to pick rows, Shift-click or drag for a range`}
        onClick={() => {
          setOpen(!open)
        }}
        className="rounded p-1 text-text-secondary hover:bg-bg-surface"
      >
        <Copy size={13} />
      </button>
      {open ? (
        <div
          role="menu"
          className="absolute top-full right-0 z-40 mt-1 min-w-[150px] rounded-md border border-border-subtle bg-bg-raised py-1 shadow-2xl"
        >
          <Item
            label="Copy"
            onClick={() => {
              pick(onCopy)
            }}
          />
          <Item
            label="Copy as JSON"
            onClick={() => {
              pick(onCopyAsJson)
            }}
          />
          <div className="my-1 border-t border-border-subtle" />
          <Item
            label="Deselect"
            onClick={() => {
              pick(onDeselect)
            }}
          />
        </div>
      ) : null}
    </div>
  )
}

function Item({ label, onClick }: { label: string; onClick: () => void }) {
  return (
    <button
      type="button"
      role="menuitem"
      onClick={onClick}
      className="w-full px-3 py-1 text-left text-text-primary hover:bg-accent/20"
    >
      {label}
    </button>
  )
}
