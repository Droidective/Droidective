import { act, renderHook, waitFor } from "@testing-library/react"
import { beforeEach, describe, expect, it, vi } from "vitest"

import type { Device, FeatureKind, FeatureSummary } from "@/lib/wire"

/** What `runAction` was asked to do — the only thing these tests assert on. */
interface RunArgs {
  featureId: string
  serial: string
  platform?: string
  fields?: Record<string, unknown>
}

const { runAction, hideQuickPanel } = vi.hoisted(() => ({
  // Typed, so the argument assertions below are checked rather than `any`.
  runAction: vi.fn((_args: { featureId: string; serial: string }) =>
    Promise.resolve({ ok: true, message: "done" }),
  ),
  hideQuickPanel: vi.fn(() => Promise.resolve()),
}))

/** The one call's arguments, as this file wants to read them. */
function calledWith(index = 0): RunArgs {
  return runAction.mock.calls[index]?.[0] as unknown as RunArgs
}

vi.mock("@/lib/daemon", () => ({
  runAction,
  hideQuickPanel,
  asDaemonError: (thrown: unknown) => ({ code: "unknown", message: String(thrown), detail: null }),
}))

const { useQuickRun } = await import("@/hooks/useQuickRun")

function feature(over: Partial<FeatureSummary> & { id: string }): FeatureSummary {
  return {
    title: over.id,
    subtitle: null,
    keywords: [],
    category: "logs",
    kind: "instantAction" as FeatureKind,
    implemented: true,
    needsDevice: true,
    needsBundle: false,
    isDestructive: false,
    isAbsorbedByHub: false,
    absorbedBy: null,
    supportsRunAll: false,
    fields: [],
    ...over,
  }
}

function device(serial: string): Device {
  return { serial, label: serial, state: "device", platform: "android" } as Device
}

const one = [device("emulator-5554")]
const two = [device("emulator-5554"), device("emulator-5556")]

beforeEach(() => {
  runAction.mockClear()
  hideQuickPanel.mockClear()
})

function panel(ready: Device[]) {
  return renderHook(() => useQuickRun({ ready, closeAfterRun: false }))
}

describe("the questions before a run", () => {
  it("runs a plain action straight away", async () => {
    const { result } = panel(one)
    act(() => {
      result.current.activate(feature({ id: "screenshot" }))
    })
    await waitFor(() => {
      expect(runAction).toHaveBeenCalledTimes(1)
    })
    expect(calledWith()).toMatchObject({ serial: "emulator-5554" })
  })

  it("arms a destructive action and needs a second press", async () => {
    const { result } = panel(one)
    const wipe = feature({ id: "clear-data", isDestructive: true })
    act(() => {
      result.current.activate(wipe)
    })
    expect(result.current.armed).toBe("clear-data")
    expect(runAction).not.toHaveBeenCalled()
    act(() => {
      result.current.activate(wipe)
    })
    await waitFor(() => {
      expect(runAction).toHaveBeenCalledTimes(1)
    })
  })

  it("asks which device when there is more than one", () => {
    const { result } = panel(two)
    act(() => {
      result.current.activate(feature({ id: "screenshot" }))
    })
    expect(result.current.picking?.id).toBe("screenshot")
    expect(runAction).not.toHaveBeenCalled()
  })

  /**
   * The device settles first, because "which app" is a question about a
   * particular device — asking the other way round would offer a list that
   * might not exist on the device finally chosen.
   */
  it("asks which app only after the device is settled", async () => {
    const { result } = panel(two)
    act(() => {
      result.current.activate(feature({ id: "monkey", needsBundle: true }))
    })
    expect(result.current.picking?.id).toBe("monkey")
    expect(result.current.pickingApp).toBeNull()

    act(() => {
      result.current.pickDevice(["emulator-5556"])
    })
    expect(result.current.picking).toBeNull()
    expect(result.current.pickingApp?.id).toBe("monkey")
    expect(result.current.bundleSerial).toBe("emulator-5556")
    expect(runAction).not.toHaveBeenCalled()

    act(() => {
      result.current.pickApp("com.example.app")
    })
    await waitFor(() => {
      expect(runAction).toHaveBeenCalledTimes(1)
    })
    expect(calledWith()).toMatchObject({
      serial: "emulator-5556",
      fields: { packageId: "com.example.app" },
    })
  })

})

