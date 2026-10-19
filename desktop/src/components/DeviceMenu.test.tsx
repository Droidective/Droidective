import { cleanup, fireEvent, render, screen } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"

import { DeviceMenu, DevicePill } from "@/components/DeviceMenu"
import type { PhoneSetupMenu, TailscaleMenu } from "@/components/DeviceMenuSections"
import type { Device, PhoneSetupOffer } from "@/lib/wire"

vi.mock("@/hooks/useWindows", () => ({
  useWindows: () => ({ others: false, claims: [], label: "Window 1", newWindow: vi.fn() }),
}))

function menu({
  phoneSetup = null,
  tailscale = null,
  devices = [],
  onDismiss = vi.fn(),
}: {
  phoneSetup?: PhoneSetupMenu | null
  tailscale?: TailscaleMenu | null
  devices?: Device[]
  onDismiss?: () => void
} = {}) {
  render(
    <DeviceMenu
      devices={devices}
      selected={null}
      avds={[]}
      disabled={false}
      onSelect={vi.fn()}
      onLaunchAvd={vi.fn()}
      onPair={vi.fn()}
      onConnect={vi.fn()}
      phoneSetup={phoneSetup}
      tailscale={tailscale}
      onManageEmulators={vi.fn()}
      onDismiss={onDismiss}
    />,
  )
  return onDismiss
}

function tailnet(over: Partial<TailscaleMenu> = {}): TailscaleMenu {
  return { notice: null, peers: [], onConnect: vi.fn(), prepare: null, ...over }
}

const PIXEL = { id: "nPIXEL", name: "pixel-7", ipv4: "100.101.102.103" }

const SET_UP: PhoneSetupOffer = {
  kind: "setUp",
  menuTitle: "Set Up Droidective on This Phone…",
  from: null,
  to: null,
}

/** The Mac offers the entry only while there is something to do for the phone. */
describe("DeviceMenu phone set-up", () => {
  it("is absent when there is nothing to offer", () => {
    menu()
    expect(screen.queryByRole("menuitem", { name: /Droidective on This Phone/u })).toBeNull()
  })

  it("names what the daemon offers, and opens the sheet", () => {
    const offers: PhoneSetupOffer[] = [
      { ...SET_UP, kind: "install", menuTitle: "Install Droidective on This Phone…" },
      { kind: "update", menuTitle: "Update Droidective on This Phone…", from: "0.1.0", to: "0.1.1" },
      SET_UP,
    ]
    for (const offer of offers) {
      const onSelect = vi.fn()
      const onDismiss = menu({ phoneSetup: { offer, onSelect } })
      fireEvent.click(screen.getByRole("menuitem", { name: offer.menuTitle }))
      expect(onSelect).toHaveBeenCalledOnce()
      expect(onDismiss).toHaveBeenCalledOnce()
      cleanup()
    }
  })
})

/** The Mac's Tailscale section: between set-up and Wireless debugging. */
describe("DeviceMenu Tailscale section", () => {
  it("is absent without a Tailscale CLI", () => {
    menu({ tailscale: null })
    expect(screen.queryByText("Tailscale")).toBeNull()
  })

  it("is absent when it would have no row", () => {
    // A running tailnet whose phones are all connected already: they are in
    // the device list above instead.
    menu({ tailscale: tailnet() })
    expect(screen.queryByText("Tailscale")).toBeNull()
  })

  it("says why there is nothing to connect, as a row that does nothing", () => {
    menu({ tailscale: tailnet({ notice: "Tailscale is stopped" }) })
    expect(screen.getByText("Tailscale")).toBeTruthy()
    expect(screen.getByText("Tailscale is stopped").tagName).toBe("P")
    expect(screen.queryByRole("menuitem", { name: /Tailscale is stopped/u })).toBeNull()
  })

  it("connects a peer by name and closes the menu", () => {
    const onConnect = vi.fn()
    const onDismiss = menu({ tailscale: tailnet({ peers: [PIXEL], onConnect }) })
    fireEvent.click(screen.getByRole("menuitem", { name: "Connect pixel-7" }))
    expect(onConnect).toHaveBeenCalledWith(PIXEL)
    expect(onDismiss).toHaveBeenCalledOnce()
  })

  it("offers to prepare the cabled phone it was given", () => {
    const onSelect = vi.fn()
    const onDismiss = menu({
      tailscale: tailnet({ prepare: { name: "Pixel 7 (3ABC)", onSelect } }),
    })
    fireEvent.click(
      screen.getByRole("menuitem", { name: "Prepare Pixel 7 (3ABC) for Tailscale…" }),
    )
    expect(onSelect).toHaveBeenCalledOnce()
    expect(onDismiss).toHaveBeenCalledOnce()
  })

  it("sits after set-up and before Wireless debugging", () => {
    menu({
      phoneSetup: { offer: SET_UP, onSelect: vi.fn() },
      tailscale: tailnet({ peers: [PIXEL] }),
    })
    const items = screen.getAllByRole("menuitem").map((item) => item.textContent ?? "")
    const setUp = items.indexOf("Set Up Droidective on This Phone…")
    const connect = items.indexOf("Connect pixel-7")
    const pair = items.indexOf("Pair new device…")
    expect(setUp).toBeGreaterThanOrEqual(0)
    expect(setUp).toBeLessThan(connect)
    expect(connect).toBeLessThan(pair)
  })
})

describe("device titles", () => {
  const remote: Device = {
    serial: "100.101.102.103:5555",
    state: "device",
    model: "Pixel 7",
    product: null,
    transportId: null,
    label: "Pixel 7 (5555)",
    isWireless: true,
    platform: "android",
  }

  it("ends a tailnet phone's row with Tailscale", () => {
    menu({ devices: [remote] })
    expect(screen.getByRole("menuitem", { name: "Pixel 7 (5555) · Tailscale" })).toBeTruthy()
  })

  it("ends the pill's title the same way", () => {
    render(<DevicePill device={remote} open={false} disabled={false} onToggle={vi.fn()} />)
    expect(screen.getByText("Pixel 7 (5555) · Tailscale")).toBeTruthy()
  })
})
