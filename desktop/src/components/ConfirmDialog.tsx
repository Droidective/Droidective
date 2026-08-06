import { useEffect } from "react"
import { Button } from "@/components/Controls"

/**
 * SwiftUI's `confirmationDialog`, as close as a webview gets.
 *
 * The Mac asks before anything irreversible — deleting files, emptying the
 * crash buffer, stopping a recording — with a titled question, an explanatory
 * line, a destructive verb and Cancel. This app used to arm a button for a
 * second press instead, which is a different interaction someone moving
 * between the two would have to relearn, so the dialog is what both do now.
 */
export function ConfirmDialog({
  title,
  message,
  confirmLabel,
  destructive = true,
  extraLabel,
  onExtra,
  onConfirm,
  onCancel,
}: {
  title: string
  message?: string | undefined
  confirmLabel: string
  destructive?: boolean
  /** A third choice, when the Mac's dialog offers one. */
  extraLabel?: string | undefined
  onExtra?: (() => void) | undefined
  onConfirm: () => void
  onCancel: () => void
}) {
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      // Escape cancels, as it does in every macOS sheet. Return deliberately
      // does not confirm: the destructive button is never the default one.
      if (event.key === "Escape") onCancel()
    }
    globalThis.addEventListener("keydown", onKeyDown)
    return () => {
      globalThis.removeEventListener("keydown", onKeyDown)
    }
  }, [onCancel])

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-8">
      <button
        type="button"
        aria-label="Cancel"
        onClick={onCancel}
        className="absolute inset-0 cursor-default"
      />
      <div
        role="alertdialog"
        aria-modal="true"
        aria-label={title}
        className="relative w-[420px] max-w-full rounded-xl border border-border-subtle bg-bg-raised p-5 shadow-2xl"
      >
        <h2 className="text-[14px] font-medium text-text-primary">{title}</h2>
        {message === undefined ? null : (
          <p className="mt-1.5 text-[12.5px] text-text-secondary">{message}</p>
        )}
        <div className="mt-4 flex justify-end gap-2">
          <Button onClick={onCancel}>Cancel</Button>
          {extraLabel === undefined || onExtra === undefined ? null : (
            <Button onClick={onExtra}>{extraLabel}</Button>
          )}
          <Button tone={destructive ? "danger" : "primary"} onClick={onConfirm}>
            {confirmLabel}
          </Button>
        </div>
      </div>
    </div>
  )
}
