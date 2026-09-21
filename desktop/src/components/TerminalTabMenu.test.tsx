import { fireEvent, render, screen } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"

import { TerminalTabMenu } from "@/components/TerminalTabMenu"

function menu() {
  const handlers = {
    onRename: vi.fn(),
    onSplitVertically: vi.fn(),
    onSplitHorizontally: vi.fn(),
    onClose: vi.fn(),
    onDismiss: vi.fn(),
    onNewGroup: vi.fn(),
    onNewTerminalHere: null,
    onCloseGroup: null,
  }
  render(<TerminalTabMenu at={{ x: 10, y: 10 }} {...handlers} />)
  return handlers
}

describe("a terminal tab's right-click menu", () => {
  it("offers the Mac's items, in its order", () => {
    menu()
    const labels = screen.getAllByRole("menuitem").map((one) => one.textContent)
    expect(labels).toEqual([
      "Rename…",
      "New Group…",
      "Split Vertically",
      "Split Horizontally",
      "Close Terminal",
    ])
  })

  it("splits the way each item says", () => {
    // The two are a keystroke apart on the menu bar and easy to wire crossed.
    const { onSplitVertically, onSplitHorizontally } = menu()
    fireEvent.click(screen.getByRole("menuitem", { name: "Split Vertically" }))
    expect(onSplitVertically).toHaveBeenCalledOnce()
    expect(onSplitHorizontally).not.toHaveBeenCalled()
  })

  it("closes on Escape", () => {
    const { onDismiss } = menu()
    fireEvent.keyDown(document, { key: "Escape" })
    expect(onDismiss).toHaveBeenCalled()
  })

  it("closes when a click lands elsewhere, before that click opens another", () => {
    // Captured, so a click on the tab underneath dismisses this rather than
    // opening a second menu over it.
    const { onDismiss } = menu()
    fireEvent.mouseDown(document.body)
    expect(onDismiss).toHaveBeenCalled()
  })

  it("hides the two group verbs on a tab that is in no group", () => {
    // Close Group on a loose tab would be a verb with nothing to act on; the
    // Mac's menu is arranged the same way.
    menu()
    expect(screen.queryByRole("menuitem", { name: "New Terminal Here" })).toBeNull()
    expect(screen.queryByRole("menuitem", { name: "Close Group" })).toBeNull()
  })

  it("offers them on a tab that is in one", () => {
    const handlers = {
      onRename: vi.fn(),
      onSplitVertically: vi.fn(),
      onSplitHorizontally: vi.fn(),
      onClose: vi.fn(),
      onDismiss: vi.fn(),
      onNewGroup: vi.fn(),
      onNewTerminalHere: vi.fn(),
      onCloseGroup: vi.fn(),
    }
    render(<TerminalTabMenu at={{ x: 10, y: 10 }} {...handlers} />)
    expect(screen.getByRole("menuitem", { name: "New Terminal Here" })).toBeTruthy()
    expect(screen.getByRole("menuitem", { name: "Close Group" })).toBeTruthy()
  })
})
