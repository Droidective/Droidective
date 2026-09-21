import { fireEvent, render, screen } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"

import { JsConsoleFindBar } from "@/components/JsConsoleFindBar"

function bar(over: { count?: string; hasMatches?: boolean } = {}) {
  const onNext = vi.fn()
  const onPrev = vi.fn()
  const onClose = vi.fn()
  const onQuery = vi.fn()
  render(
    <JsConsoleFindBar
      query="user"
      onQuery={onQuery}
      count={over.count ?? "1 of 2"}
      hasMatches={over.hasMatches ?? true}
      onNext={onNext}
      onPrev={onPrev}
      onClose={onClose}
    />,
  )
  return { onNext, onPrev, onClose, onQuery }
}

describe("the find bar", () => {
  it("carries the Mac's placeholder", () => {
    bar()
    expect(screen.getByPlaceholderText("Find in console")).toBeTruthy()
  })

  it("takes focus as it opens, so the shortcut lands somewhere useful", () => {
    bar()
    expect(document.activeElement).toBe(screen.getByPlaceholderText("Find in console"))
  })

  it("shows the counter", () => {
    bar({ count: "2 of 7" })
    expect(screen.getByText("2 of 7")).toBeTruthy()
  })

  it("walks forward on Enter and back on Shift+Enter", () => {
    const { onNext, onPrev } = bar()
    const field = screen.getByPlaceholderText("Find in console")
    fireEvent.keyDown(field, { key: "Enter" })
    expect(onNext).toHaveBeenCalledOnce()
    fireEvent.keyDown(field, { key: "Enter", shiftKey: true })
    expect(onPrev).toHaveBeenCalledOnce()
  })

  it("closes on Escape", () => {
    const { onClose } = bar()
    fireEvent.keyDown(screen.getByPlaceholderText("Find in console"), { key: "Escape" })
    expect(onClose).toHaveBeenCalledOnce()
  })

  it("disables both arrows when nothing matched", () => {
    // Stepping through an empty set would move the counter and nothing else.
    bar({ hasMatches: false, count: "No matches" })
    expect(screen.getByLabelText("Next match").hasAttribute("disabled")).toBe(true)
    expect(screen.getByLabelText("Previous match").hasAttribute("disabled")).toBe(true)
  })
})
