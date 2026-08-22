import { act, renderHook, waitFor } from "@testing-library/react"
import { beforeEach, describe, expect, it, vi } from "vitest"
import type { PerfSample, StreamUpdate } from "@/lib/wire"

const { watchPerformance, emit } = vi.hoisted(() => {
  let send: ((update: StreamUpdate<PerfSample>) => void) | null = null
  return {
    watchPerformance: vi.fn(
      (_params: unknown, onUpdate: (update: StreamUpdate<PerfSample>) => void) => {
        send = onUpdate
        return Promise.resolve({ stop: () => Promise.resolve() })
      },
    ),
    emit: (update: StreamUpdate<PerfSample>) => {
      send?.(update)
    },
  }
})

vi.mock("@/lib/daemon", () => ({
  watchPerformance,
  asDaemonError: (thrown: unknown) => ({
    code: "unknown",
    message: String(thrown),
    detail: null,
  }),
}))

const { usePerformance } = await import("@/hooks/usePerformance")

const sample = (cpu: number): PerfSample => ({
  cores: [{ core: -1, label: "All", usagePercent: cpu }],
  ramTotalKb: 8_000_000,
  ramUsedKb: 4_000_000,
  appFps: null,
  appJankPercent: null,
  appPssKb: null,
  downloadBytesPerSec: null,
  uploadBytesPerSec: null,
  processes: [],
})

/** Record, then feed `count` samples in. */
async function recordSamples(
  result: { current: { toggleRecord: () => void; samples: unknown[] } },
  count: number,
) {
  act(() => {
    result.current.toggleRecord()
  })
  await waitFor(() => {
    expect(watchPerformance).toHaveBeenCalled()
  })
  act(() => {
    emit({ event: "batch", items: Array.from({ length: count }, (_, i) => sample(i)) })
  })
  await waitFor(() => {
    expect(result.current.samples).toHaveLength(count)
  })
}

describe("usePerformance", () => {
  beforeEach(() => {
    watchPerformance.mockClear()
  })

  it("keeps the recording when per-process is toggled mid-run", async () => {
    // The regression this guards: `processes` was in the reset effect's
    // dependency list, so flipping the toolbar switch emptied `samples` and
    // dropped the phase to idle — minutes of data gone, with no confirmation
    // and without going through the "Export before stopping?" guard.
    const { result, rerender } = renderHook(
      ({ processes }) => usePerformance({ serial: "abc", packageId: null, processes }),
      { initialProps: { processes: false } },
    )

    await recordSamples(result, 3)

    rerender({ processes: true })

    expect(result.current.samples).toHaveLength(3)
    expect(result.current.phase).toBe("recording")
  })

  it("re-subscribes with the new per-process flag", async () => {
    const { result, rerender } = renderHook(
      ({ processes }) => usePerformance({ serial: "abc", packageId: null, processes }),
      { initialProps: { processes: false } },
    )

    await recordSamples(result, 1)
    expect(watchPerformance.mock.calls[0]?.[0]).toMatchObject({ processes: false })

    rerender({ processes: true })

    await waitFor(() => {
      expect(watchPerformance).toHaveBeenCalledTimes(2)
    })
    expect(watchPerformance.mock.calls[1]?.[0]).toMatchObject({ processes: true })
  })

  it("still discards the recording when the device changes", async () => {
    // The other half of the same effect, which is correct and must stay:
    // splicing two devices' numbers into one chart would be worse than losing
    // the run.
    const { result, rerender } = renderHook(
      ({ serial }) => usePerformance({ serial, packageId: null, processes: false }),
      { initialProps: { serial: "abc" } },
    )

    await recordSamples(result, 2)

    rerender({ serial: "xyz" })

    expect(result.current.samples).toHaveLength(0)
    expect(result.current.phase).toBe("idle")
  })

  it("still discards the recording when the app bundle changes", async () => {
    const { result, rerender } = renderHook(
      ({ packageId }) => usePerformance({ serial: "abc", packageId, processes: false }),
      { initialProps: { packageId: "com.one" as string | null } },
    )

    await recordSamples(result, 2)

    rerender({ packageId: "com.two" })

    expect(result.current.samples).toHaveLength(0)
    expect(result.current.phase).toBe("idle")
  })
})
