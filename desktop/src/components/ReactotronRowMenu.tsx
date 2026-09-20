import { useEffect, useRef } from "react"
import { copyLine, copyObject } from "@/lib/reactotron-copy"
import type { TimelineRow } from "@/lib/reactotron-rows"

export interface RowMenuTarget {
  row: TimelineRow
  x: number
  y: number
}

/**
 * A timeline row's right-click menu: the picked rows, then this one.
 *
 * Hand-rolled for the same reason `FileRowMenu` is — a webview has no menu of
 * its own, and reaching for the OS one would mean another plugin and another
 * permission for two items.
 *
 * Copy object is offered only when the frame carried a payload. `clear` and the
 * relay's own notices do not, and a verb that silently copies "null" is worse
 * than one that is not there.
 */
export function ReactotronRowMenu({
  at,
  row,
  onDismiss,
  onCopy,
  selectionCount,
  onCopySelection,
}: {
  at: { x: number; y: number }
  row: TimelineRow
  onDismiss: () => void
  onCopy: (text: string) => void
  /** How many rows are picked, which decides whether the bulk verbs appear. */
  selectionCount: number
  onCopySelection: (asJson: boolean) => void
}) {
  const dismiss = useRef(onDismiss)
  dismiss.current = onDismiss

  useEffect(() => {
    const close = () => {
      dismiss.current()
    }
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") close()
    }
    globalThis.addEventListener("keydown", onKeyDown)
    // Capture, so a click that lands on a row underneath closes this first
    // rather than opening a second menu.
    globalThis.addEventListener("mousedown", close, { capture: true })
    return () => {
      globalThis.removeEventListener("keydown", onKeyDown)
      globalThis.removeEventListener("mousedown", close, { capture: true })
    }
  }, [])

  const object = copyObject(row)
  return (
    <div
      role="menu"
      style={{ left: at.x, top: at.y }}
      className="fixed z-50 min-w-[180px] rounded-md border border-border-subtle bg-bg-raised py-1 shadow-2xl"
    >
      {/* The Mac shows the bulk verbs only past one row: with a single row
          picked they would say the same thing as Copy line, twice. */}
      {selectionCount > 1 ? (
        <>
          <Item
            label={`Copy ${String(selectionCount)} Selected Events`}
            onClick={() => {
              onCopySelection(false)
            }}
          />
          <Item
            label={`Copy ${String(selectionCount)} Selected as JSON`}
            onClick={() => {
              onCopySelection(true)
            }}
          />
          <div className="my-1 border-t border-border-subtle" />
        </>
      ) : null}
      {object === null ? null : (
        <Item
          label="Copy object"
          onClick={() => {
            onCopy(object)
          }}
        />
      )}
      <Item
        label="Copy line"
        onClick={() => {
          onCopy(copyLine(row))
        }}
      />
    </div>
  )
}

function Item({ label, onClick }: { label: string; onClick: () => void }) {
  return (
    <button
      type="button"
      role="menuitem"
      onClick={onClick}
      className="block w-full px-3 py-1 text-left text-[12.5px] text-text-primary hover:bg-accent/20"
    >
      {label}
    </button>
  )
}
