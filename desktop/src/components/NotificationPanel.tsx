import { useState } from "react"
import { AlertTriangle, Bell, BellOff, CheckCircle2, FolderOpen, Info, XCircle, X } from "lucide-react"
import { Button } from "@/components/Controls"
import { useNotifications } from "@/hooks/useNotifications"
import { asDaemonError, revealPath } from "@/lib/daemon"
import { badgeText, relativeTime, type AppNotification, type ToastLevel } from "@/lib/notifications"

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
 * The bell in the device bar, with its unread count.
 *
 * Sits at the top-right so the toasts drop from underneath it, which is what
 * makes the two surfaces read as one thing on the Mac.
 */
export function NotificationBell() {
  const { unread, panelOpen, togglePanel } = useNotifications()
  const badge = panelOpen ? null : badgeText(unread)
  return (
    <button
      type="button"
      onClick={togglePanel}
      aria-label={badge === null ? "Notifications" : `Notifications, ${badge} unread`}
      title="Notifications"
      className="relative rounded-md p-1.5 text-text-secondary hover:bg-white/[0.06] hover:text-text-primary"
    >
      {panelOpen ? <Bell size={15} className="text-accent" /> : <Bell size={15} />}
      {badge === null ? null : (
        <span className="absolute -right-0.5 -top-0.5 rounded-full bg-danger px-1 text-[9px] font-bold leading-[13px] text-white">
          {badge}
        </span>
      )}
    </button>
  )
}

/**
 * The history column — the important toasts, newest first.
 *
 * A persistent right column rather than a popover, as `NotificationPanelView`
 * is: the point is to be able to go back to what an action said after its
 * toast has gone, which a thing that closes on the next click cannot do.
 */
export function NotificationPanel() {
  const { history, panelOpen, togglePanel, dismiss, clearHistory } = useNotifications()
  if (!panelOpen) return null
  return (
    <aside className="flex w-[320px] shrink-0 flex-col border-l border-border-subtle bg-bg-surface">
      <header className="flex shrink-0 items-center gap-2 border-b border-border-subtle px-3 py-2">
        <h2 className="flex-1 text-[13px] text-text-primary">Notifications</h2>
        {history.length === 0 ? null : <Button onClick={clearHistory}>Clear</Button>}
        <button
          type="button"
          onClick={togglePanel}
          aria-label="Close notifications"
          className="text-text-tertiary hover:text-text-primary"
        >
          <X size={13} />
        </button>
      </header>

      {history.length === 0 ? (
        <div className="flex flex-1 flex-col items-center justify-center gap-2 px-6 text-center">
          <BellOff size={20} className="text-text-tertiary" />
          <p className="text-text-tertiary">
            Nothing yet. Errors and anything that produced a file are kept here.
          </p>
        </div>
      ) : (
        <div className="min-h-0 flex-1 overflow-y-auto" data-selectable>
          {history.map((entry) => (
            <Row key={entry.id} entry={entry} onDismiss={dismiss} />
          ))}
        </div>
      )}
    </aside>
  )
}

function Row({
  entry,
  onDismiss,
}: {
  entry: AppNotification
  onDismiss: (id: string) => void
}) {
  const [failure, setFailure] = useState<string | null>(null)
  const Icon = ICONS[entry.level]
  return (
    <div className="flex gap-2.5 border-b border-border-subtle/50 px-3 py-2">
      <Icon size={14} className={`mt-0.5 shrink-0 ${TONES[entry.level]}`} />
      <div className="min-w-0 flex-1">
        <p className="break-words text-[12.5px] text-text-primary">{entry.message}</p>
        <p className="mt-0.5 text-[11px] text-text-tertiary">{relativeTime(entry.at, Date.now())}</p>
        {entry.revealPath === undefined ? null : (
          <button
            type="button"
            onClick={() => {
              revealPath(entry.revealPath ?? "").catch((thrown: unknown) => {
                setFailure(asDaemonError(thrown).message)
              })
            }}
            className="mt-1 flex items-center gap-1 rounded-md bg-white/[0.06] px-2 py-0.5 text-[11.5px] hover:bg-white/[0.12]"
          >
            <FolderOpen size={11} />
            Show in folder
          </button>
        )}
        {failure === null ? null : <p className="mt-1 text-[11px] text-danger">{failure}</p>}
      </div>
      <button
        type="button"
        aria-label="Dismiss"
        onClick={() => {
          onDismiss(entry.id)
        }}
        className="shrink-0 self-start text-text-tertiary hover:text-text-primary"
      >
        <X size={12} />
      </button>
    </div>
  )
}
