import { fireEvent, render, screen } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"

import { AppPill } from "@/components/AppPill"

const show = vi.fn()
vi.mock("@/hooks/useNotifications", () => ({ useNotifications: () => ({ show }) }))
vi.mock("@/lib/daemon", () => ({
  foregroundApp: vi.fn(() => Promise.resolve({ packageId: "com.example.front" })),
  asDaemonError: (thrown: unknown) => ({ message: String(thrown) }),
}))
vi.mock("@/components/InstalledAppsPicker", () => ({
  InstalledAppsPicker: () => <div data-testid="picker" />,
}))

const props = { serial: "S1", onSelect: vi.fn() }

describe("AppPill", () => {
  it("says what is chosen, and invites a choice when nothing is", () => {
    const { rerender } = render(<AppPill {...props} packageId={null} />)
    expect(screen.getByText("Choose app…")).toBeDefined()

    rerender(<AppPill {...props} packageId="com.example.app" />)
    expect(screen.getByText("com.example.app")).toBeDefined()
  })

  it("offers the two ways to answer that this app can actually offer", () => {
    // `Add manually / manage…` is the Mac's third, and it manages saved
    // bundles — a store this app does not keep, so it is absent rather than
    // present and inert.
    render(<AppPill {...props} packageId={null} />)
    fireEvent.click(screen.getByRole("button", { name: "Choose the target app" }))

    expect(screen.getByRole("button", { name: /Add from installed apps/u })).toBeDefined()
    expect(screen.getByRole("button", { name: /Use app on device screen/u })).toBeDefined()
    expect(screen.queryByRole("button", { name: /manage/u })).toBeNull()
  })

  it("greys both out with no device to ask", () => {
    render(<AppPill {...props} serial={null} packageId={null} />)
    fireEvent.click(screen.getByRole("button", { name: "Choose the target app" }))

    for (const name of [/Add from installed apps/u, /Use app on device screen/u]) {
      expect(screen.getByRole("button", { name }).hasAttribute("disabled")).toBe(true)
    }
  })

  it("only offers to clear once there is something to clear", () => {
    const { rerender } = render(<AppPill {...props} packageId={null} />)
    fireEvent.click(screen.getByRole("button", { name: "Choose the target app" }))
    expect(screen.queryByText("Clear the choice")).toBeNull()

    rerender(<AppPill {...props} packageId="com.example.app" />)
    expect(screen.getByText("Clear the choice")).toBeDefined()
  })

  it("takes the foreground app when asked", async () => {
    const onSelect = vi.fn()
    render(<AppPill {...props} onSelect={onSelect} packageId={null} />)
    fireEvent.click(screen.getByRole("button", { name: "Choose the target app" }))
    fireEvent.click(screen.getByRole("button", { name: /Use app on device screen/u }))

    await vi.waitFor(() => {
      expect(onSelect).toHaveBeenCalledWith("com.example.front")
    })
  })

  it("says so when nothing worth naming is in front, rather than failing", async () => {
    // The launcher is in front more often than not, and that is an answer.
    const { foregroundApp } = await import("@/lib/daemon")
    // Absent, not null: the daemon omits the key when nothing is in front.
    vi.mocked(foregroundApp).mockResolvedValueOnce({})
    show.mockClear()

    render(<AppPill {...props} packageId={null} />)
    fireEvent.click(screen.getByRole("button", { name: "Choose the target app" }))
    fireEvent.click(screen.getByRole("button", { name: /Use app on device screen/u }))

    await vi.waitFor(() => {
      expect(show).toHaveBeenCalledWith({ message: "Nothing in front to pick.", ok: false })
    })
  })
})
