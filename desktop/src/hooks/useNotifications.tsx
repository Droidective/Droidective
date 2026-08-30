import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from "react"
import { postNotification } from "@/lib/daemon"
import {
  systemNotification,
  toNotification,
  toToast,
  withNotification,
  TOAST_TTL_MS,
  type AppNotification,
  type Toast,
  type ToastInput,
} from "@/lib/notifications"
import { isWindowFocused, onWindowFocusChanged } from "@/lib/window-focus"

/** A rejection with nowhere useful to go. Named so the intent is not "oops". */
const ignore = () => {}

/**
 * Whether this window is the one being looked at, as a ref.
 *
 * A ref rather than state: this changes every time someone switches app, and
 * re-rendering every screen in the window for that would be absurd. Nothing
 * renders from it — it is read at the moment a result lands.
 *
 * It starts optimistic. Until the window manager has answered, a result is
 * assumed to be one you are looking at: missing a notification costs someone a
 * glance at the window, where posting a spurious one interrupts them for
 * something already on their screen.
 */
function useWindowFocus(): { current: boolean } {
  const focused = useRef(true)
  useEffect(() => {
    let live = true
    let unlisten: (() => void) | null = null
    void isWindowFocused().then((current) => {
      if (live) focused.current = current
    }, ignore)
    void onWindowFocusChanged((next) => {
      focused.current = next
    }).then((stop) => {
      if (live) unlisten = stop
      else stop()
    }, ignore)
    return () => {
      live = false
      unlisten?.()
    }
  }, [])
  return focused
}

export interface Notifications {
  toasts: Toast[]
  history: AppNotification[]
  unread: number
  panelOpen: boolean

  /** Report an action's result. The one call every screen makes. */
  show: (input: ToastInput) => void
  /**
   * Post a native notification directly, with no toast.
   *
   * `SystemNotifier.postIfBackgrounded` on the Mac, and it exists for the same
   * one caller: a batch of installs reports each APK as its own toast and then
   * says one thing about the batch. Only reaches the tray while the window is
   * not the one being looked at.
   */
  notifyIfBackgrounded: (title: string, body: string, sound?: boolean) => void
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

  const focused = useWindowFocus()

  const dismissToast = useCallback((id: string) => {
    setToasts((current) => current.filter((toast) => toast.id !== id))
  }, [])

  const notifyIfBackgrounded = useCallback((title: string, body: string, sound = false) => {
    if (focused.current) return
    // A notification that cannot be posted is not worth a second failure on
    // screen — the toast already said what happened, in the window the person
    // is about to come back to.
    void postNotification({ title, body, sound }).catch(() => {})
  }, [focused])

  const show = useCallback(
    (input: ToastInput) => {
      nextID.current += 1
      const toast = toToast(input, `t${String(nextID.current)}`)
      setToasts((current) => [...current, toast])
      const native = systemNotification(toast, !focused.current)
      if (native !== null) {
        void postNotification(native).catch(() => {})
      }
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
    [dismissToast, focused],
  )

  const value = useMemo<Notifications>(
    () => ({
      toasts,
      history,
      unread,
      panelOpen,
      show,
      notifyIfBackgrounded,
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
    [toasts, history, unread, panelOpen, show, notifyIfBackgrounded, dismissToast],
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
