import { readFileSync } from "node:fs"
import { describe, expect, it } from "vitest"
import {
  chordOf,
  isMenuOwned,
  keyOfCode,
  MENU_COMMANDS,
  menuCommandFor,
  parseAccelerator,
} from "@/lib/menuKeys"
import { IS_MAC } from "@/lib/platform"

/** Every accelerator the Rust menu binds, with its label, read out of the table. */
function declared(): string[] {
  const source = readFileSync(new URL("../../src-tauri/src/menu.rs", import.meta.url), "utf8")
  const tabled = [
    ...source.matchAll(/label:\s*"([^"]+)",\s*accelerator:\s*Some\("([^"]+)"\)/gu),
  ].map((match) => `${match[2] ?? ""} = ${match[1] ?? ""}`)
  // The Go rows are generated rather than tabled — `format!("Alt+{}", …)` with
  // `format!("Sidebar Item {}", …)`.
  const generated = /format!\("Alt\+\{\}"/u.test(source)
    ? [1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map(
        (row) => `Alt+${String(row % 10)} = Sidebar Item ${String(row)}`,
      )
    : []
  return [...tabled, ...generated]
}

function listed(): string[] {
  return MENU_COMMANDS.map((entry) => `${entry.accelerator} = ${entry.command}`)
}

describe("which keys the menu owns", () => {
  it("lists exactly what the menu binds, by the same names", () => {
    // Two guards in one. An accelerator in Rust that is missing here would be
    // handled by *both* the menu and the page — Ctrl+W closing two tabs. And a
    // relabelled item would leave the hotkey recorder refusing a combination
    // under a name the menu no longer uses.
    expect(listed().toSorted()).toEqual(declared().toSorted())
  })

  it("finds the accelerators it is meant to be checking", () => {
    expect(declared().length).toBeGreaterThan(15)
    expect(declared()).toContain("CmdOrCtrl+Shift+D = Split Terminal Vertically")
    expect(declared()).toContain("Alt+0 = Sidebar Item 10")
  })
})

describe("naming the command a combination collides with", () => {
  it("names it, so the recorder can say which", () => {
    expect(menuCommandFor(held("KeyD", false, { shift: true }), false)).toBe(
      "Split Terminal Vertically",
    )
    expect(menuCommandFor(held("KeyD", true, { shift: true }), true)).toBe(
      "Split Terminal Vertically",
    )
    expect(
      menuCommandFor({ code: "Digit1", ctrl: false, meta: false, shift: false, alt: true }, false),
    ).toBe("Sidebar Item 1")
  })

  it("asks about the host it is given, not the one it is running on", () => {
    // The recorder describes both platforms, so ⌘W is reserved only when it is
    // asking about a Mac and Ctrl+W only when it is not.
    expect(menuCommandFor(held("KeyW", true), true)).toBe("Close Tab")
    expect(menuCommandFor(held("KeyW", true), false)).toBeNull()
    expect(menuCommandFor(held("KeyW", false), false)).toBe("Close Tab")
    expect(menuCommandFor(held("KeyW", false), true)).toBeNull()
  })

  it("says nothing for a combination the menu does not bind", () => {
    expect(menuCommandFor(held("KeyK", false), false)).toBeNull()
  })

  it("says nothing for a key it cannot name", () => {
    // A recorder captures modifier-only presses too, and a chord with no key
    // must not match the first entry in the table.
    expect(
      menuCommandFor(
        { code: "ShiftLeft", ctrl: false, meta: false, shift: true, alt: false },
        false,
      ),
    ).toBeNull()
  })
})

describe("naming a physical key", () => {
  it("reads digits, letters and the punctuation accelerators use", () => {
    expect(keyOfCode("Digit7")).toBe("7")
    expect(keyOfCode("KeyN")).toBe("n")
    expect(keyOfCode("BracketRight")).toBe("]")
    expect(keyOfCode("Tab")).toBe("tab")
  })

  it("refuses a key it has no name for", () => {
    expect(keyOfCode("F13")).toBeNull()
    expect(keyOfCode("ControlLeft")).toBeNull()
  })
})

describe("parsing an accelerator", () => {
  it("reads the modifiers and the key", () => {
    expect(parseAccelerator("CmdOrCtrl+Shift+N")).toEqual({
      accelerator: true,
      control: false,
      shift: true,
      alt: false,
      key: "n",
    })
    expect(parseAccelerator("Ctrl+Tab")?.control).toBe(true)
    expect(parseAccelerator("Ctrl+Tab")?.accelerator).toBe(false)
  })

  it("refuses a chord it cannot read rather than matching everything", () => {
    // Returning a partial chord would make `isMenuOwned` claim keystrokes the
    // menu never bound, which silently kills them in the page.
    expect(parseAccelerator("Super+K")).toBeNull()
    expect(parseAccelerator("Shift+")).toBeNull()
    expect(parseAccelerator("N")).toBeNull()
  })
})

/** A keypress with nothing held, overridden as each case needs. */
function press(over: Partial<Parameters<typeof chordOf>[0]>) {
  return {
    key: "a",
    code: "KeyA",
    ctrlKey: false,
    metaKey: false,
    shiftKey: false,
    altKey: false,
    ...over,
  }
}

/** A recorded chord with the given host's accelerator held. */
function held(code: string, mac: boolean, over: Record<string, boolean> = {}) {
  return { code, ctrl: !mac, meta: mac, shift: false, alt: false, ...over }
}

/** A keypress with *this host's* accelerator held — ⌘ on a Mac, Ctrl elsewhere. */
function accelerated(over: Record<string, unknown>) {
  return press({ ctrlKey: !IS_MAC, metaKey: IS_MAC, ...over })
}

describe("reading a keypress", () => {
  it("takes the digit from the physical key, not the character", () => {
    // Option+1 on a Mac is "¡" and Shift+1 is "!", so reading `key` would miss
    // the Go menu's rows entirely and mis-read the shifted forms.
    expect(chordOf(press({ key: "¡", code: "Digit1", altKey: true })).key).toBe("1")
    expect(chordOf(press({ key: "!", code: "Digit1", shiftKey: true })).key).toBe("1")
  })

  it("lowercases a letter, which Shift would otherwise capitalise", () => {
    expect(chordOf(press({ key: "N", code: "KeyN", shiftKey: true })).key).toBe("n")
  })

  it("keeps a punctuation key as its character", () => {
    expect(chordOf(press({ key: "]", code: "BracketRight" })).key).toBe("]")
    expect(chordOf(press({ key: "Tab", code: "Tab" })).key).toBe("tab")
  })
})

describe("deferring to the menu", () => {
  it("claims the terminal's shortcuts", () => {
    expect(isMenuOwned(accelerated({ key: "N", code: "KeyN", shiftKey: true }))).toBe(true)
    expect(isMenuOwned(accelerated({ key: "D", code: "KeyD", shiftKey: true }))).toBe(true)
    expect(isMenuOwned(accelerated({ key: "]", code: "BracketRight", shiftKey: true }))).toBe(true)
  })

  it("claims Close Tab and New Tab", () => {
    expect(isMenuOwned(accelerated({ key: "w", code: "KeyW" }))).toBe(true)
    expect(isMenuOwned(accelerated({ key: "t", code: "KeyT" }))).toBe(true)
  })

  it("leaves the page's own shortcuts alone", () => {
    // These are not in the menu, and the page must keep answering them:
    // Ctrl+K opens the palette, Ctrl+\\ splits the pane, Ctrl+1–9 switch tabs,
    // Ctrl+0 is Actual Size.
    expect(isMenuOwned(accelerated({ key: "k", code: "KeyK" }))).toBe(false)
    expect(isMenuOwned(accelerated({ key: "\\", code: "Backslash" }))).toBe(false)
    expect(isMenuOwned(accelerated({ key: "1", code: "Digit1" }))).toBe(false)
    expect(isMenuOwned(accelerated({ key: "0", code: "Digit0" }))).toBe(false)
  })

  it("tells the Go rows apart from the tab shortcuts", () => {
    // The collision the Alt move exists to avoid: Alt+1 is a sidebar row and
    // Ctrl+1 is a tab, and reading one as the other would open the wrong thing.
    expect(isMenuOwned(press({ key: "1", code: "Digit1", altKey: true }))).toBe(true)
    expect(isMenuOwned(accelerated({ key: "1", code: "Digit1" }))).toBe(false)
  })

  it("wants a modifier", () => {
    // A bare key must never be claimed: someone typing "n" into the rename
    // field would otherwise lose the keystroke to the menu.
    expect(isMenuOwned(press({ key: "n", code: "KeyN" }))).toBe(false)
  })

  it("does not confuse the shifted and unshifted forms", () => {
    // ⇧⌘0 is Actual Size; plain ⌘0 is not in the menu at all.
    expect(isMenuOwned(accelerated({ key: ")", code: "Digit0", shiftKey: true }))).toBe(true)
    expect(isMenuOwned(accelerated({ key: "0", code: "Digit0" }))).toBe(false)
  })
})
