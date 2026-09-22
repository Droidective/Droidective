import { fireEvent, render, screen } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"

import { OverridesPill, pillTitle } from "@/components/OverridesPill"
import type { ActiveOverride } from "@/lib/wire"

const proxy: ActiveOverride = { kind: "proxy", label: "HTTP Proxy", value: "10.0.0.2:8888", setAt: 0 }
const dark: ActiveOverride = { kind: "darkMode", label: "Dark Mode", value: "Dark", setAt: 0 }

const props = { busy: false, onReset: vi.fn(), onResetAll: vi.fn() }

describe("pillTitle", () => {
  it("names the one override", () => {
    expect(pillTitle([proxy])).toBe("HTTP Proxy")
  })

  it("names the first and counts the rest", () => {
    // A bare count says less in the same space: the name is what tells you
    // whether the pill is about the thing you are currently confused by.
    expect(pillTitle([proxy, dark])).toBe("HTTP Proxy +1")
  })

  it("says nothing for nothing", () => {
    expect(pillTitle([])).toBe("")
  })
})

describe("OverridesPill", () => {
  it("is absent when the device is in its own state", () => {
    // An untouched device carries no chrome for this.
    const { container } = render(<OverridesPill overrides={[]} {...props} />)
    expect(container.firstChild).toBeNull()
  })

  it("offers each override before it offers all of them", () => {
    // Clearing one is the common case — the reason you notice the pill is
    // usually one specific thing.
    render(<OverridesPill overrides={[proxy, dark]} {...props} />)
    fireEvent.click(screen.getByRole("button", { name: /HTTP Proxy/u }))

    expect(screen.getByText("HTTP Proxy: 10.0.0.2:8888 — reset")).toBeDefined()
    expect(screen.getByText("Dark Mode: Dark — reset")).toBeDefined()
    expect(screen.getByRole("button", { name: "Reset all overrides" })).toBeDefined()
  })

  it("clears the one that was picked, by kind", () => {
    const onReset = vi.fn()
    render(<OverridesPill overrides={[proxy, dark]} {...props} onReset={onReset} />)
    fireEvent.click(screen.getByRole("button", { name: /HTTP Proxy/u }))
    fireEvent.click(screen.getByText("Dark Mode: Dark — reset"))

    expect(onReset).toHaveBeenCalledWith("darkMode")
  })

  it("cannot be used twice while a reset is in flight", () => {
    render(<OverridesPill overrides={[proxy]} {...props} busy />)
    fireEvent.click(screen.getByRole("button", { name: /HTTP Proxy/u }))
    expect(
      screen.getByRole("button", { name: "Reset all overrides" }).hasAttribute("disabled"),
    ).toBe(true)
  })
})
