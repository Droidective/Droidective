import { describe, expect, it } from "vitest"

import { emptyLayout, HOME_TAB, type LayoutState } from "@/lib/layout"
import {
  currentWindowLabel,
  emptyWindowLayout,
  forgetWindowLayout,
  loadWindowLayout,
  requestedSerial,
  saveWindowLayout,
  windowKey,
} from "@/lib/window-layout"

function storage(seed: Record<string, string> = {}) {
  const map = new Map(Object.entries(seed))
  return {
    getItem: (key: string) => map.get(key) ?? null,
    setItem: (key: string, value: string) => {
      map.set(key, value)
    },
    removeItem: (key: string) => {
      map.delete(key)
    },
    dump: () => Object.fromEntries(map),
  }
}

function shared(over: Partial<LayoutState> = {}): LayoutState {
  return { ...emptyLayout(), ...over }
}

describe("currentWindowLabel", () => {
  /**
   * Read from the query string rather than Tauri's API for the reason
   * `main.tsx` gives about the panel: the label is reachable asynchronously,
   * and a window painting as the wrong workspace for a frame would flash
   * another window's tabs.
   */
  it("is main when nothing says otherwise", () => {
    expect(currentWindowLabel("")).toBe("main")
    expect(currentWindowLabel("?serial=emulator-5554")).toBe("main")
    expect(currentWindowLabel("?w=")).toBe("main")
  })

  it("takes the label the opener put there", () => {
    expect(currentWindowLabel("?w=w1")).toBe("w1")
    expect(currentWindowLabel("?w=w2&serial=A")).toBe("w2")
  })
})

describe("requestedSerial", () => {
  it("reads a device the opener asked for, decoded", () => {
    expect(requestedSerial("?serial=emulator-5554")).toBe("emulator-5554")
    // A wireless serial carries a colon, which is percent-encoded on the way.
    expect(requestedSerial("?serial=192.168.1.10%3A5555")).toBe("192.168.1.10:5555")
  })

  it("is null when no device was named", () => {
    expect(requestedSerial("")).toBeNull()
    expect(requestedSerial("?w=w1")).toBeNull()
    expect(requestedSerial("?serial=")).toBeNull()
  })
})

describe("loadWindowLayout", () => {
  /**
   * The pre-multi-window layout kept one workspace on the shared blob. It is
   * adopted into the *first* window only — `adoptWindows` on the Mac — so an
   * existing install opens on the tabs it was closed with.
   */
  it("folds the old single-window layout into the first window", () => {
    const previous = shared({
      panes: [{ tabs: [HOME_TAB, "logcat"], activeTab: "logcat" }],
      focusedPane: 0,
      splitFraction: 0.4,
    })
    const layout = loadWindowLayout(storage(), "main", previous)

    expect(layout.panes[0]?.tabs).toEqual([HOME_TAB, "logcat"])
    expect(layout.splitFraction).toBe(0.4)
  })

  /** A second window must not inherit the first's tabs. */
  it("gives a new window a bare Home", () => {
    const previous = shared({ panes: [{ tabs: [HOME_TAB, "logcat"], activeTab: "logcat" }] })
    expect(loadWindowLayout(storage(), "w1", previous)).toEqual(emptyWindowLayout())
  })

  it("prefers a window's own saved entry over the shared one", () => {
    const store = storage({
      [windowKey("main")]: JSON.stringify({
        serial: "emulator-5554",
        panes: [{ tabs: ["apps"], activeTab: "apps" }],
        focusedPane: 0,
        splitFraction: 0.6,
      }),
    })
    const layout = loadWindowLayout(store, "main", shared({ panes: [{ tabs: ["logcat"], activeTab: null }] }))

    expect(layout.serial).toBe("emulator-5554")
    expect(layout.panes[0]?.tabs).toEqual(["apps"])
    expect(layout.splitFraction).toBe(0.6)
  })

  it("survives a corrupt entry rather than losing the window", () => {
    const store = storage({ [windowKey("w1")]: "{not json" })
    expect(loadWindowLayout(store, "w1", shared())).toEqual(emptyWindowLayout())
  })

  /** A pane with no tabs cannot be drawn, so it is dropped rather than shown. */
  it("drops a pane with no tabs, and falls back when none survive", () => {
    const store = storage({
      [windowKey("w1")]: JSON.stringify({
        panes: [{ tabs: [], activeTab: null }, { tabs: ["logcat"], activeTab: "logcat" }],
      }),
    })
    expect(loadWindowLayout(store, "w1", shared()).panes).toEqual([
      { tabs: ["logcat"], activeTab: "logcat" },
    ])

    const empty = storage({ [windowKey("w2")]: JSON.stringify({ panes: [] }) })
    expect(loadWindowLayout(empty, "w2", shared()).panes).toEqual(emptyWindowLayout().panes)
  })
})

describe("saveWindowLayout and forgetWindowLayout", () => {
  /**
   * Separate keys are the whole point: two webviews sharing one blob lose
   * whichever write landed first, and no care inside a merge fixes that.
   */
  it("writes each window to its own key", () => {
    const store = storage()
    saveWindowLayout(store, "main", { ...emptyWindowLayout(), serial: "A" })
    saveWindowLayout(store, "w1", { ...emptyWindowLayout(), serial: "B" })

    expect(loadWindowLayout(store, "main", shared()).serial).toBe("A")
    expect(loadWindowLayout(store, "w1", shared()).serial).toBe("B")
  })

  /**
   * Without this every window ever opened leaves an entry behind, and `w1`'s
   * tabs come back the next time a window is given that label.
   */
  it("removes a closed window's entry", () => {
    const store = storage()
    saveWindowLayout(store, "w1", { ...emptyWindowLayout(), serial: "B" })
    forgetWindowLayout(store, "w1")

    expect(Object.keys(store.dump())).not.toContain(windowKey("w1"))
  })

  it("swallows a storage that refuses, rather than throwing into the render", () => {
    const refusing = {
      setItem: () => {
        throw new Error("quota")
      },
      removeItem: () => {
        throw new Error("quota")
      },
    }
    expect(() => {
      saveWindowLayout(refusing, "w1", emptyWindowLayout())
    }).not.toThrow()
    expect(() => {
      forgetWindowLayout(refusing, "w1")
    }).not.toThrow()
  })
})
