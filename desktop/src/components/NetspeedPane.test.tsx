import { act, render, screen, waitFor } from "@testing-library/react"
import { beforeEach, describe, expect, it, vi } from "vitest"
import type { Device, NetSample, StreamUpdate } from "@/lib/wire"

const { watchNetspeed, emit, writeRecording, show } = vi.hoisted(() => {
  let send: ((update: StreamUpdate<NetSample>) => void) | null = null
  return {
    watchNetspeed: vi.fn(
      (_serial: string, onUpdate: (update: StreamUpdate<NetSample>) => void) => {
        send = onUpdate
        return Promise.resolve({ stop: () => Promise.resolve() })
      },
    ),
    emit: (update: StreamUpdate<NetSample>) => {
      send?.(update)
    },
    writeRecording: vi.fn((_samples: readonly unknown[], _serial: string) =>
      Promise.resolve({ ok: true, message: "Exported" }),
    ),
    show: vi.fn(),
  }
})

vi.mock("@/lib/daemon", () => ({
  watchNetspeed,
  asDaemonError: (thrown: unknown) => ({ code: "unknown", message: String(thrown), detail: null }),
}))
vi.mock("@/lib/netexport", () => ({ writeRecording }))
vi.mock("@/hooks/useNotifications", () => ({ useNotifications: () => ({ show }) }))

const { NetspeedPane } = await import("@/components/NetspeedPane")

const device: Device = {
  serial: "abc",
  state: "device",
  model: "Pixel",
  product: null,
  platform: "android",
} as Device

const sample = (): NetSample => ({
  downloadBytesPerSec: 1024,
  uploadBytesPerSec: 512,
  totalRxBytes: 1_000_000,
  totalTxBytes: 500_000,
  interfaces: [],
})

/** Mount, start a recording, and get three samples into it. */
async function recordingPane() {
  render(<NetspeedPane device={device} />)
  await waitFor(() => {
    expect(watchNetspeed).toHaveBeenCalled()
  })
  act(() => {
    emit({ event: "batch", items: [sample(), sample(), sample()] })
  })
  await screen.findByRole("button", { name: /record/iu })
  act(() => {
    screen.getByRole("button", { name: /record/iu }).click()
  })
  act(() => {
    emit({ event: "batch", items: [sample(), sample(), sample()] })
  })
  await screen.findByRole("button", { name: /stop/iu })
}

describe("NetspeedPane", () => {
  beforeEach(() => {
    watchNetspeed.mockClear()
    writeRecording.mockClear()
    show.mockClear()
  })

  it("keeps the recording after exporting it", async () => {
    // The regression this guards: a successful export called `discard()`,
    // which both stopped the recording nobody asked to stop and threw away
    // the samples. The Mac's `NetworkView.export()` writes and returns.
    await recordingPane()

    act(() => {
      screen.getByRole("button", { name: /export/iu }).click()
    })
    await waitFor(() => {
      expect(writeRecording).toHaveBeenCalled()
    })

    // Still recording, and the samples are still there to export again.
    expect(screen.getByRole("button", { name: /stop/iu })).toBeDefined()
    act(() => {
      screen.getByRole("button", { name: /export/iu }).click()
    })
    await waitFor(() => {
      expect(writeRecording).toHaveBeenCalledTimes(2)
    })
    expect(writeRecording.mock.calls[1]?.[0]).toHaveLength(3)
  })

  it("keeps the samples when stopping without exporting", async () => {
    // "Stop without exporting" answers "not now", not "throw it away" — the
    // Export button must still work afterwards.
    await recordingPane()

    act(() => {
      screen.getByRole("button", { name: /stop/iu }).click()
    })
    act(() => {
      screen.getByRole("button", { name: "Stop without exporting" }).click()
    })

    expect(screen.getByRole("button", { name: /record/iu })).toBeDefined()
    act(() => {
      screen.getByRole("button", { name: /export/iu }).click()
    })
    await waitFor(() => {
      expect(writeRecording).toHaveBeenCalled()
    })
    expect(writeRecording.mock.calls[0]?.[0]).toHaveLength(3)
  })

  it("stops straight away when there is nothing recorded", async () => {
    render(<NetspeedPane device={device} />)
    await waitFor(() => {
      expect(watchNetspeed).toHaveBeenCalled()
    })
    act(() => {
      screen.getByRole("button", { name: /record/iu }).click()
    })
    act(() => {
      screen.getByRole("button", { name: /stop/iu }).click()
    })

    // No dialog: there is nothing to lose.
    expect(screen.queryByText("Export this recording before stopping?")).toBeNull()
    expect(screen.getByRole("button", { name: /record/iu })).toBeDefined()
  })
})
