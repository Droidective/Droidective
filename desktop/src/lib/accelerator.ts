import type { Hotkey } from "@/lib/hotkeys"

/**
 * A recorded shortcut in the syntax the OS registration parses.
 *
 * Built from `code` rather than from a printable character, and that is the
 * whole reason this is one line of translation instead of a table: a binding is
 * recorded as a *physical* key so it survives a layout change, and the
 * platform's shortcut parser takes exactly those names — "KeyL", "Digit3",
 * "F5". The two agree without anything to keep in step.
 *
 * "Super" for meta, which is what the parser calls it on Windows and Linux; a
 * Mac's ⌘ arrives under the same name.
 */
export function accelerator(hotkey: Hotkey): string {
  const parts: string[] = []
  if (hotkey.ctrl) parts.push("Ctrl")
  if (hotkey.alt) parts.push("Alt")
  if (hotkey.shift) parts.push("Shift")
  if (hotkey.meta) parts.push("Super")
  parts.push(hotkey.code)
  return parts.join("+")
}
