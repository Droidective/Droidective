import { renderHook, waitFor } from "@testing-library/react"
import { beforeEach, describe, expect, it, vi } from "vitest"
import type { Device, FeatureSummary, StreamUpdate } from "@/lib/wire"

const { listFeatures, listDevices, watchDevices, daemonStatus, onDaemonStatus, settleDevices, emit } =
  vi.hoisted(() => {
    let resolveDevices: ((devices: Device[]) => void) | null = null
    let send: ((update: StreamUpdate<Device>) => void) | null = null
    return {
      listFeatures: vi.fn(() => Promise.resolve([] as FeatureSummary[])),
      // Pending until a test settles it — the whole point here is what the app
      // does while adb has not answered yet.
      listDevices: vi.fn(
        () =>
          new Promise<Device[]>((resolve) => {
            resolveDevices = resolve
          }),
      ),
      watchDevices: vi.fn((onUpdate: (update: StreamUpdate<Device>) => void) => {
        send = onUpdate
        return Promise.resolve({ stop: () => Promise.resolve() })
      }),
      daemonStatus: vi.fn(() => Promise.resolve({ state: "ready" as const })),
      onDaemonStatus: vi.fn((notify: (next: { state: "ready" }) => void) => {
        // Both ready paths fire, which is the race the hook guards: the status
        // event and the immediate `daemonStatus()` answer.
        notify({ state: "ready" })
        return Promise.resolve(() => {})
      }),
      settleDevices: (devices: Device[]) => {
        resolveDevices?.(devices)
      },
      emit: (update: StreamUpdate<Device>) => {
        send?.(update)
      },
    }
  })

vi.mock("@/lib/daemon", () => ({
  listFeatures,
  listDevices,
  watchDevices,
  daemonStatus,
  onDaemonStatus,
  asDaemonError: (thrown: unknown) => ({ code: "unknown", message: String(thrown), detail: null }),
}))

const { useSession } = await import("@/hooks/useSession")

const feature = (id: string): FeatureSummary =>
  ({ id, title: id, category: "Device", kind: "view", implemented: true }) as FeatureSummary

const device = (serial: string): Device => ({ serial, state: "device" }) as Device

describe("useSession", () => {
  beforeEach(() => {
    listFeatures.mockClear()
    listDevices.mockClear()
    watchDevices.mockClear()
  })

  it("shows the features while the device list is still pending", async () => {
    listFeatures.mockResolvedValueOnce([feature("logcat"), feature("terminal")])

    const rendered = renderHook(() => useSession())

    // This is the regression: the two used to arrive through one Promise.all,
    // so a slow `adb devices` — which is what a machine with no adb server
    // running has — left the window with "0 features" and no explanation.
    await waitFor(() => expect(rendered.result.current.features).toHaveLength(2))
    expect(rendered.result.current.devicesLoaded).toBe(false)
    expect(rendered.result.current.devices).toEqual([])
  })

  it("lands the devices and opens the stream once adb answers", async () => {
    const rendered = renderHook(() => useSession())
    settleDevices([device("emulator-5554")])

    await waitFor(() => expect(rendered.result.current.devicesLoaded).toBe(true))
    expect(rendered.result.current.selected?.serial).toBe("emulator-5554")
    await waitFor(() => expect(watchDevices).toHaveBeenCalledTimes(1))

    emit({ event: "batch", items: [] } as StreamUpdate<Device>)
    await waitFor(() => expect(rendered.result.current.devices).toEqual([]))
  })

  it("loads once even though both ready paths fire", async () => {
    renderHook(() => useSession())
    settleDevices([])

    await waitFor(() => expect(watchDevices).toHaveBeenCalledTimes(1))
    expect(listFeatures).toHaveBeenCalledTimes(1)
    expect(listDevices).toHaveBeenCalledTimes(1)
  })
})
