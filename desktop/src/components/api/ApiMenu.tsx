import { useEffect, useRef, useState, type ReactNode } from "react"

import { cn } from "@/lib/cn"

/**
 * The API pane's menus — the several `Menu`s and `contextMenu`s the Mac's view
 * carries, in the shape `FileRowMenu` and `TabMenu` already use here.
 *
 * Hand-rolled for the same reason those are: a webview has no menu of its own,
 * and reaching for the OS one would mean another plugin and another permission
 * for a handful of items.
 */

export interface MenuEntry {
  label: string
  /** Absent on a heading, which is a label rather than a choice. */
  onSelect?: () => void
  danger?: boolean
  /** A heading rather than a choice — the Mac's submenu titles. */
  heading?: boolean
  separatorBefore?: boolean
}

/** A menu positioned at a point, for a right-click. */
export function ApiContextMenu({
  at,
  entries,
  onDismiss,
}: {
  at: { x: number; y: number }
  entries: MenuEntry[]
  onDismiss: () => void
}) {
  const dismiss = useRef(onDismiss)
  dismiss.current = onDismiss

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") dismiss.current()
    }
    globalThis.addEventListener("keydown", onKeyDown)
    return () => {
      globalThis.removeEventListener("keydown", onKeyDown)
    }
  }, [])

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
        style={{ left: at.x, top: at.y }}
        className={cn(
          "fixed z-50 min-w-[210px] rounded-lg border border-border-subtle",
          "bg-bg-raised py-1 shadow-xl",
        )}
      >
        {entries.map((entry, index) => (
          <MenuRow
            key={`${entry.label}-${String(index)}`}
            entry={entry}
            onDismiss={onDismiss}
          />
        ))}
      </div>
    </>
  )
}

/** A menu hung off a button — the `⋯` the Mac puts on a row or a toolbar. */
export function ApiMenuButton({
  label,
  entries,
  children,
}: {
  label: string
  entries: MenuEntry[]
  children: ReactNode
}) {
  const [open, setOpen] = useState(false)

  return (
    <div className="relative">
      <button
        type="button"
        title={label}
        aria-label={label}
        aria-haspopup="menu"
        aria-expanded={open}
        onClick={() => {
          setOpen((was) => !was)
        }}
        className="rounded p-1 text-text-secondary transition hover:bg-bg-raised hover:text-text-primary"
      >
        {children}
      </button>
      {open ? (
        <>
          <div
            className="fixed inset-0 z-40"
            onPointerDown={() => {
              setOpen(false)
            }}
          />
          <div
            role="menu"
            className={cn(
              "absolute right-0 top-full z-50 mt-1 min-w-[230px] rounded-lg",
              "border border-border-subtle bg-bg-raised py-1 shadow-xl",
            )}
          >
            {entries.map((entry, index) => (
              <MenuRow
                key={`${entry.label}-${String(index)}`}
                entry={entry}
                onDismiss={() => {
                  setOpen(false)
                }}
              />
            ))}
          </div>
        </>
      ) : null}
    </div>
  )
}

function MenuRow({ entry, onDismiss }: { entry: MenuEntry; onDismiss: () => void }) {
  return (
    <>
      {entry.separatorBefore === true ? <div className="my-1 h-px bg-border-subtle" /> : null}
      {entry.heading === true ? (
        <p className="px-3 py-1 text-[11px] uppercase tracking-wide text-text-tertiary">
          {entry.label}
        </p>
      ) : (
        <button
          type="button"
          role="menuitem"
          // The dismissing pointerdown listener runs first, so acting on
          // pointerdown here would never be reached — this fires on click.
          onClick={() => {
            entry.onSelect?.()
            onDismiss()
          }}
          className={cn(
            "flex w-full items-center gap-2 px-3 py-1 text-left text-[13px]",
            entry.danger === true
              ? "text-danger hover:bg-danger/20"
              : "text-text-primary hover:bg-accent/20",
          )}
        >
          {entry.label}
        </button>
      )}
    </>
  )
}
