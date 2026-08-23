import { describe, expect, it } from "vitest"
import {
  formatHotkey,
  holderOf,
  hotkeyEffect,
  hotkeyFromEvent,
  isModifierCode,
  keyLabel,
  modifierPreview,
  reservedCommand,
  resolveHotkey,
  sameHotkey,
  withHotkey,
  type Hotkey,
  type KeyState,
} from "@/lib/hotkeys"

/** A `keydown` as the recorder sees it, with nothing held unless asked for. */
function press(code: string, held: Partial<KeyState> = {}): KeyState {
  return { code, ctrl: false, alt: false, shift: false, meta: false, ...held }
}

function hotkey(code: string, held: Partial<Hotkey> = {}): Hotkey {
  return { code, ctrl: false, alt: false, shift: false, meta: false, ...held }
}

describe("hotkeyFromEvent", () => {
  it("captures the whole combination", () => {
    expect(hotkeyFromEvent(press("KeyL", { ctrl: true, shift: true }))).toEqual(
      hotkey("KeyL", { ctrl: true, shift: true }),
    )
  })

  it("refuses a modifier on its own — no key has landed yet", () => {
    expect(hotkeyFromEvent(press("ControlLeft", { ctrl: true }))).toBeNull()
    expect(hotkeyFromEvent(press("MetaRight", { meta: true }))).toBeNull()
    expect(hotkeyFromEvent(press("ShiftLeft", { shift: true }))).toBeNull()
    expect(hotkeyFromEvent(press("AltLeft", { alt: true }))).toBeNull()
  })

  it("refuses Caps Lock, which nobody can release", () => {
    expect(hotkeyFromEvent(press("CapsLock", { ctrl: true }))).toBeNull()
  })

  it("refuses a bare key, and Shift alone", () => {
    // Otherwise "L" would fire Logcat every time it was typed into a filter.
    expect(hotkeyFromEvent(press("KeyL"))).toBeNull()
    expect(hotkeyFromEvent(press("KeyL", { shift: true }))).toBeNull()
  })

  it("accepts any of Ctrl, Alt or the platform key", () => {
    expect(hotkeyFromEvent(press("KeyL", { ctrl: true }))).not.toBeNull()
    expect(hotkeyFromEvent(press("KeyL", { alt: true }))).not.toBeNull()
    expect(hotkeyFromEvent(press("KeyL", { meta: true }))).not.toBeNull()
  })

  it("refuses an event with no code at all", () => {
    expect(hotkeyFromEvent(press("", { ctrl: true }))).toBeNull()
  })
})

describe("isModifierCode", () => {
  it("does not mistake a key that merely starts like one", () => {
    // "Comma" is not "Control"; "Slash" is not "Shift".
    expect(isModifierCode("Comma")).toBe(false)
    expect(isModifierCode("Slash")).toBe(false)
    expect(isModifierCode("KeyM")).toBe(false)
  })
})

describe("keyLabel", () => {
  it("reads a physical code as the key it is", () => {
    expect(keyLabel("KeyL")).toBe("L")
    expect(keyLabel("Digit7")).toBe("7")
    expect(keyLabel("Numpad3")).toBe("Num 3")
    expect(keyLabel("Backslash")).toBe("\\")
    expect(keyLabel("ArrowUp")).toBe("↑")
    expect(keyLabel("Space")).toBe("Space")
  })

  it("falls through to the code rather than rendering nothing", () => {
    expect(keyLabel("F13")).toBe("F13")
    expect(keyLabel("IntlBackslash")).toBe("IntlBackslash")
  })
})

describe("formatHotkey", () => {
  it("prints the Mac's symbols in the Mac's order", () => {
    // ⌃⌥⇧⌘, which is what HotkeyRecording.modifierSymbols emits.
    const all = hotkey("KeyY", { ctrl: true, alt: true, shift: true, meta: true })
    expect(formatHotkey(all, true)).toBe("⌃⌥⇧⌘Y")
    expect(formatHotkey(hotkey("KeyY", { ctrl: true, meta: true }), true)).toBe("⌃⌘Y")
  })

  it("spells them out on Windows and Linux", () => {
    expect(formatHotkey(hotkey("KeyY", { ctrl: true, alt: true }), false)).toBe("Ctrl+Alt+Y")
    expect(formatHotkey(hotkey("KeyY", { meta: true }), false)).toBe("Super+Y")
  })
})

