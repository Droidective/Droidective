import { fireEvent, render, screen } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"

import { DeviceMenu } from "@/components/DeviceMenu"

vi.mock("@/hooks/useWindows", () => ({
  useWindows: () => ({ others: false, claims: [], label: "Window 1", newWindow: vi.fn() }),
}))

function menu(onPhoneSetup: (() => void) | null, onDismiss = vi.fn()) {
  render(
    <DeviceMenu
      devices={[]}
      selected={null}
      avds={[]}
      disabled={false}
      onSelect={vi.fn()}
      onLaunchAvd={vi.fn()}
      onPair={vi.fn()}
      onConnect={vi.fn()}
      onPhoneSetup={onPhoneSetup}
      onManageEmulators={vi.fn()}
      onDismiss={onDismiss}
    />,
  )
  return onDismiss
}

/** The Mac offers set-up only while the selected phone needs it. */
describe("DeviceMenu phone set-up", () => {
  it("is absent when there is nothing to set up", () => {
    menu(null)
    expect(screen.queryByRole("menuitem", { name: /Set Up Droidective/u })).toBeNull()
  })

  it("opens the sheet and closes the menu when the phone needs it", () => {
    const onPhoneSetup = vi.fn()
    const onDismiss = menu(onPhoneSetup)
    fireEvent.click(screen.getByRole("menuitem", { name: "Set Up Droidective on This Phone…" }))
    expect(onPhoneSetup).toHaveBeenCalledOnce()
    expect(onDismiss).toHaveBeenCalledOnce()
  })
})
