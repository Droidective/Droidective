/**
 * The one place the host OS shows through.
 *
 * Shortcut hints are the visible half: this app ships on Windows and Linux,
 * where a tooltip promising ⌘W is simply wrong, and it is developed on a Mac,
 * where Ctrl+W is.
 */

/** "⌘W" on a Mac, "Ctrl+W" elsewhere. */
export function shortcutLabel(key: string, mac: boolean): string {
  return mac ? `⌘${key.toUpperCase()}` : `Ctrl+${key.toUpperCase()}`
}

export function isMacHost(userAgent: string): boolean {
  return userAgent.includes("Macintosh") || userAgent.includes("Mac OS X")
}

export const IS_MAC = isMacHost(navigator.userAgent)

export function isLinuxHost(userAgent: string): boolean {
  // "Android" also contains "Linux", and this app talks *to* Android — so the
  // string that matters is the one WebKitGTK sends, not the substring.
  return userAgent.includes("Linux") && !userAgent.includes("Android")
}

/**
 * Whether the window itself can be transparent, which is what makes the
 * Appearance ▸ Opacity slider do anything.
 *
 * Not on Linux, and the reason is the menu bar: there the app draws its own
 * GTK menu bar above the webview, and that strip has nothing to paint itself
 * on when the window is transparent — File, Edit and View end up with the
 * desktop showing through them. `tauri.linux.conf.json` turns the window's
 * transparency off for the same reason, and the two have to agree: this
 * decides whether the *page* paints itself translucent, that decides whether
 * there is anything behind it to see.
 */
export const TRANSPARENCY_SUPPORTED = !isLinuxHost(navigator.userAgent)

/** The accelerator key for this host — ⌘ on a Mac, Ctrl everywhere else. */
export function hasModifier(event: { metaKey: boolean; ctrlKey: boolean }): boolean {
  return IS_MAC ? event.metaKey : event.ctrlKey
}
