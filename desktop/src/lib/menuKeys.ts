/**
 * Which keystrokes the native menu owns.
 *
 * The window menu binds its accelerators with the platform, and this app also
 * listens for keys in the page. Both answering the same combination is the bug
 * to avoid: Ctrl+W would close two tabs, and a keystroke that destroys twice as
 * much as it should is worse than one that does nothing.
 *
 * **The menu wins.** That is the Mac's own arrangement — `NSMenu` sees a key
 * before any view does, which `ADTApp.swift` relies on for the one exit that
 * always works — and it fails in the recoverable direction: if a platform ever
 * failed to deliver an accelerator to a focused webview, the command is still
 * one menu click away, whereas a double-fire silently destroys work.
 *
 * The list is duplicated from `src-tauri/src/menu.rs` because Rust builds the
 * menu and the page handles the keys; `menuKeys.test.ts` reads that file and
 * fails if the two disagree, which is the same guard `hints.test.ts` uses for
 * the pane router.
 */

import { IS_MAC } from "@/lib/platform"

/**
 * Every accelerator the menu binds, with the command it runs.
 *
 * The name travels with it so the hotkey recorder can refuse a combination *by
 * name* — "⇧⌘D is Split Terminal Vertically" — rather than saying only that it
 * is taken. `menuKeys.test.ts` checks both halves against the Rust table, so a
 * relabelled menu item cannot leave a stale name here.
 */
export interface MenuAccelerator {
  accelerator: string
  command: string
}

export const MENU_COMMANDS: readonly MenuAccelerator[] = [
  { accelerator: "CmdOrCtrl+Shift+Alt+N", command: "New Window" },
  { accelerator: "CmdOrCtrl+Shift+N", command: "New Terminal" },
  { accelerator: "CmdOrCtrl+Shift+D", command: "Split Terminal Vertically" },
  { accelerator: "CmdOrCtrl+Shift+E", command: "Split Terminal Horizontally" },
  { accelerator: "CmdOrCtrl+Shift+W", command: "Close Terminal" },
  { accelerator: "CmdOrCtrl+Shift+R", command: "Rename Terminal…" },
  { accelerator: "CmdOrCtrl+Shift+]", command: "Next Terminal" },
  { accelerator: "CmdOrCtrl+Shift+[", command: "Previous Terminal" },
  { accelerator: "CmdOrCtrl+.", command: "Manage Features" },
  { accelerator: "CmdOrCtrl+,", command: "Settings…" },
  { accelerator: "CmdOrCtrl+B", command: "Toggle Sidebar" },
  { accelerator: "CmdOrCtrl+=", command: "Increase Font Size" },
  { accelerator: "CmdOrCtrl+-", command: "Decrease Font Size" },
  { accelerator: "CmdOrCtrl+Shift+0", command: "Actual Size" },
  { accelerator: "CmdOrCtrl+T", command: "New Tab" },
  { accelerator: "CmdOrCtrl+W", command: "Close Tab" },
  { accelerator: "Ctrl+Tab", command: "Next Tab" },
  { accelerator: "Ctrl+Shift+Tab", command: "Previous Tab" },
  { accelerator: "Alt+1", command: "Sidebar Item 1" },
  { accelerator: "Alt+2", command: "Sidebar Item 2" },
  { accelerator: "Alt+3", command: "Sidebar Item 3" },
  { accelerator: "Alt+4", command: "Sidebar Item 4" },
  { accelerator: "Alt+5", command: "Sidebar Item 5" },
  { accelerator: "Alt+6", command: "Sidebar Item 6" },
  { accelerator: "Alt+7", command: "Sidebar Item 7" },
  { accelerator: "Alt+8", command: "Sidebar Item 8" },
  { accelerator: "Alt+9", command: "Sidebar Item 9" },
  { accelerator: "Alt+0", command: "Sidebar Item 10" },
]

/** An accelerator, or a keypress, in one comparable shape. */
interface Chord {
  /** ⌘ on a Mac, Ctrl elsewhere — Tauri's `CmdOrCtrl`. */
  accelerator: boolean
  /** A literal `Ctrl`, which on a Mac is *not* the accelerator. */
  control: boolean
  shift: boolean
  alt: boolean
  /** Lowercased: "n", "tab", "]", "1". */
  key: string
}

/**
 * Parses Tauri's syntax. Unknown modifiers are kept as part of no chord — an
 * accelerator this cannot read must not silently match everything.
 */
export function parseAccelerator(accelerator: string): Chord | null {
  const parts = accelerator.split("+")
  const key = parts.at(-1)?.toLowerCase() ?? ""
  if (key.length === 0 || parts.length < 2) return null
  const chord: Chord = { accelerator: false, control: false, shift: false, alt: false, key }
  for (const part of parts.slice(0, -1)) {
    switch (part) {
      case "CmdOrCtrl":
        chord.accelerator = true
        break
      case "Ctrl":
        chord.control = true
        break
      case "Shift":
        chord.shift = true
        break
      case "Alt":
        chord.alt = true
        break
      default:
        return null
    }
  }
  return chord
}

