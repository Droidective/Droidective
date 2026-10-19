import { act, renderHook, waitFor } from "@testing-library/react"
import { beforeEach, describe, expect, it, vi } from "vitest"

import { usePhoneSetupProbe } from "@/hooks/useDeviceBarActions"
import type { Device, PhoneSetupOffer } from "@/lib/wire"

vi.mock("@/lib/daemon", () => ({ phoneSetupOffer: vi.fn() }))

function phone(serial: string, over: Partial<Device> = {}): Device {
  return {
    serial,
    state: "device",
    model: null,
    product: null,
    transportId: null,
    label: serial,
    isWireless: false,
    platform: "android",
    ...over,
  }
}

const INSTALL: PhoneSetupOffer = {
  kind: "install",
  menuTitle: "Install Droidective on This Phone…",
  from: null,
  to: null,
}

/**
 * The Mac's `probePhoneSetup`: the menu shows what the daemon offers the
 * selected phone, never another phone's answer, and nothing it cannot read.
 */
describe("usePhoneSetupProbe", () => {
  beforeEach(async () => {
    const { phoneSetupOffer } = await import("@/lib/daemon")
    vi.mocked(phoneSetupOffer).mockReset()
  })

  it("shows the daemon's offer for the selected phone", async () => {
    const { phoneSetupOffer } = await import("@/lib/daemon")
    vi.mocked(phoneSetupOffer).mockResolvedValue({ offer: INSTALL })
    const { result } = renderHook(() => usePhoneSetupProbe(phone("S1")))

    await waitFor(() => {
      expect(result.current.offer).toEqual(INSTALL)
    })
    expect(phoneSetupOffer).toHaveBeenCalledWith("S1")
  })

  it("never asks about a phone that isn't ready, or a simulator", async () => {
    const { phoneSetupOffer } = await import("@/lib/daemon")
    renderHook(() => usePhoneSetupProbe(phone("S1", { state: "unauthorized" })))
    renderHook(() => usePhoneSetupProbe(phone("SIM", { platform: "ios-simulator" })))
    renderHook(() => usePhoneSetupProbe(null))
    expect(phoneSetupOffer).not.toHaveBeenCalled()
  })

  it("keeps an answer with the phone it was about", async () => {
    const { phoneSetupOffer } = await import("@/lib/daemon")
    vi.mocked(phoneSetupOffer).mockResolvedValue({ offer: INSTALL })
    const { result, rerender } = renderHook(({ device }) => usePhoneSetupProbe(device), {
      initialProps: { device: phone("S1") },
    })
    await waitFor(() => {
      expect(result.current.offer).toEqual(INSTALL)
    })

    // The next phone's question is still out: S1's answer must not show under it.
    vi.mocked(phoneSetupOffer).mockReturnValue(new Promise(() => {}))
    rerender({ device: phone("S2") })
    expect(result.current.offer).toBeNull()
  })

  it("takes what the sheet reports, and forgets a failed read", async () => {
    const { phoneSetupOffer } = await import("@/lib/daemon")
    vi.mocked(phoneSetupOffer).mockRejectedValue(new Error("daemon gone"))
    const { result } = renderHook(() => usePhoneSetupProbe(phone("S1")))
    await waitFor(() => {
      expect(phoneSetupOffer).toHaveBeenCalled()
    })
    expect(result.current.offer).toBeNull()

    act(() => {
      result.current.report("S1", INSTALL)
    })
    expect(result.current.offer).toEqual(INSTALL)
    act(() => {
      result.current.report("S1", null)
    })
    expect(result.current.offer).toBeNull()
  })
})
