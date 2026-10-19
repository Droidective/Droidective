import { fireEvent, render, screen } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"

import { DeviceSheets } from "@/components/DeviceSheets"
import type { Device } from "@/lib/wire"

const phone: Device = {
  serial: "R58M123ABC",
  state: "device",
  model: "Pixel 7",
  product: null,
  transportId: null,
  label: "Pixel 7 (3ABC)",
  isWireless: false,
  platform: "android",
}

/** Whatever the daemon served; the dialog shows it rather than its own words. */
const WARNING = "Served warning, first paragraph.\n\nServed warning, second paragraph."

function prepareSheet() {
  const onPrepare = vi.fn()
  const onDismiss = vi.fn()
  render(
    <DeviceSheets
      sheet={{ kind: "tailscale-prepare", device: phone, warning: WARNING }}
      devices={[phone]}
      onSelectDevice={vi.fn()}
      onPhoneOffer={vi.fn()}
      onPrepareForTailscale={onPrepare}
      onDismiss={onDismiss}
    />,
  )
  return { onPrepare, onDismiss }
}

/** "Prepare for Tailscale" asks before `adb tcpip 5555`, as the Mac does. */
describe("the Prepare for Tailscale question", () => {
  it("names the phone and shows the served warning", () => {
    prepareSheet()
    const dialog = screen.getByRole("alertdialog", {
      name: "Prepare Pixel 7 (3ABC) for Tailscale?",
    })
    expect(dialog.textContent).toContain("Served warning, first paragraph.")
    expect(dialog.textContent).toContain("Served warning, second paragraph.")
  })

  it("prepares only once confirmed", () => {
    const { onPrepare, onDismiss } = prepareSheet()
    fireEvent.click(screen.getByRole("button", { name: "Prepare" }))
    expect(onPrepare).toHaveBeenCalledWith(phone)
    expect(onDismiss).toHaveBeenCalledOnce()
  })

  it("does nothing on Cancel", () => {
    const { onPrepare, onDismiss } = prepareSheet()
    fireEvent.click(screen.getAllByRole("button", { name: "Cancel" })[0] as HTMLElement)
    expect(onPrepare).not.toHaveBeenCalled()
    expect(onDismiss).toHaveBeenCalledOnce()
  })
})
