/**
 * Toasts and the notification history.
 *
 * Two surfaces over one event, exactly as the Mac has it: a toast appears
 * top-right and goes away on its own, and the *important* subset is also kept
 * in the panel behind the device bar's bell. Which of those an event gets is
 * the rule worth testing, so it lives here rather than at each call site —
 * `AppState.showToast` decides it once on the Mac and this is the same
 * decision.
 */

/** The Mac's `Toast.Level`. */
export type ToastLevel = "success" | "info" | "warning" | "error"

export interface ToastInput {
  message: string
  ok: boolean
  /** Defaults to success/error from `ok`, as the Mac's initialiser does. */
  level?: ToastLevel
  copyText?: string
  /** A host path an action produced, for a Show in folder button. */
  revealPath?: string
  /** Overrides the "is this worth keeping" rule below. */
  important?: boolean
  /**
   * Overrides the "is this worth interrupting for" rule. Defaults to
   * `important`; a batch that posts one summary opts its members out, as the
   * Mac's per-APK install toasts do.
   */
  notifiesWhenBackgrounded?: boolean
}

export interface Toast {
  id: string
  message: string
  level: ToastLevel
  copyText: string | undefined
  revealPath: string | undefined
  important: boolean
  /** Whether this mirrors to a native notification while the window is not the
   * one being looked at. The Mac's `Toast.notifiesWhenBackgrounded`. */
  notifiesWhenBackgrounded: boolean
}

/** A kept toast. The Mac's `AppNotification`. */
export interface AppNotification {
  id: string
  message: string
  level: ToastLevel
  copyText: string | undefined
  revealPath: string | undefined
  /** Epoch millis, so the row can say how long ago without a live clock. */
  at: number
}

/** How long a toast stays up. Five seconds, as on the Mac. */
export const TOAST_TTL_MS = 5000

/** The history is bounded; the Mac keeps 200. */
export const NOTIFICATION_LIMIT = 200

/**
 * Whether an event is worth keeping after its toast fades.
 *
 * Errors and warnings always are — they are the thing someone scrolls back to
 * find. A success only when it produced something to go back *to*, which in
 * practice means a file path: "Copied to the clipboard" is a confirmation, not
 * a record, and a history full of them is a history nobody reads.
 */
export function isImportant(input: ToastInput): boolean {
  if (input.important !== undefined) return input.important
  const level = resolveLevel(input)
  return level === "error" || level === "warning" || input.revealPath !== undefined
}

export function resolveLevel(input: ToastInput): ToastLevel {
  return input.level ?? (input.ok ? "success" : "error")
}

export function toToast(input: ToastInput, id: string): Toast {
  const important = isImportant(input)
  return {
    id,
    message: input.message,
    level: resolveLevel(input),
    copyText: input.copyText,
    revealPath: input.revealPath,
    important,
    notifiesWhenBackgrounded: input.notifiesWhenBackgrounded ?? important,
  }
}

/** A native notification's title and body, or null when this toast earns none.
 *
 * The Mac's `SystemNotifier` decides the same two things, and the titles are
 * its titles verbatim: someone who moves between the two apps sees the same
 * words in the same tray. The `backgrounded` argument is the whole condition —
 * a result you are already looking at needs no second surface, and posting one
 * anyway is the failure mode every chatty app has.
 */
export function systemNotification(
  toast: Toast,
  backgrounded: boolean,
): { title: string; body: string; sound: boolean } | null {
  if (!toast.notifiesWhenBackgrounded || !backgrounded) return null
  return {
    title: systemTitle(toast.level),
    body: toast.message,
    sound: toast.level === "error",
  }
}

/** `SystemNotifier.title(for:)`, word for word. */
export function systemTitle(level: ToastLevel): string {
  switch (level) {
    case "success":
      return "Task finished"
    case "error":
      return "Task failed"
    default:
      return "Droidective"
  }
}

export function toNotification(toast: Toast, at: number): AppNotification {
  return {
    id: toast.id,
    message: toast.message,
    level: toast.level,
    copyText: toast.copyText,
    revealPath: toast.revealPath,
    at,
  }
}

/** Newest first, capped. Anything past the cap falls off the end. */
export function withNotification(
  history: readonly AppNotification[],
  entry: AppNotification,
  limit = NOTIFICATION_LIMIT,
): AppNotification[] {
  return [entry, ...history].slice(0, limit)
}

/**
 * "just now" / "4m ago" / "2h ago" — a relative stamp the row can render
 * without a ticking clock.
 */
export function relativeTime(at: number, now: number): string {
  const seconds = Math.max(0, Math.round((now - at) / 1000))
  if (seconds < 45) return "just now"
  const minutes = Math.round(seconds / 60)
  if (minutes < 60) return `${String(Math.max(1, minutes))}m ago`
  const hours = Math.round(minutes / 60)
  if (hours < 24) return `${String(hours)}h ago`
  return `${String(Math.round(hours / 24))}d ago`
}

/** What the bell shows. Over 99 it stops counting, as the Mac's badge does. */
export function badgeText(unread: number): string | null {
  if (unread <= 0) return null
  return unread > 99 ? "99+" : String(unread)
}
