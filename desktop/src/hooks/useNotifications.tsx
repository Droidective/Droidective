import { createContext, useCallback, useContext, useMemo, useRef, useState } from "react"
import {
  toNotification,
  toToast,
  withNotification,
  TOAST_TTL_MS,
  type AppNotification,
  type Toast,
  type ToastInput,
} from "@/lib/notifications"

export interface Notifications {
  toasts: Toast[]
  history: AppNotification[]
  unread: number
  panelOpen: boolean

  /** Report an action's result. The one call every screen makes. */
  show: (input: ToastInput) => void
  dismissToast: (id: string) => void
  togglePanel: () => void
  dismiss: (id: string) => void
  clearHistory: () => void
}

const NotificationsContext = createContext<Notifications | null>(null)

/**
 * Toasts and their history, for the whole window.
 *
 * A context rather than props because it is genuinely app-wide state — the
 * Mac keeps it on `AppState` for the same reason. Every screen reports a
 * result, and threading a callback down through the pane area to each one
 * would be prop-drilling with extra steps.
 */
export function NotificationsProvider({ children }: { children: React.ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([])
  const [history, setHistory] = useState<AppNotification[]>([])
  const [unread, setUnread] = useState(0)
  const [panelOpen, setPanelOpen] = useState(false)
  // Monotonic rather than random: two results in the same millisecond must not
  // collide, and a stable id is what lets a toast and its history row be
  // dismissed as one thing.
  const nextID = useRef(0)

  const dismissToast = useCallback((id: string) => {
    setToasts((current) => current.filter((toast) => toast.id !== id))
  }, [])

  const show = useCallback(
    (input: ToastInput) => {
      nextID.current += 1
      const toast = toToast(input, `t${String(nextID.current)}`)
      setToasts((current) => [...current, toast])
      if (toast.important) {
        setHistory((current) => withNotification(current, toNotification(toast, Date.now())))
        // Only counts while the panel is shut; opening it is what marks read.
        setPanelOpen((open) => {
          if (!open) setUnread((count) => count + 1)
          return open
        })
      }
      globalThis.setTimeout(() => {
        dismissToast(toast.id)
      }, TOAST_TTL_MS)
    },
    [dismissToast],
  )

  const value = useMemo<Notifications>(
    () => ({
      toasts,
      history,
      unread,
      panelOpen,
      show,
      dismissToast,
      togglePanel: () => {
        setPanelOpen((open) => {
          if (!open) setUnread(0)
          return !open
        })
      },
      dismiss: (id: string) => {
        setHistory((current) => current.filter((entry) => entry.id !== id))
      },
      clearHistory: () => {
        setHistory([])
      },
    }),
    [toasts, history, unread, panelOpen, show, dismissToast],
  )

  return <NotificationsContext value={value}>{children}</NotificationsContext>
}

/**
 * The reporting surface every screen uses.
 *
 * Throws outside the provider rather than returning a no-op: a screen whose
 * results silently go nowhere is the defect this replaces, not a mode worth
 * supporting.
 */
export function useNotifications(): Notifications {
  const value = useContext(NotificationsContext)
  if (value === null) {
    throw new Error("useNotifications used outside NotificationsProvider")
  }
  return value
}
