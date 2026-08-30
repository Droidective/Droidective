import { invoke } from "@tauri-apps/api/core"
import type { TrayEntry } from "@/lib/tray"

/**
 * The host, not the daemon.
 *
 * These reach the clipboard, the file manager, the notification centre, the
 * tray and the window itself — this process's own capabilities rather than
 * anything adb does. They live beside the daemon calls because they arrive the
 * same way and fail the same way, and are re-exported from `@/lib/daemon` so
 * there is still one import for everything the page asks Rust for.
 *
 * Every one of them goes through a command rather than a plugin's JS API, so
 * the webview's capability file stays at `core:default` and a page cannot copy,
 * open, notify or quit on its own.
 */

export function copyText(text: string): Promise<void> {
  return invoke("copy_text", { text })
}

export function revealPath(path: string): Promise<void> {
  return invoke("reveal_path", { path })
}

/**
 * Posts a native notification. Rejects when the platform would not show one —
 * a Linux session with no notification daemon running, say — which is never
 * worth reporting: the toast already said it in the window being returned to.
 */
export function postNotification(args: {
  title: string
  body: string
  sound: boolean
}): Promise<void> {
  return invoke("post_notification", args)
}

/**
 * The tray icon's menu — see `lib/tray.ts` for what goes in it and why the
 * page decides rather than the Rust side.
 */
export function setTrayMenu(entries: TrayEntry[]): Promise<void> {
  return invoke("set_tray_menu", { entries })
}

/** Mirrors Settings ▸ General ▸ Keep running in the background into Rust,
 * which is where the close button's meaning is decided. */
export function setBackgroundMode(enabled: boolean): Promise<void> {
  return invoke("set_background_mode", { enabled })
}

/** False when no tray icon could be created — hiding the window would then
 * leave no way back to it, so background mode is not offered. */
export function backgroundAvailable(): Promise<boolean> {
  return invoke<boolean>("background_available")
}

/** Brings the window back. The Mac's `activateMainWindow`. */
export function showMainWindow(): Promise<void> {
  return invoke("show_main_window")
}

/** Quits for real — the tray's only way out once the window hides. */
export function quitApp(): Promise<void> {
  return invoke("quit_app")
}

/** Where pulls and exports land, as the Rust side resolves it. */
export function capturesFolder(): Promise<string> {
  return invoke<string>("captures_folder")
}

/** Opens an external link. The Rust side refuses anything but https. */
export function openUrl(url: string): Promise<void> {
  return invoke("open_url", { url })
}

/** Writes into ~/Downloads/Droidective and returns where it landed. */
export function exportText(name: string, contents: string): Promise<string> {
  return invoke<string>("export_text", { name, contents })
}
