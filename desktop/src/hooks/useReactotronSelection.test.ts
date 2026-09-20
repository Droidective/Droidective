import { act, renderHook } from "@testing-library/react"
import { beforeEach, describe, expect, it, vi } from "vitest"

import { useReactotronSelection } from "@/hooks/useReactotronSelection"
import type { TimelineRow } from "@/lib/reactotron-rows"

function row(id: number, message: string): TimelineRow {
  return {
    id,
    event: { kind: "log", level: "debug", message } as unknown as TimelineRow["event"],
    command: { type: "log", payload: { message } } as unknown as TimelineRow["command"],
    connection: 1,
    important: false,
    bytes: 32,
    receivedAt: Date.UTC(2026, 8, 20, 12, 0, 0, 0),
  } as unknown as TimelineRow
}

const rows = [row(1, "one"), row(2, "two"), row(3, "three")]
const withCtrl = { ctrlKey: true, metaKey: false, shiftKey: false }
const plain = { ctrlKey: false, metaKey: false, shiftKey: false }

const onCopy = vi.fn()
beforeEach(() => {
  onCopy.mockClear()
})

describe("picking timeline rows", () => {
  it("uses the same gestures as the console", () => {
    // Same hook underneath, which is the point: the Mac shares RowSelection
    // between the two screens and so does this.
    const { result } = renderHook(() => useReactotronSelection(rows, onCopy))
    act(() => {
      result.current.onPointerDown(1, withCtrl)
    })
    act(() => {
      result.current.onPointerDown(3, { ...plain, shiftKey: true })
    })
    expect(result.current.count).toBe(3)
  })

  it("does not pick on a plain click", () => {
    const { result } = renderHook(() => useReactotronSelection(rows, onCopy))
    act(() => {
      result.current.onPointerDown(2, plain)
    })
    expect(result.current.count).toBe(0)
  })
})

describe("copying the picked events", () => {
  it("copies the lines, blank-line separated, and says how many", () => {
    const { result } = renderHook(() => useReactotronSelection(rows, onCopy))
    act(() => {
      result.current.onPointerDown(1, withCtrl)
    })
    act(() => {
      result.current.onPointerDown(2, withCtrl)
    })
    act(() => {
      result.current.copy()
    })
    const [text, count, asJson] = onCopy.mock.calls[0] ?? []
    expect(count).toBe(2)
    expect(asJson).toBe(false)
    expect(String(text)).toContain("\n\n")
  })

  it("copies as the frames the app sent, not the rendered line", () => {
    const { result } = renderHook(() => useReactotronSelection(rows, onCopy))
    act(() => {
      result.current.onPointerDown(2, withCtrl)
    })
    act(() => {
      result.current.copyAsJson()
    })
    const [text, count, asJson] = onCopy.mock.calls[0] ?? []
    expect(count).toBe(1)
    expect(asJson).toBe(true)
    const written = JSON.parse(String(text))
    expect(written[0]).toMatchObject({ type: "log" })
  })

  it("does nothing with nothing picked", () => {
    const { result } = renderHook(() => useReactotronSelection(rows, onCopy))
    act(() => {
      result.current.copy()
    })
    expect(onCopy).not.toHaveBeenCalled()
  })

  it("copies on Ctrl+C while rows are picked, and not otherwise", () => {
    const { result } = renderHook(() => useReactotronSelection(rows, onCopy))
    act(() => {
      globalThis.dispatchEvent(new KeyboardEvent("keydown", { key: "c", ctrlKey: true }))
    })
    expect(onCopy).not.toHaveBeenCalled()
    act(() => {
      result.current.onPointerDown(1, withCtrl)
    })
    act(() => {
      globalThis.dispatchEvent(new KeyboardEvent("keydown", { key: "c", ctrlKey: true }))
    })
    expect(onCopy).toHaveBeenCalledOnce()
  })
})

describe("rows leaving the timeline", () => {
  it("drops picks the filter or the ring buffer has taken away", () => {
    const { result, rerender } = renderHook(
      ({ shown }: { shown: TimelineRow[] }) => useReactotronSelection(shown, onCopy),
      { initialProps: { shown: rows } },
    )
    act(() => {
      result.current.onPointerDown(1, withCtrl)
    })
    act(() => {
      result.current.onPointerDown(3, withCtrl)
    })
    rerender({ shown: [rows[2] as TimelineRow] })
    expect(result.current.count).toBe(1)
    expect(result.current.has(3)).toBe(true)
  })
})
