import { describe, expect, it } from "vitest"
import {
  afterButtonPress,
  afterModeChange,
  afterToggle,
  isPeeked,
  occupiesLayout,
  pinnedSidebar,
  type SidebarMode,
} from "@/lib/sidebarMode"

const pinned = pinnedSidebar()
const autoHiding: SidebarMode = { autoHide: true, visible: true, overlayShown: false }

describe("afterModeChange", () => {
  it("leaves the auto-hiding sidebar at rest", () => {
    // Hidden until a hover or ⌘B — that is what auto-hide means.
    expect(afterModeChange(pinned, true)).toEqual({
      autoHide: true,
      visible: true,
      overlayShown: false,
    })
  })

  it("always restores the pinned sidebar on the way back", () => {
    // Even from a state where the pinned one had been evicted, so no direction
    // can strand someone with the sidebar nowhere.
    const evicted: SidebarMode = { autoHide: true, visible: false, overlayShown: true }
    expect(afterModeChange(evicted, false)).toEqual(pinned)
  })
})

describe("afterButtonPress", () => {
  it("flips the mode", () => {
    expect(afterButtonPress(pinned).autoHide).toBe(true)
    expect(afterButtonPress(autoHiding).autoHide).toBe(false)
  })

  it("is never a dead click when the pinned sidebar has been evicted", () => {
    // A split-resize took it away; the first press has to bring it back rather
    // than silently switching a mode nobody could see.
    const evicted: SidebarMode = { autoHide: false, visible: false, overlayShown: false }
    expect(afterButtonPress(evicted)).toEqual(pinned)
  })
})

describe("afterToggle", () => {
  it("peeks in auto-hide mode without changing the mode", () => {
    const peeked = afterToggle(autoHiding)
    expect(peeked).toEqual({ autoHide: true, visible: true, overlayShown: true })
    expect(afterToggle(peeked).overlayShown).toBe(false)
  })

  it("takes the pinned sidebar away and brings it back in fixed mode", () => {
    expect(afterToggle(pinned).visible).toBe(false)
    expect(afterToggle(afterToggle(pinned))).toEqual(pinned)
  })
})

describe("occupiesLayout and isPeeked", () => {
  it("separates being in the layout from being drawn over it", () => {
    expect(occupiesLayout(pinned)).toBe(true)
    expect(isPeeked(pinned)).toBe(false)

    expect(occupiesLayout(autoHiding)).toBe(false)
    expect(isPeeked(autoHiding)).toBe(false)

    const peeked = afterToggle(autoHiding)
    expect(occupiesLayout(peeked)).toBe(false)
    expect(isPeeked(peeked)).toBe(true)
  })
})
