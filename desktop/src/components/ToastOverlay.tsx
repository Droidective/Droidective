import { useState } from "react"
import { AlertTriangle, CheckCircle2, Clipboard, FolderOpen, Info, XCircle, X } from "lucide-react"
import { useNotifications } from "@/hooks/useNotifications"
import { asDaemonError, copyText, revealPath } from "@/lib/daemon"
import type { Toast, ToastLevel } from "@/lib/notifications"

const ICONS = {
  success: CheckCircle2,
  info: Info,
  warning: AlertTriangle,
  error: XCircle,
} as const

const TONES: Record<ToastLevel, string> = {
  success: "text-accent",
  info: "text-text-secondary",
  warning: "text-warn",
  error: "text-danger",
}

/**
 * Transient results, stacked top-right under the notifications bell — the
 * Mac's `ToastOverlay`. The important ones are also kept in the panel, which
 * is why a toast can be let go of after five seconds without losing anything.
 */
export function ToastOverlay() {
  const { toasts, dismissToast } = useNotifications()
  if (toasts.length === 0) return null
  return (
    <div className="pointer-events-none fixed right-4 top-14 z-50 flex flex-col items-end gap-2">
      {toasts.map((toast) => (
        <ToastRow key={toast.id} toast={toast} onDismiss={dismissToast} />
      ))}
    </div>
  )
}

function ToastRow({ toast, onDismiss }: { toast: Toast; onDismiss: (id: string) => void }) {
  const [failure, setFailure] = useState<string | null>(null)
  const [copied, setCopied] = useState(false)
  const Icon = ICONS[toast.level]

  return (
    <div className="pointer-events-auto flex max-w-[460px] items-center gap-2.5 rounded-lg border border-border-subtle bg-bg-raised px-3.5 py-2.5 shadow-xl">
      <Icon size={15} className={`shrink-0 ${TONES[toast.level]}`} />
      <span className="min-w-0 flex-1 break-words text-[13px] text-text-primary">
        {toast.message}
      </span>

      {toast.copyText === undefined ? null : (
        <Action
          icon={Clipboard}
          label={copied ? "Copied" : "Copy"}
          onClick={() => {
            copyText(toast.copyText ?? "").then(
              () => {
                setCopied(true)
              },
              (thrown: unknown) => {
                setFailure(asDaemonError(thrown).message)
              },
            )
          }}
        />
      )}
      {toast.revealPath === undefined ? null : (
        <Action
          icon={FolderOpen}
          label="Show in folder"
          onClick={() => {
            revealPath(toast.revealPath ?? "").catch((thrown: unknown) => {
              setFailure(asDaemonError(thrown).message)
            })
          }}
        />
      )}
      {failure === null ? null : <span className="text-[11px] text-danger">{failure}</span>}

      <button
        type="button"
        aria-label="Dismiss"
        onClick={() => {
          onDismiss(toast.id)
        }}
        className="shrink-0 text-text-tertiary hover:text-text-primary"
      >
        <X size={12} />
      </button>
    </div>
  )
}

function Action({
  icon: Icon,
  label,
  onClick,
}: {
  icon: typeof Clipboard
  label: string
  onClick: () => void
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="flex shrink-0 items-center gap-1 rounded-md bg-white/[0.08] px-2 py-1 text-[11.5px] text-text-primary hover:bg-white/[0.14]"
    >
      <Icon size={11} />
      {label}
    </button>
  )
}
