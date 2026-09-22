import { fireEvent, render, screen } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"

import { ResetOverridesRow } from "@/components/ResetOverridesRow"
import type { ActiveOverride } from "@/lib/wire"

const proxy: ActiveOverride = {
  kind: "proxy",
  label: "HTTP Proxy",
  value: "10.0.0.2:8888",
  setAt: 0,
}
const dark: ActiveOverride = { kind: "darkMode", label: "Dark Mode", value: "on", setAt: 0 }

describe("ResetOverridesRow", () => {
  it("names what it would put back", () => {
    // "Reset all overrides" alone does not say what it clears, and the read
    // that makes the row appear already knows.
    render(<ResetOverridesRow overrides={[proxy, dark]} busy={false} onReset={vi.fn()} />)
    expect(screen.getByText("HTTP Proxy, Dark Mode")).toBeDefined()
  })

  it("asks before clearing", () => {
    const onReset = vi.fn()
    render(<ResetOverridesRow overrides={[proxy]} busy={false} onReset={onReset} />)
    fireEvent.click(screen.getByRole("button", { name: "Reset all overrides" }))

    expect(screen.getByRole("alertdialog")).toBeDefined()
    expect(onReset).not.toHaveBeenCalled()
  })

  it("clears once the question is answered", () => {
    const onReset = vi.fn()
    render(<ResetOverridesRow overrides={[proxy]} busy={false} onReset={onReset} />)
    fireEvent.click(screen.getByRole("button", { name: "Reset all overrides" }))
    // Two now: the row's and the dialog's. The dialog's is the confirming one.
    const buttons = screen.getAllByRole("button", { name: "Reset all overrides" })
    fireEvent.click(buttons.at(-1) as HTMLElement)

    expect(onReset).toHaveBeenCalledTimes(1)
  })

  it("cannot be pressed while a reset is in flight", () => {
    render(<ResetOverridesRow overrides={[proxy]} busy onReset={vi.fn()} />)
    const button = screen.getByRole("button", { name: "Reset all overrides" })
    expect(button.hasAttribute("disabled")).toBe(true)
  })
})