describe("only one screen can be in front", () => {
  /**
   * The regression this file exists for: only one screen can be in front, and
   * the panel checks the form first. A form action that then pushed an
   * interstitial left the form up with the interstitial behind it, which reads
   * as a Run button that does nothing.
   */
  it("takes the form down when it pushes an interstitial", () => {
    const { result } = panel(one)
    const monkey = feature({
      id: "monkey",
      kind: "formAction" as FeatureKind,
      needsBundle: true,
    })
    act(() => {
      result.current.activate(monkey)
    })
    expect(result.current.form?.id).toBe("monkey")

    act(() => {
      result.current.submitForm({ count: 500 }, true)
    })
    expect(result.current.form).toBeNull()
    expect(result.current.pickingApp?.id).toBe("monkey")
  })

  it("takes the form down for the device question too", () => {
    const { result } = panel(two)
    const send = feature({ id: "send-text", kind: "formAction" as FeatureKind })
    act(() => {
      result.current.activate(send)
    })
    act(() => {
      result.current.submitForm({ text: "hi" }, true)
    })
    expect(result.current.form).toBeNull()
    expect(result.current.picking?.id).toBe("send-text")
  })

  /** A form's values have to survive both questions, or the run is wrong. */
  it("keeps the form's values across the questions", async () => {
    const { result } = panel(two)
    act(() => {
      result.current.activate(
        feature({
          id: "monkey",
          kind: "formAction" as FeatureKind,
          needsBundle: true,
          // Declared, because `runFields` copies only the fields the registry
          // says the runner takes — an undeclared one is dropped by design.
          fields: [
            {
              name: "count",
              label: "Event count",
              control: "number",
              options: [],
              placeholder: null,
              description: null,
              defaultValue: null,
              optional: false,
              min: null,
              max: null,
              step: null,
            },
          ],
        }),
      )
    })
    act(() => {
      result.current.submitForm({ count: 42 }, true)
    })
    act(() => {
      result.current.pickDevice(["emulator-5554"])
    })
    act(() => {
      result.current.pickApp("com.example.app")
    })
    await waitFor(() => {
      expect(runAction).toHaveBeenCalledTimes(1)
    })
    expect(calledWith()).toMatchObject({
      fields: { count: 42, packageId: "com.example.app" },
    })
  })

})

describe("what a run refuses to guess", () => {
  it("says so rather than guessing when nothing is connected", () => {
    const { result } = panel([])
    act(() => {
      result.current.activate(feature({ id: "screenshot" }))
    })
    expect(result.current.outcome).toEqual({ message: "No device connected.", ok: false })
    expect(runAction).not.toHaveBeenCalled()
  })

  it("runs a device-free action with no questions at all", async () => {
    const { result } = panel([])
    act(() => {
      result.current.activate(feature({ id: "api-client", needsDevice: false }))
    })
    await waitFor(() => {
      expect(runAction).toHaveBeenCalledTimes(1)
    })
  })
})

describe("backing out", () => {
  it("pops a screen, and closes the panel at the root", () => {
    const { result } = panel(two)
    act(() => {
      result.current.activate(feature({ id: "screenshot" }))
    })
    act(() => {
      result.current.back()
    })
    expect(result.current.picking).toBeNull()
    expect(hideQuickPanel).not.toHaveBeenCalled()

    act(() => {
      result.current.back()
    })
    expect(hideQuickPanel).toHaveBeenCalledTimes(1)
  })
})