describe("modifierPreview", () => {
  it("shows what is held, and nothing at all when nothing is", () => {
    expect(modifierPreview({ ctrl: true, alt: false, shift: false, meta: true }, true)).toBe("⌃⌘…")
    expect(modifierPreview({ ctrl: true, alt: false, shift: false, meta: false }, false)).toBe(
      "Ctrl+…",
    )
    expect(modifierPreview({ ctrl: false, alt: false, shift: false, meta: false }, true)).toBe("")
  })
})

describe("sameHotkey", () => {
  it("separates combinations that differ only by a modifier", () => {
    expect(sameHotkey(hotkey("KeyL", { ctrl: true }), hotkey("KeyL", { ctrl: true }))).toBe(true)
    expect(
      sameHotkey(hotkey("KeyL", { ctrl: true }), hotkey("KeyL", { ctrl: true, shift: true })),
    ).toBe(false)
    expect(sameHotkey(hotkey("KeyL", { ctrl: true }), hotkey("KeyL", { meta: true }))).toBe(false)
  })
})

describe("resolveHotkey", () => {
  const bindings = {
    logcat: hotkey("KeyL", { ctrl: true, alt: true }),
    apps: hotkey("KeyA", { ctrl: true, alt: true }),
  }

  it("finds the feature a press is bound to", () => {
    expect(resolveHotkey(bindings, press("KeyL", { ctrl: true, alt: true }), false)).toBe("logcat")
  })

  it("answers nothing for an unbound press", () => {
    expect(resolveHotkey(bindings, press("KeyZ", { ctrl: true, alt: true }), false)).toBeNull()
    // The same physical key without the modifiers is ordinary typing.
    expect(resolveHotkey(bindings, press("KeyL"), false)).toBeNull()
    expect(resolveHotkey(bindings, press("KeyL", { ctrl: true }), false)).toBeNull()
  })

  it("never hands over one of the shell's own keys", () => {
    // Not reachable through the recorder, which refuses them — but a binding
    // some other build wrote must not shadow Close Tab either.
    const stale = { apps: hotkey("KeyW", { ctrl: true }) }
    expect(resolveHotkey(stale, press("KeyW", { ctrl: true }), false)).toBeNull()
    // The same feature on a combination the shell does not own still fires.
    expect(resolveHotkey(stale, press("KeyW", { ctrl: true, alt: true }), false)).toBeNull()
    const fine = { apps: hotkey("KeyW", { ctrl: true, alt: true }) }
    expect(resolveHotkey(fine, press("KeyW", { ctrl: true, alt: true }), false)).toBe("apps")
  })
})

describe("withHotkey", () => {
  const bindings = { logcat: hotkey("KeyL", { ctrl: true, alt: true }) }

  it("sets one", () => {
    const next = withHotkey(bindings, "apps", hotkey("KeyA", { ctrl: true, alt: true }))
    expect(next["apps"]).toEqual(hotkey("KeyA", { ctrl: true, alt: true }))
    expect(next["logcat"]).toEqual(bindings.logcat)
  })

  it("clears one, leaving the rest alone", () => {
    const two = withHotkey(bindings, "apps", hotkey("KeyA", { ctrl: true, alt: true }))
    expect(Object.keys(withHotkey(two, "apps", null))).toEqual(["logcat"])
  })

  it("takes a combination off whatever held it before", () => {
    // Two features on one shortcut means one of them silently never fires.
    const moved = withHotkey(bindings, "apps", hotkey("KeyL", { ctrl: true, alt: true }))
    expect(Object.keys(moved)).toEqual(["apps"])
  })

  it("does not touch a feature bound to a different combination", () => {
    const next = withHotkey(bindings, "apps", hotkey("KeyL", { ctrl: true }))
    expect(Object.keys(next).toSorted()).toEqual(["apps", "logcat"])
  })
})

