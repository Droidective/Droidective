import { fireEvent, render, screen } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"

import { AppLifecycleActions } from "@/components/AppLifecycleActions"
import type { AppSummary } from "@/lib/wire"

vi.mock("@/lib/daemon", () => ({
  appLifecycle: vi.fn(() => Promise.resolve({ ok: true, message: "Done." })),
  asDaemonError: (thrown: unknown) => ({ message: String(thrown) }),
}))

vi.mock("@/hooks/useNotifications", () => ({
  useNotifications: () => ({ show: vi.fn() }),
}))

function app(over: Partial<AppSummary> = {}): AppSummary {
  return {
    packageId: "com.example.app",
    displayName: "Example",
    versionName: "1.0",
    isSystem: false,
    disabled: false,
    removed: false,
    ...over,
  }
}

const props = { serial: "S1", onChanged: vi.fn() }

/**
 * Which verb is offered is the app's own state. Offering all three would mean
 * two of them always fail — a package removed for this user cannot be disabled.
 */
describe("AppLifecycleActions", () => {
  it("offers Disable for an ordinary app", () => {
    render(<AppLifecycleActions app={app()} {...props} />)
    expect(screen.getByRole("button", { name: /Disable/u })).toBeDefined()
    expect(screen.queryByRole("button", { name: /Restore/u })).toBeNull()
  })

  it("offers Enable for one that is disabled, not Disable again", () => {
    render(<AppLifecycleActions app={app({ disabled: true })} {...props} />)
    expect(screen.getByRole("button", { name: /Enable/u })).toBeDefined()
    expect(screen.queryByRole("button", { name: /^Disable$/u })).toBeNull()
  })

  it("offers only Restore for one removed for this user", () => {
    // It is not installed for this user, so there is nothing to disable.
    render(<AppLifecycleActions app={app({ removed: true })} {...props} />)
    expect(screen.getByRole("button", { name: /Restore/u })).toBeDefined()
    expect(screen.queryByRole("button", { name: /Enable|Disable/u })).toBeNull()
  })

  it("asks before disabling", async () => {
    const { appLifecycle } = await import("@/lib/daemon")
    render(<AppLifecycleActions app={app()} {...props} />)
    fireEvent.click(screen.getByRole("button", { name: /Disable/u }))

    // The app vanishes from the launcher, which is alarming even though
    // getting it back is one button away.
    expect(screen.getByRole("alertdialog")).toBeDefined()
    expect(appLifecycle).not.toHaveBeenCalled()
  })

  it("does not ask before enabling", async () => {
    const { appLifecycle } = await import("@/lib/daemon")
    vi.mocked(appLifecycle).mockClear()
    render(<AppLifecycleActions app={app({ disabled: true })} {...props} />)
    fireEvent.click(screen.getByRole("button", { name: /Enable/u }))

    // Enabling puts something back; there is nothing to warn about.
    expect(screen.queryByRole("alertdialog")).toBeNull()
    expect(appLifecycle).toHaveBeenCalledWith({
      serial: "S1",
      packageId: "com.example.app",
      disabled: false,
    })
  })

  it("restores by clearing removed, not by a verb of its own", async () => {
    const { appLifecycle } = await import("@/lib/daemon")
    vi.mocked(appLifecycle).mockClear()
    render(<AppLifecycleActions app={app({ removed: true })} {...props} />)
    fireEvent.click(screen.getByRole("button", { name: /Restore/u }))

    expect(appLifecycle).toHaveBeenCalledWith({
      serial: "S1",
      packageId: "com.example.app",
      removed: false,
    })
  })
})
