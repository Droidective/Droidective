import { describe, expect, it, vi } from "vitest"

import { tailscaleMenu } from "@/hooks/useDeviceBarActions"
import type { Device, TailscaleStatus } from "@/lib/wire"

const WARNING = "This runs adb tcpip 5555. …\n\nThat listener is plaintext …"

function status(over: Partial<TailscaleStatus> = {}): TailscaleStatus {
  return {
    installed: true,
    flavor: "appBundle",
    backendState: "Running",
    running: true,
    notice: null,
    peers: [{ id: "nPIXEL", name: "pixel-7", ipv4: "100.101.102.103" }],
    prepareWarning: WARNING,
    ...over,
  }
}

function device(over: Partial<Device> = {}): Device {
  return {
    serial: "R58M123ABC",
    state: "device",
    model: "Pixel 7",
    product: null,
    transportId: null,
    label: "Pixel 7 (3ABC)",
    isWireless: false,
    platform: "android",
    ...over,
  }
}

const connect = vi.fn()

describe("tailscaleMenu", () => {
  it("is no section without a Tailscale CLI, or before the first read", () => {
    expect(tailscaleMenu({ status: null, connect }, device(), vi.fn())).toBeNull()
    expect(
      tailscaleMenu({ status: status({ installed: false }), connect }, device(), vi.fn()),
    ).toBeNull()
  })

  it("carries the daemon's notice and peers as they came", () => {
    const menu = tailscaleMenu(
      { status: status({ notice: "Tailscale is stopped", peers: [] }), connect },
      null,
      vi.fn(),
    )
    expect(menu?.notice).toBe("Tailscale is stopped")
    expect(menu?.peers).toEqual([])
    expect(menu?.onConnect).toBe(connect)
  })

  it("offers to prepare a cabled phone, opening the served warning", () => {
    const onSheet = vi.fn()
    const phone = device()
    const menu = tailscaleMenu({ status: status(), connect }, phone, onSheet)
    expect(menu?.prepare?.name).toBe("Pixel 7 (3ABC)")

    menu?.prepare?.onSelect()
    expect(onSheet).toHaveBeenCalledWith({
      kind: "tailscale-prepare",
      device: phone,
      warning: WARNING,
    })
  })

  it("does not offer it for a wireless phone, an emulator, or one not ready", () => {
    for (const selected of [
      device({ serial: "100.101.102.103:5555", isWireless: true }),
      device({ serial: "emulator-5560" }),
      device({ state: "unauthorized" }),
      null,
    ]) {
      expect(tailscaleMenu({ status: status(), connect }, selected, vi.fn())?.prepare).toBeNull()
    }
  })
})
