import { getCurrentWindow } from "@tauri-apps/api/window"

/**
 * Whether this window is the one being looked at.
 *
 * The Mac reads `NSApp.isActive`; this is the same question asked of the window
 * manager rather than of the document. `document.hasFocus()` was the obvious
 * spelling and is the wrong one: it answers for the *document*, so a window
 * that is plainly in front reports false whenever focus sits somewhere the DOM
 * does not own — and in jsdom it is false outright. Getting this wrong posts a
 * tray notification for a result already on screen, which is the single most
 * irritating thing a desktop app does.
 *
 * A thin module so the calls have a seam: everything above it is testable
 * without a webview.
 */
export async function isWindowFocused(): Promise<boolean> {
  // `async` so that `getCurrentWindow()` throwing — which is what it does
  // outside a Tauri webview, in a unit test or a plain browser — arrives as a
  // rejection the caller already handles rather than as an exception thrown
  // out of a React effect.
  return await getCurrentWindow().isFocused()
}

/** Calls back on every change, and answers with the unsubscribe. */
export async function onWindowFocusChanged(
  onChange: (focused: boolean) => void,
): Promise<() => void> {
  return await getCurrentWindow().onFocusChanged(({ payload }) => {
    onChange(payload)
  })
}
