import { act, renderHook, waitFor } from "@testing-library/react"
import { beforeEach, describe, expect, it, vi } from "vitest"
import type { NetSample, StreamUpdate } from "@/lib/wire"

const { watchNetspeed, emit } = vi.hoisted(() => {
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
  }
})

vi.mock("@/lib/daemon", () => ({
  watchNetspeed,
  asDaemonError: (thrown: unknown) => ({
    code: "unknown",
    message: String(thrown),
    detail: null,
  }),
}))

const { useNetspeed } = await import("@/hooks/useNetspeed")

const sample = (): NetSample => ({
  downloadBytesPerSec: 1024,
  uploadBytesPerSec: 512,
  totalRxBytes: 1_000_000,
  totalTxBytes: 500_000,
  interfaces: [],
})

describe("useNetspeed", () => {
  beforeEach(() => {
    watchNetspeed.mockClear()
  })

  async function recording(count: number) {
    const rendered = renderHook(() => useNetspeed("abc"))
    await waitFor(() => {
      expect(watchNetspeed).toHaveBeenCalled()
    })
    act(() => {
      rendered.result.current.startRecording()
    })
    act(() => {
      emit({ event: "batch", items: Array.from({ length: count }, sample) })
    })
    await waitFor(() => {
      expect(rendered.result.current.recorded).toHaveLength(count)
    })
    return rendered
  }

  it("keeps the samples when the recording stops", async () => {
    // The Mac's `NetworkView.stopRecording()` only flips the flag; the samples
    // stay exportable. `stopRecording` must not be `discard` by another name.
    const { result } = await recording(3)

    act(() => {
      result.current.stopRecording()
    })

    expect(result.current.recording).toBe(false)
    expect(result.current.recorded).toHaveLength(3)
  })

  it("starts a new recording empty rather than adopting the rolling window", async () => {
    const { result } = await recording(2)

    act(() => {
      result.current.startRecording()
    })

    expect(result.current.recorded).toHaveLength(0)
    expect(result.current.live.length).toBeGreaterThan(0)
  })
})