describe("holderOf", () => {
  const bindings = { logcat: hotkey("KeyL", { ctrl: true, alt: true }) }

  it("names the feature already using a combination", () => {
    expect(holderOf(bindings, hotkey("KeyL", { ctrl: true, alt: true }), "apps")).toBe("logcat")
  })

  it("does not report a feature against itself", () => {
    expect(holderOf(bindings, hotkey("KeyL", { ctrl: true, alt: true }), "logcat")).toBeNull()
  })
})

describe("reservedCommand", () => {
  it("refuses the shell's own keys, which a feature could never win", () => {
    expect(reservedCommand(hotkey("KeyW", { meta: true }), true)).toBe("Close Tab")
    expect(reservedCommand(hotkey("KeyW", { ctrl: true }), false)).toBe("Close Tab")
    expect(reservedCommand(hotkey("Backslash", { ctrl: true }), false)).toBe("Split Pane")
    // Named the way the menu labels it, so one key never has two names.
    expect(reservedCommand(hotkey("Comma", { ctrl: true }), false)).toBe("Settings…")
    expect(reservedCommand(hotkey("Digit3", { ctrl: true }), false)).toBe("Show Tab 3")
    expect(reservedCommand(hotkey("KeyB", { ctrl: true }), false)).toBe("Toggle Sidebar")
    expect(reservedCommand(hotkey("Equal", { ctrl: true }), false)).toBe("Increase Font Size")
    expect(reservedCommand(hotkey("Minus", { ctrl: true }), false)).toBe("Decrease Font Size")
  })

  it("reserves zero for Actual Size, not for a tab", () => {
    // There is no tab 0; ⌘0 is the zoom reset, as it is in every browser.
    expect(reservedCommand(hotkey("Digit0", { ctrl: true }), false)).toBe("Actual Size")
  })

  it("still reserves it when Ctrl is also held on a Mac", () => {
    // `hasModifier` only asks about ⌘ there, so ⌃⌘W closes the tab too.
    expect(reservedCommand(hotkey("KeyW", { ctrl: true, meta: true }), true)).toBe("Close Tab")
  })

  it("frees the key again once a second modifier is added", () => {
    // `useShellShortcuts` returns early on Alt and compares unshifted keys.
    expect(reservedCommand(hotkey("KeyW", { ctrl: true, alt: true }), false)).toBeNull()
    expect(reservedCommand(hotkey("Digit3", { ctrl: true, shift: true }), false)).toBeNull()
  })

  it("also refuses what the window menu binds, Shift and Alt forms included", () => {
    // The hole this closes: the page's shortcuts all drop a Shift chord, but the
    // *menu* binds several, and a feature bound to one would be shadowed by the
    // platform and simply never fire.
    expect(reservedCommand(hotkey("KeyW", { ctrl: true, shift: true }), false)).toBe(
      "Close Terminal",
    )
    expect(reservedCommand(hotkey("KeyD", { ctrl: true, shift: true }), false)).toBe(
      "Split Terminal Vertically",
    )
    expect(reservedCommand(hotkey("Tab", { ctrl: true }), false)).toBe("Next Tab")
    expect(reservedCommand(hotkey("Digit1", { alt: true }), false)).toBe("Sidebar Item 1")
  })

  it("does not reserve the other platform's accelerator", () => {
    // ⌃W is nobody's on a Mac, and ⌘W is nobody's on Windows and Linux. This is
    // what caught the menu lookup reading the *running* host instead of the one
    // it was asked about.
    expect(reservedCommand(hotkey("KeyW", { ctrl: true }), true)).toBeNull()
    expect(reservedCommand(hotkey("KeyW", { meta: true }), false)).toBeNull()
  })
})

describe("hotkeyEffect", () => {
  it("runs an instant action and opens everything else", () => {
    expect(hotkeyEffect("instantAction")).toBe("run")
    expect(hotkeyEffect("formAction")).toBe("open")
    expect(hotkeyEffect("view")).toBe("open")
    expect(hotkeyEffect("system")).toBe("open")
    // The Mac flips a toggle from tracked override state this app does not
    // keep, so it opens rather than guessing a direction.
    expect(hotkeyEffect("toggleAction")).toBe("open")
  })
})
