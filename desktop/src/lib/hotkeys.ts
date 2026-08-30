/**
 * Per-feature keyboard shortcuts.
 *
 * The Mac binds these through `KeyboardShortcuts` (Carbon), which makes them
 * *global* — they fire with the app in the background. Here they are handled in
 * the window, because OS-level registration arrives with the Quick Actions
 * panel and its tray icon (backlog 19–20 in `docs/desktop-parity.md`), and the
 * recorder says so rather than promising something it does not do. Everything
 * else is the Mac's model: at least one of Ctrl/Alt/⌘ is required so a shortcut
 * cannot be a bare key, Esc cancels a recording, Backspace clears the binding,
 * and an instant action runs where anything else opens.
 */

import { menuCommandFor } from "@/lib/menuKeys"

/**
 * One combination.
 *
 * The key is `KeyboardEvent.code` — the *physical* key — not `key`. With Alt
 * held, a layout reports the alternate character it produces (⌥O is "ø" on a
 * Mac), so a binding recorded from `key` would never match again.
 */
export interface Hotkey {
  code: string
  ctrl: boolean
  alt: boolean
  shift: boolean
  meta: boolean
}

/** Feature id → its shortcut. */
export type HotkeyBindings = Readonly<Record<string, Hotkey>>

/** The modifier half of an event, without its key. */
export interface Modifiers {
  ctrl: boolean
  alt: boolean
  shift: boolean
  meta: boolean
}

/** What a recorder needs off a `keydown` or `keyup`. */
export interface KeyState extends Modifiers {
  code: string
}

export function modifiersOf(event: {
  ctrlKey: boolean
  altKey: boolean
  shiftKey: boolean
  metaKey: boolean
}): Modifiers {
  return { ctrl: event.ctrlKey, alt: event.altKey, shift: event.shiftKey, meta: event.metaKey }
}

/**
 * A key that only ever modifies another one.
 *
 * Caps Lock is in here with the four real modifiers: it reports as a key of its
 * own, and a shortcut nobody can release is not a shortcut.
 */
export function isModifierCode(code: string): boolean {
  if (code === "CapsLock") return true
  return ["Control", "Alt", "Shift", "Meta"].some((name) => code.startsWith(name))
}

/**
 * The combination an event describes, or null when it is not one.
 *
 * Refused: a modifier on its own (no key has landed yet), and a combination
 * carrying nothing but Shift — a shortcut has to be out of reach of ordinary
 * typing, which is the rule the Mac's recorder applies as
 * `[.command, .option, .control]`.
 */
export function hotkeyFromEvent(event: KeyState): Hotkey | null {
  if (event.code === "" || isModifierCode(event.code)) return null
  if (!event.ctrl && !event.alt && !event.meta) return null
  return {
    code: event.code,
    ctrl: event.ctrl,
    alt: event.alt,
    shift: event.shift,
    meta: event.meta,
  }
}

/**
 * How a key prints. Anything unrecognised falls through as its own code, which
 * is ugly but true — better than a shortcut that renders as nothing.
 */
const KEY_LABELS: Readonly<Record<string, string>> = {
  ArrowDown: "↓",
  ArrowLeft: "←",
  ArrowRight: "→",
  ArrowUp: "↑",
  Backquote: "`",
  Backslash: "\\",
  BracketLeft: "[",
  BracketRight: "]",
  Comma: ",",
  End: "End",
  Enter: "Enter",
  Equal: "=",
  Home: "Home",
  Minus: "-",
  PageDown: "Page Down",
  PageUp: "Page Up",
  Period: ".",
  Quote: "'",
  Semicolon: ";",
  Slash: "/",
  Space: "Space",
  Tab: "Tab",
}

export function keyLabel(code: string): string {
  const named = KEY_LABELS[code]
  if (named !== undefined) return named
  if (code.startsWith("Key")) return code.slice(3)
  if (code.startsWith("Digit")) return code.slice(5)
  if (code.startsWith("Numpad")) return `Num ${code.slice(6)}`
  return code
}

/**
 * The modifiers, in each platform's own order: the Mac's ⌃⌥⇧⌘, which is what
 * `HotkeyRecording.modifierSymbols` prints, and Ctrl+Alt+Shift elsewhere.
 */
function modifierLabel(mods: Modifiers, mac: boolean): string {
  if (mac) {
    const symbols = [
      mods.ctrl ? "⌃" : "",
      mods.alt ? "⌥" : "",
      mods.shift ? "⇧" : "",
      mods.meta ? "⌘" : "",
    ]
    return symbols.join("")
  }
  const parts: string[] = []
  if (mods.ctrl) parts.push("Ctrl")
  if (mods.alt) parts.push("Alt")
  if (mods.shift) parts.push("Shift")
  // "Super" rather than "Win": this app also ships on Linux, where the key is
  // not a Windows logo and nobody calls it one.
  if (mods.meta) parts.push("Super")
  return parts.length === 0 ? "" : `${parts.join("+")}+`
}

export function formatHotkey(hotkey: Hotkey, mac: boolean): string {
  return `${modifierLabel(hotkey, mac)}${keyLabel(hotkey.code)}`
}

