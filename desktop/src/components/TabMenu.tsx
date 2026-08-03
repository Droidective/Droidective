import { useEffect } from "react"
import { cn } from "@/lib/cn"

export interface TabMenuTarget {
  id: string
  x: number
  y: number
}

/**
 * A tab's right-click menu.
 *
 * Hand-rolled rather than native: a webview has no menu of its own to put these
 * on, and reaching for the OS menu would mean another plugin and another
 * permission for four items.
 */
export function TabMenu({
  target,
  isSplit,
  canCloseOthers,
  onSplit,
  onMoveToOtherPane,
  onClose,
  onCloseOthers,
  onDismiss,
}: {
  target: TabMenuTarget
  isSplit: boolean
  canCloseOthers: boolean
  onSplit: () => void
  onMoveToOtherPane: () => void
  onClose: () => void
  onCloseOthers: () => void
  onDismiss: () => void
}) {
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") onDismiss()
    }
    globalThis.addEventListener("keydown", onKeyDown)
    return () => {
      globalThis.removeEventListener("keydown", onKeyDown)
    }
  }, [onDismiss])

  return (
    <>
      {/* A backdrop rather than a window listener: it swallows the dismissing
          click, so it cannot also land on whatever sits under the menu. */}
      <div
        className="fixed inset-0 z-40"
        onPointerDown={onDismiss}
        onContextMenu={(event) => {
          event.preventDefault()
          onDismiss()
        }}
      />
      <div
        role="menu"
        style={{ left: target.x, top: target.y }}
        className="fixed z-50 min-w-[190px] rounded-lg border border-border-subtle bg-bg-raised py-1 shadow-xl"
      >
        {isSplit ? (
          <Item onSelect={onMoveToOtherPane}>Move to Other Pane</Item>
        ) : (
          <Item onSelect={onSplit}>Split: Move to New Pane</Item>
        )}
        <div className="my-1 h-px bg-border-subtle" />
        <Item onSelect={onClose}>Close Tab</Item>
        <Item onSelect={onCloseOthers} disabled={!canCloseOthers}>
          Close Other Tabs
        </Item>
      </div>
    </>
  )
}

function Item({
  onSelect,
  disabled = false,
  children,
}: {
  onSelect: () => void
  disabled?: boolean
  children: string
}) {
  return (
    <button
      type="button"
      role="menuitem"
      disabled={disabled}
      // The dismissing pointerdown listener runs in capture, so acting on
      // pointerdown here would never be reached — this fires on click.
      onClick={onSelect}
      className={cn(
        "block w-full px-3 py-1 text-left text-[13px]",
        disabled
          ? "cursor-not-allowed text-text-tertiary"
          : "text-text-primary hover:bg-accent/20",
      )}
    >
      {children}
    </button>
  )
}
