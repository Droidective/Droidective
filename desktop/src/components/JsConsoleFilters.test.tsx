import { fireEvent, render, screen } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"
import type { Mock } from "vitest"

import { Filters } from "@/components/JsConsoleFilters"
import { allHidden, type Level } from "@/lib/console-feed"

const counts = { verbose: 2, info: 7, warning: 1, error: 3 }

/** Nothing picked: the selection controls stay out of the bar. */
const noSelection = {
  count: 0,
  has: () => false,
  onPointerDown: vi.fn(),
  onPointerEnter: vi.fn(),
  dragging: false,
  copy: vi.fn(),
  copyAsJson: vi.fn(),
  clear: vi.fn(),
}

/** The level set the picker handed back, as a sorted array. */
function handedBack(onHidden: Mock): string[] {
  const first = onHidden.mock.calls[0]
  if (first === undefined) throw new Error("the picker reported nothing")
  return [...(first[0] as ReadonlySet<Level>)].toSorted()
}

function filters(
  over: { hidden?: ReadonlySet<Level>; enabled?: boolean; picked?: number } = {},
) {
  const onHidden = vi.fn()
  const onFind = vi.fn()
  const copy = vi.fn()
  const copyAsJson = vi.fn()
  const clear = vi.fn()
  const saveAsJson = vi.fn()
  const copyToClipboard = vi.fn()
  render(
    <Filters
      hidden={over.hidden ?? new Set()}
      counts={counts}
      query=""
      onQuery={vi.fn()}
      onHidden={onHidden}
      onClear={vi.fn()}
      onFind={onFind}
      selection={{ ...noSelection, count: over.picked ?? 0, copy, copyAsJson, clear }}
      exporting={{ enabled: over.enabled ?? true, saveAsJson, copyToClipboard }}
    />,
  )
  return { onHidden, onFind, saveAsJson, copyToClipboard, copy, copyAsJson, clear }
}

describe("the level picker", () => {
  it("reads All levels while nothing is hidden", () => {
    filters()
    expect(screen.getByRole("button", { name: /All levels/u })).toBeTruthy()
  })

  it("counts what is still shown once something is hidden", () => {
    filters({ hidden: new Set<Level>(["verbose"]) })
    expect(screen.getByRole("button", { name: /Levels 3\/4/u })).toBeTruthy()
  })

  it("keeps the levels behind the pill until it is opened", () => {
    // The Mac's shape: one pill, not a chip per level — which is the design it
    // replaced, and what this used to be.
    filters()
    expect(screen.queryByText("Show levels")).toBeNull()
  })

  it("unticks a level rather than selecting only it", () => {
    const { onHidden } = filters()
    fireEvent.click(screen.getByRole("button", { name: /All levels/u }))
    fireEvent.click(screen.getByRole("checkbox", { name: /verbose/u }))
    expect(handedBack(onHidden)).toEqual(["verbose"])
  })

  it("Show All clears everything hidden", () => {
    const { onHidden } = filters({ hidden: allHidden() })
    fireEvent.click(screen.getByRole("button", { name: /Levels 0\/4/u }))
    fireEvent.click(screen.getByRole("button", { name: "Show All" }))
    expect(handedBack(onHidden)).toEqual([])
  })

  it("Hide All hides every level", () => {
    const { onHidden } = filters()
    fireEvent.click(screen.getByRole("button", { name: /All levels/u }))
    fireEvent.click(screen.getByRole("button", { name: "Hide All" }))
    expect(handedBack(onHidden)).toEqual(["error", "info", "verbose", "warning"])
  })

  it("disables each end at its own extreme", () => {
    filters()
    fireEvent.click(screen.getByRole("button", { name: /All levels/u }))
    // Nothing hidden: Show All would do nothing, Hide All would do something.
    expect(screen.getByRole("button", { name: "Show All" }).hasAttribute("disabled")).toBe(true)
    expect(screen.getByRole("button", { name: "Hide All" }).hasAttribute("disabled")).toBe(false)
  })
})

describe("the export menu", () => {
  it("offers the Mac's two items", () => {
    filters()
    fireEvent.click(screen.getByRole("button", { name: "Export" }))
    expect(screen.getByRole("menuitem", { name: "Save as JSON…" })).toBeTruthy()
    expect(screen.getByRole("menuitem", { name: "Copy to Clipboard" })).toBeTruthy()
  })

  it("is disabled with nothing on screen to export", () => {
    filters({ enabled: false })
    expect(screen.getByRole("button", { name: "Export" }).hasAttribute("disabled")).toBe(true)
  })

  it("closes after a pick, so the menu is not left hanging over the feed", () => {
    const { saveAsJson } = filters()
    fireEvent.click(screen.getByRole("button", { name: "Export" }))
    fireEvent.click(screen.getByRole("menuitem", { name: "Save as JSON…" }))
    expect(saveAsJson).toHaveBeenCalledOnce()
    expect(screen.queryByRole("menuitem", { name: "Save as JSON…" })).toBeNull()
  })
})

describe("the filter bar's wording", () => {
  it("uses the Mac's placeholder and its clear tooltip", () => {
    filters()
    expect(screen.getByPlaceholderText("Filter")).toBeTruthy()
    expect(screen.getByTitle("Clear the console")).toBeTruthy()
  })

  it("carries the Mac's tooltip on the level pill", () => {
    filters()
    expect(screen.getByTitle("Choose which log levels to show")).toBeTruthy()
  })
})

describe("the selection controls", () => {
  it("stay out of the bar while nothing is picked", () => {
    // The Mac renders them the same way: a Copy that is disabled nine times
    // out of ten is noise.
    filters()
    expect(screen.queryByText(/selected/u)).toBeNull()
  })

  it("say how many are picked", () => {
    filters({ picked: 3 })
    expect(screen.getByText("3 selected")).toBeTruthy()
  })

  it("offer the Mac's three actions behind the button", () => {
    filters({ picked: 2 })
    fireEvent.click(screen.getByRole("button", { name: "Selection actions" }))
    expect(screen.getByRole("menuitem", { name: "Copy" })).toBeTruthy()
    expect(screen.getByRole("menuitem", { name: "Copy as JSON" })).toBeTruthy()
    expect(screen.getByRole("menuitem", { name: "Deselect" })).toBeTruthy()
  })

  it("runs the action and closes", () => {
    const { copyAsJson } = filters({ picked: 2 })
    fireEvent.click(screen.getByRole("button", { name: "Selection actions" }))
    fireEvent.click(screen.getByRole("menuitem", { name: "Copy as JSON" }))
    expect(copyAsJson).toHaveBeenCalledOnce()
    expect(screen.queryByRole("menuitem", { name: "Copy as JSON" })).toBeNull()
  })

  it("writes the gestures down, since nothing else does", () => {
    filters({ picked: 1 })
    expect(
      screen.getByRole("button", { name: "Selection actions" }).getAttribute("title"),
    ).toBe(
      "Copy the selected logs (Ctrl+C) — Ctrl-click to pick rows, Shift-click or drag for a range",
    )
  })
})
