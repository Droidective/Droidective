import { useEffect, type ReactNode } from "react"

import { methodColor } from "@/lib/api/labels"
import type { HttpMethod } from "@/lib/api/model"
import { cn } from "@/lib/cn"

/**
 * The pieces the API pane reuses across its sidebar, editor, response pane and
 * sheets.
 *
 * Their own file rather than a component library: these are the Mac's own
 * controls (`ApiKeyValueEditor`, `ApiMultipartEditor`, the method badge) and
 * they are shaped by that view, not by a general-purpose design system.
 */

/** `SwiftUI`'s sheet, as close as a webview gets — the app's own shape. */
export function ApiSheet({
  title,
  width = 420,
  onDismiss,
  children,
  footer,
}: {
  title: string
  width?: number
  onDismiss: () => void
  children: ReactNode
  footer: ReactNode
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
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-8">
      <button
        type="button"
        aria-label="Cancel"
        onClick={onDismiss}
        className="absolute inset-0 cursor-default"
      />
      <dialog
        open
        aria-modal="true"
        aria-label={title}
        style={{ width }}
        className={cn(
          "relative flex max-h-full max-w-full flex-col gap-3 overflow-hidden rounded-xl",
          "border border-border-subtle bg-bg-raised p-5 shadow-2xl",
        )}
      >
        <h2 className="text-[14px] font-medium text-text-primary">{title}</h2>
        <div className="flex min-h-0 flex-1 flex-col gap-3 overflow-auto">{children}</div>
        <div className="flex items-center justify-end gap-2">{footer}</div>
      </dialog>
    </div>
  )
}

/** The fixed-width method column, so names line up down the tree. */
export function MethodBadge({ method }: { method: HttpMethod }) {
  return (
    <span className={cn("w-[38px] shrink-0 font-mono text-[10px] font-bold", methodColor(method))}>
      {method}
    </span>
  )
}

export function SectionHeader({ title, children }: { title: string; children?: ReactNode }) {
  return (
    <div className="flex items-center justify-between px-3 py-2">
      <span className="text-[13px] font-medium text-text-primary">{title}</span>
      {children}
    </div>
  )
}

export function IconButton({
  label,
  onClick,
  children,
  disabled = false,
}: {
  label: string
  onClick: () => void
  children: ReactNode
  disabled?: boolean
}) {
  return (
    <button
      type="button"
      title={label}
      aria-label={label}
      disabled={disabled}
      onClick={onClick}
      className={cn(
        "rounded p-1 text-text-secondary transition hover:bg-bg-raised hover:text-text-primary",
        "disabled:cursor-not-allowed disabled:opacity-40",
      )}
    >
      {children}
    </button>
  )
}

export function EmptyNote({ title, detail }: { title: string; detail?: string }) {
  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-1 p-4 text-center">
      <span className="text-[12px] text-text-secondary">{title}</span>
      {detail === undefined ? null : (
        <span className="text-[11px] text-text-tertiary">{detail}</span>
      )}
    </div>
  )
}
