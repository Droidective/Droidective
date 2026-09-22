import { useEffect } from "react"
import { Button } from "@/components/Controls"

/**
 * SwiftUI's `.alert` with a single `OK` — a statement, not a question.
 *
 * The sibling of `ConfirmDialog`, and deliberately not a toast: the Mac uses an
 * alert where the answer has to be read before anything else happens (an import
 * that failed, a device that dropped off mid-feed), and a toast that slides away
 * on a timer is a different interaction someone moving between the two apps
 * would have to relearn.
 *
 * `OK` is the default action here, so Return dismisses as well as Escape —
 * unlike the confirm dialog, where the primary button is destructive and Return
 * must not reach it.
 */
export function AlertDialog({
  title,
  message,
  dismissLabel = "OK",
  onDismiss,
}: {
  title: string
  message?: string | undefined
  /** What the one button says, for the rare alert that names its own. */
  dismissLabel?: string
  onDismiss: () => void
}) {
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape" || event.key === "Enter") onDismiss()
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
        aria-label={dismissLabel}
        onClick={onDismiss}
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
        <div className="mt-4 flex justify-end">
          <Button tone="primary" onClick={onDismiss}>
            {dismissLabel}
          </Button>
        </div>
      </div>
    </div>
  )
}