/** What the recorder shows while modifiers are held and no key has landed. */
export function modifierPreview(mods: Modifiers, mac: boolean): string {
  const label = modifierLabel(mods, mac)
  return label === "" ? "" : `${label}…`
}

export function sameHotkey(a: Hotkey, b: Hotkey): boolean {
  return (
    a.code === b.code &&
    a.ctrl === b.ctrl &&
    a.alt === b.alt &&
    a.shift === b.shift &&
    a.meta === b.meta
  )
}

/**
 * The feature an event is bound to, or null when nothing claims it.
 *
 * A combination the shell owns resolves to nothing even if something is bound
 * to it. The recorder refuses to store one, so this only catches a binding
 * written by some other build — but making it a rule here rather than relying on
 * which `keydown` listener was added first is the difference between a
 * guarantee and a coincidence.
 */
export function resolveHotkey(
  bindings: HotkeyBindings,
  event: KeyState,
  mac: boolean,
): string | null {
  const pressed = hotkeyFromEvent(event)
  if (pressed === null || reservedCommand(pressed, mac) !== null) return null
  for (const [id, hotkey] of Object.entries(bindings)) {
    if (sameHotkey(hotkey, pressed)) return id
  }
  return null
}

/** Which *other* feature already owns this combination. */
export function holderOf(
  bindings: HotkeyBindings,
  hotkey: Hotkey,
  exceptId: string,
): string | null {
  for (const [id, bound] of Object.entries(bindings)) {
    if (id !== exceptId && sameHotkey(bound, hotkey)) return id
  }
  return null
}

/**
 * The bindings with one feature's shortcut set, or cleared.
 *
 * Setting a combination takes it off whatever held it before: two features on
 * one shortcut means one of them silently never fires, and the Mac cannot reach
 * that state at all — the OS refuses the second registration.
 */
export function withHotkey(
  bindings: HotkeyBindings,
  id: string,
  hotkey: Hotkey | null,
): Record<string, Hotkey> {
  const next: Record<string, Hotkey> = {}
  for (const [key, bound] of Object.entries(bindings)) {
    if (key === id) continue
    if (hotkey !== null && sameHotkey(bound, hotkey)) continue
    next[key] = bound
  }
  if (hotkey !== null) next[id] = hotkey
  return next
}

/**
 * The shell's own keys, which a feature may not shadow.
 *
 * `useShellShortcuts` handles these before any feature binding is considered, so
 * a feature bound to one would simply never fire. The Mac needs no equivalent
 * guard: its per-feature hotkeys are registered with the OS and take
 * precedence over the app's own menu, which a key handler in a window cannot.
 */
/**
 * What the *page* claims.
 *
 * These overlap the menu's list on purpose, and it is not redundancy. The menu
 * binds an exact chord — ⌘W and nothing else — while `useShellShortcuts` asks
 * `hasModifier`, which on a Mac only looks at ⌘ and ignores a Ctrl held
 * alongside it. So ⌘W is the menu's and **⌃⌘W is still the page's**, and a
 * feature bound to it would lose. Trimming these as "unreachable" was tried;
 * the suite caught it.
 *
 * The names match the menu's labels so one key never has two names.
 */
const RESERVED: readonly { readonly code: string; readonly command: string }[] = [
  { code: "KeyK", command: "the command palette" },
  { code: "KeyT", command: "New Tab" },
  { code: "KeyW", command: "Close Tab" },
  { code: "KeyB", command: "Toggle Sidebar" },
  { code: "Backslash", command: "Split Pane" },
  { code: "Comma", command: "Settings…" },
  { code: "Equal", command: "Increase Font Size" },
  { code: "Minus", command: "Decrease Font Size" },
  { code: "Digit0", command: "Actual Size" },
]

/**
 * The shell command that owns this combination, or null.
 *
 * Two sources, because there are two claimants. The **menu** binds its
 * accelerators with the platform, so a feature bound to one would be shadowed
 * and simply never fire — those are asked about first, and they include the
 * Shift and Alt forms. What is left is what `useShellShortcuts` claims in the
 * page: the accelerator with no Alt and no Shift, compared against unshifted
 * keys. So ⌘K is the palette and ⌘⌥K is nobody's — a second modifier frees the
 * key up again, *unless* the menu took it.
 */
export function reservedCommand(hotkey: Hotkey, mac: boolean): string | null {
  const claimed = menuCommandFor(hotkey, mac)
  if (claimed !== null) return claimed
  const commandKey = mac ? hotkey.meta : hotkey.ctrl
  if (!commandKey || hotkey.alt || hotkey.shift) return null
  if (/^Digit[1-9]$/u.test(hotkey.code)) return `Show Tab ${hotkey.code.slice(5)}`
  return RESERVED.find((entry) => entry.code === hotkey.code)?.command ?? null
}

/**
 * What pressing a feature's shortcut does.
 *
 * The Mac's rule, in `HotkeyManager.install`: an instant action runs on the
 * spot and everything else opens its screen. Its **toggles** run too, flipping
 * whatever `activeOverrides` currently says — state this app does not track, so
 * a toggle opens instead of guessing a direction and writing it to a device.
 */
export function hotkeyEffect(kind: string): "run" | "open" {
  return kind === "instantAction" ? "run" : "open"
}
