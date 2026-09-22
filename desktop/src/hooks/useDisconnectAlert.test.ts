import { act, renderHook } from "@testing-library/react"
import { describe, expect, it } from "vitest"

import { useDisconnectAlert } from "@/hooks/useDisconnectAlert"
import type { Device } from "@/lib/wire"

const phone = { serial: "emulator-5554", state: "device", model: "Pixel" } as Device

describe("useDisconnectAlert", () => {
  it("announces a device that drops off", () => {
    const view = renderHook(({ device }) => useDisconnectAlert(device, true), {
      initialProps: { device: phone as Device | null },
    })
    expect(view.result.current.showing).toBe(false)
    view.rerender({ device: null })
    expect(view.result.current.showing).toBe(true)
  })

  it("says nothing when the screen simply opens with nothing connected", () => {
    // The relay listens on this machine and runs with no device at all, so
    // that is the ordinary case here — an alert would be an interruption
    // rather than news.
    const view = renderHook(({ device }) => useDisconnectAlert(device, true), {
      initialProps: { device: null as Device | null },
    })
    expect(view.result.current.showing).toBe(false)
  })

  it("stays quiet while another tab is on screen", () => {
    // Every open tab stays mounted. Without the guard, a hidden Reactotron tab
    // puts a modal over whatever someone is actually looking at.
    const view = renderHook(({ device }) => useDisconnectAlert(device, false), {
      initialProps: { device: phone as Device | null },
    })
    view.rerender({ device: null })
    expect(view.result.current.showing).toBe(false)
  })

  it("announces the next disconnect after one is dismissed", () => {
    const view = renderHook(({ device }) => useDisconnectAlert(device, true), {
      initialProps: { device: phone as Device | null },
    })
    view.rerender({ device: null })
    act(() => {
      view.result.current.dismiss()
    })
    expect(view.result.current.showing).toBe(false)

    view.rerender({ device: phone })
    view.rerender({ device: null })
    expect(view.result.current.showing).toBe(true)
  })

  it("does not re-announce on a re-render with the device still gone", () => {
    const view = renderHook(({ device }) => useDisconnectAlert(device, true), {
      initialProps: { device: phone as Device | null },
    })
    view.rerender({ device: null })
    act(() => {
      view.result.current.dismiss()
    })
    view.rerender({ device: null })
    expect(view.result.current.showing).toBe(false)
  })
})
