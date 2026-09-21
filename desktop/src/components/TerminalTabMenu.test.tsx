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
  }
  render(<TerminalTabMenu at={{ x: 10, y: 10 }} {...handlers} />)
  return handlers
}

describe("a terminal tab's right-click menu", () => {
  it("offers the Mac's four items, in its order", () => {
    menu()
    const labels = screen.getAllByRole("menuitem").map((one) => one.textContent)
    expect(labels).toEqual(["Rename…", "Split Vertically", "Split Horizontally", "Close Terminal"])
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

  it("offers no group items, because this app has no terminal groups", () => {
    // The Mac's menu has New Group…, New Terminal Here and Close Group.
    // Offering them with nothing behind them would be worse than their absence.
    menu()
    expect(screen.queryByRole("menuitem", { name: /Group/u })).toBeNull()
  })
})
