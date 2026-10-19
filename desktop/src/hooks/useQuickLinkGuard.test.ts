import { act, renderHook, waitFor } from "@testing-library/react"
import { beforeEach, describe, expect, it, vi } from "vitest"

import type { Device, FeatureSummary } from "@/lib/wire"

const { runAction } = vi.hoisted(() => ({
  runAction: vi.fn((_args: { featureId: string; serial: string }) =>
    Promise.resolve({ ok: true, message: "done" }),
  ),
}))

vi.mock("@/lib/daemon", () => ({
  runAction,
  hideQuickPanel: vi.fn(() => Promise.resolve()),
  asDaemonError: (thrown: unknown) => ({ code: "unknown", message: String(thrown), detail: null }),
}))

const { useQuickRun } = await import("@/hooks/useQuickRun")

const toggles = {
  id: "network-toggles",
  title: "Network Toggles",
  subtitle: null,
  keywords: [],
  category: "deviceState",
  kind: "formAction",
  implemented: true,
  needsDevice: true,
  needsBundle: false,
  isDestructive: false,
  remoteLinkWarning: "Turning off Wi-Fi or mobile data can take it off your tailnet.",
  isAbsorbedByHub: true,
  absorbedBy: "simulate",
  supportsRunAll: true,
  fields: [],
} satisfies FeatureSummary

function device(serial: string): Device {
  return { serial, label: serial, state: "device", platform: "android" } as Device
}

const remote = device("100.101.102.103:5555")
const cabled = device("emulator-5554")

function panel(ready: Device[]) {
  return renderHook(() => useQuickRun({ ready, closeAfterRun: false }))
}

/** Open the form and press Run once. */
function submitOnce(result: ReturnType<typeof panel>["result"]) {
  act(() => {
    result.current.activate(toggles)
  })
  act(() => {
    result.current.submitForm({}, true)
  })
}

beforeEach(() => {
  runAction.mockClear()
})

/**
 * The Mac panel's link-cut question: a panel that never takes focus cannot
 * hold a dialog, so a feature that can take a phone off the network arms on a
 * tailnet phone and runs on the second press.
 */
describe("a link-cutting run from the Quick Actions panel", () => {
  it("arms on the first press, with the question, and runs on the second", async () => {
    const { result } = panel([remote])
    submitOnce(result)
    expect(runAction).not.toHaveBeenCalled()
    expect(result.current.form?.id).toBe("network-toggles")
    expect(result.current.linkWarning?.title).toBe(
      "100.101.102.103:5555 is connected over Tailscale",
    )

    act(() => {
      result.current.submitForm({}, true)
    })
    await waitFor(() => {
      expect(runAction).toHaveBeenCalledTimes(1)
    })
    expect(result.current.linkWarning).toBeNull()
  })

  it("does not ask on a cabled phone", async () => {
    const { result } = panel([cabled])
    submitOnce(result)
    await waitFor(() => {
      expect(runAction).toHaveBeenCalledTimes(1)
    })
    expect(result.current.linkWarning).toBeNull()
  })

  it("asks on the device picker, and arming one choice is not consent for another", async () => {
    const { result } = panel([cabled, remote])
    submitOnce(result)
    act(() => {
      result.current.pickDevice([remote.serial])
    })
    // Still on the picker, which is where the question shows.
    expect(result.current.picking?.id).toBe("network-toggles")
    expect(result.current.linkWarning).not.toBeNull()

    act(() => {
      result.current.pickDevice([cabled.serial, remote.serial])
    })
    expect(runAction).not.toHaveBeenCalled()

    act(() => {
      result.current.pickDevice([cabled.serial, remote.serial])
    })
    await waitFor(() => {
      expect(runAction).toHaveBeenCalledTimes(2)
    })
  })

  it("withdraws the question when the screen is left", () => {
    const { result } = panel([remote])
    submitOnce(result)
    act(() => {
      result.current.back()
    })
    expect(result.current.linkWarning).toBeNull()
    expect(runAction).not.toHaveBeenCalled()
  })
})