export interface KeyLike {
  key: string
  code: string
  ctrlKey: boolean
  metaKey: boolean
  shiftKey: boolean
  altKey: boolean
}

/**
 * The accelerator key a physical code names.
 *
 * A table rather than `event.key`, because `key` is what the *layout* produced:
 * Option+1 on a Mac is "¡", Shift+1 is "!", and Shift+] is "}". An accelerator
 * names the key you press, so the code is the honest source. Anything not listed
 * falls back to the character, which covers the keys no accelerator uses.
 */
export function keyOfCode(code: string): string | null {
  const digit = /^Digit(\d)$/u.exec(code)?.[1]
  if (digit !== undefined) return digit
  const letter = /^Key([A-Z])$/u.exec(code)?.[1]
  if (letter !== undefined) return letter.toLowerCase()
  return PUNCTUATION[code] ?? null
}

const PUNCTUATION: Readonly<Record<string, string>> = {
  BracketLeft: "[",
  BracketRight: "]",
  Period: ".",
  Comma: ",",
  Equal: "=",
  Minus: "-",
  Backslash: "\\",
  Slash: "/",
  Quote: "'",
  Semicolon: ";",
  Backquote: "`",
  Tab: "tab",
  Space: "space",
  Enter: "enter",
}

/**
 * The keypress as a chord.
 *
 * The digit comes from `code`, not `key`: Option+1 on a Mac produces "¡" and
 * Shift+1 produces "!", so reading `key` would miss the Go menu's rows and mis-
 * read the shifted forms. `code` is the physical key, which is what an
 * accelerator names.
 */
export function chordOf(event: KeyLike, mac: boolean = IS_MAC): Chord {
  return {
    accelerator: mac ? event.metaKey : event.ctrlKey,
    control: event.ctrlKey,
    shift: event.shiftKey,
    alt: event.altKey,
    key: keyOfCode(event.code) ?? event.key.toLowerCase(),
  }
}

/**
 * The same, from a recorded key state — which has the code but no character,
 * because a recorder captures the key rather than what it typed.
 */
export function chordOfState(
  state: { code: string; ctrl: boolean; alt: boolean; shift: boolean; meta: boolean },
  mac: boolean,
): Chord | null {
  const key = keyOfCode(state.code)
  if (key === null) return null
  return {
    accelerator: mac ? state.meta : state.ctrl,
    control: state.ctrl,
    shift: state.shift,
    alt: state.alt,
    key,
  }
}

/**
 * Whether the native menu will handle this keypress, so the page must not.
 *
 * The one subtlety is that `CmdOrCtrl` and `Ctrl` are the *same* key off a Mac
 * and two different keys on one. So a chord is normalised against the host
 * before comparison: off a Mac, `Ctrl+Tab` wants the accelerator, and comparing
 * the two flags literally would mean it never matched anything. On a Mac they
 * stay apart, which is what lets ⌃Tab and ⌘T both exist.
 */
export function isMenuOwned(event: KeyLike): boolean {
  return commandForChord(chordOf(event, IS_MAC), IS_MAC) !== null
}

/**
 * The menu command a recorded combination would collide with, or null.
 *
 * What `hotkeys.ts`' recorder calls: a feature bound to ⇧⌘D would be shadowed
 * by Split Terminal Vertically and simply never fire, so the recorder refuses it
 * and says which command has it.
 */
export function menuCommandFor(
  state: { code: string; ctrl: boolean; alt: boolean; shift: boolean; meta: boolean },
  mac: boolean,
): string | null {
  const chord = chordOfState(state, mac)
  return chord === null ? null : commandForChord(chord, mac)
}

/**
 * `mac` is a parameter rather than the module's `IS_MAC` because the hotkey
 * recorder asks about *both* hosts — it renders the label for the platform it is
 * describing, not the one it is running on — and a lookup that silently used the
 * running host would call ⌘W reserved on Linux and ⌃W reserved on a Mac.
 */
function commandForChord(pressed: Chord, mac: boolean): string | null {
  for (const entry of MENU_COMMANDS) {
    const chord = parseAccelerator(entry.accelerator)
    if (chord === null) continue
    const wantsAccelerator = chord.accelerator || (!mac && chord.control)
    const wantsControl = mac && chord.control
    if (
      chord.key === pressed.key &&
      chord.shift === pressed.shift &&
      chord.alt === pressed.alt &&
      wantsAccelerator === pressed.accelerator &&
      (mac ? wantsControl === pressed.control : true)
    ) {
      return entry.command
    }
  }
  return null
}
