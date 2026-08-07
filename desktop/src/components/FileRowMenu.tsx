import { useEffect, useRef } from "react"
import { Info } from "lucide-react"
import { cn } from "@/lib/cn"
import { batchLabel } from "@/lib/files"
import type { FileEntry } from "@/lib/wire"

export interface FileMenuTarget {
  entry: FileEntry
  x: number
  y: number
}

/**
 * A row's right-click menu.
 *
 * Hand-rolled for the same reason `TabMenu` is: a webview has no menu of its
 * own, and reaching for the OS one would mean another plugin and another
 * permission for five items.
 */
export function FileRowMenu({
  at,
  targets,
  onDismiss,
  onInfo,
  onCopy,
  onCut,
  onPull,
  onDelete,
}: {
  at: { x: number; y: number }
  /** Already resolved by `targetsFor` — one row, or the whole selection. */
  targets: FileEntry[]
  onDismiss: () => void
  onInfo: (entry: FileEntry) => void
  onCopy: (targets: FileEntry[]) => void
  onCut: (targets: FileEntry[]) => void
  onPull: (targets: FileEntry[]) => void
  onDelete: (targets: FileEntry[]) => void
}) {
  const only = targets.length === 1 ? (targets[0] ?? null) : null
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

  const choose = (run: (targets: FileEntry[]) => void) => () => {
    run(targets)
    onDismiss()
  }

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
        className="fixed z-50 min-w-[210px] rounded-lg border border-border-subtle bg-bg-raised py-1 shadow-xl"
      >
        {only === null ? (
          <p className="px-3 py-1 text-[12px] text-text-tertiary">{batchLabel(names(targets))}</p>
        ) : (
          <Item
            onSelect={() => {
              onInfo(only)
              onDismiss()
            }}
          >
            <Info size={12} />
            Get Info
          </Item>
        )}
        <Separator />
        <Item onSelect={choose(onCopy)}>Copy</Item>
        <Item onSelect={choose(onCut)}>Cut</Item>
        <Item onSelect={choose(onPull)}>Pull to this computer</Item>
        <Separator />
        {/* Opens the pane's confirmation, the way the Mac's context menu
            raises `confirmationDialog` rather than confirming in the menu. */}
        <Item danger onSelect={choose(onDelete)}>
          Delete
        </Item>
      </div>
    </>
  )
}

function names(targets: FileEntry[]): string[] {
  return targets.map((entry) => entry.name)
}

function Separator() {
  return <div className="my-1 h-px bg-border-subtle" />
}

function Item({
  onSelect,
  danger = false,
  children,
}: {
  onSelect: () => void
  danger?: boolean
  children: React.ReactNode
}) {
  return (
    <button
      type="button"
      role="menuitem"
      // The dismissing pointerdown listener runs first, so acting on
      // pointerdown here would never be reached — this fires on click.
      onClick={onSelect}
      className={cn(
        "flex w-full items-center gap-2 px-3 py-1 text-left text-[13px]",
        danger ? "text-danger hover:bg-danger/20" : "text-text-primary hover:bg-accent/20",
      )}
    >
      {children}
    </button>
  )
}
