import { useEffect, useRef } from "react"

/**
 * A terminal tab's right-click menu.
 *
 * Hand-rolled for the reason `FileRowMenu` and `ReactotronRowMenu` are: a
 * webview has no menu of its own, and reaching for the OS one would mean
 * another plugin and another permission for four items.
 *
 * The Mac's wording and the Mac's order. The splits and Close Terminal are
 * also on the menu bar with their shortcuts — this is the second way to them,
 * and for someone who has never opened the menu bar it is the only one.
 *
 * The group items appear only where they mean something: New Group… on any
 * tab, and New Terminal Here / Close Group only on a tab that is in one. The
 * Mac's menu is arranged the same way — a Close Group on a loose tab would be
 * a verb with nothing to act on.
 */
export function TerminalTabMenu({
  at,
  onRename,
  onSplitVertically,
  onSplitHorizontally,
  onClose,
  onDismiss,
  onNewGroup,
  onNewTerminalHere,
  onCloseGroup,
}: {
  at: { x: number; y: number }
  onRename: () => void
  onSplitVertically: () => void
  onSplitHorizontally: () => void
  onClose: () => void
  onDismiss: () => void
  onNewGroup: () => void
  /** Null when this tab is not in a group — the verb would act on nothing. */
  onNewTerminalHere: (() => void) | null
  onCloseGroup: (() => void) | null
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
    // Capture, so a click landing on a tab underneath closes this first rather
    // than opening a second menu.
    globalThis.addEventListener("mousedown", close, { capture: true })
    return () => {
      globalThis.removeEventListener("keydown", onKeyDown)
      globalThis.removeEventListener("mousedown", close, { capture: true })
    }
  }, [])

  return (
    <div
      role="menu"
      style={{ left: at.x, top: at.y }}
      className="fixed z-50 min-w-[190px] rounded-md border border-border-subtle bg-bg-raised py-1 shadow-2xl"
    >
      <Item label="Rename…" onClick={onRename} />
      <Item label="New Group…" onClick={onNewGroup} />
      {onNewTerminalHere === null ? null : (
        <Item label="New Terminal Here" onClick={onNewTerminalHere} />
      )}
      <div className="my-1 border-t border-border-subtle" />
      <Item label="Split Vertically" onClick={onSplitVertically} />
      <Item label="Split Horizontally" onClick={onSplitHorizontally} />
      <div className="my-1 border-t border-border-subtle" />
      <Item label="Close Terminal" onClick={onClose} />
      {onCloseGroup === null ? null : <Item label="Close Group" onClick={onCloseGroup} />}
    </div>
  )
}

function Item({ label, onClick }: { label: string; onClick: () => void }) {
  return (
    <button
      type="button"
      role="menuitem"
      onClick={onClick}
      className="w-full px-3 py-1 text-left text-[12.5px] text-text-primary hover:bg-accent/20"
    >
      {label}
    </button>
  )
}
