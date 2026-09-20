import { act, renderHook } from "@testing-library/react"
import { beforeEach, describe, expect, it, vi } from "vitest"

import type { ConsoleRow } from "@/lib/console-feed"

const { copyText, show } = vi.hoisted(() => ({
  copyText: vi.fn((_text: string) => Promise.resolve()),
  show: vi.fn(),
}))

vi.mock("@/lib/daemon", () => ({
  copyText,
  asDaemonError: (thrown: unknown) => ({ code: "unknown", message: String(thrown), detail: null }),
}))
vi.mock("@/hooks/useNotifications", () => ({ useNotifications: () => ({ show }) }))

const { useConsoleSelection } = await import("@/hooks/useConsoleSelection")

function row(id: number, text: string): ConsoleRow {
  return {
    id,
    level: "info",
    type: "log",
    args: [],
    text,
    timestamp: Date.UTC(2026, 8, 20, 12, 0, 0, 0),
    source: null,
    local: false,
  }
}

const rows = [row(1, "one"), row(2, "two"), row(3, "three"), row(4, "four")]

const plain = { ctrlKey: false, metaKey: false, shiftKey: false }
const withCtrl = { ctrlKey: true, metaKey: false, shiftKey: false }
const withShift = { ctrlKey: false, metaKey: false, shiftKey: true }

beforeEach(() => {
  copyText.mockClear()
  show.mockClear()
})

describe("picking rows", () => {
  it("does not select on a plain click — that is how you clear", () => {
    // The Mac's rule: a row is something you click to read, so selection is
    // the deliberate gesture.
    const { result } = renderHook(() => useConsoleSelection(rows))
    act(() => {
      result.current.onPointerDown(2, plain)
    })
    expect(result.current.count).toBe(0)
  })

  it("picks one on Ctrl-click and drops it again", () => {
    const { result } = renderHook(() => useConsoleSelection(rows))
    act(() => {
      result.current.onPointerDown(2, withCtrl)
    })
    expect(result.current.count).toBe(1)
    act(() => {
      result.current.onPointerDown(2, withCtrl)
    })
    expect(result.current.count).toBe(0)
  })

  it("spans on Shift-click from what was last touched", () => {
    const { result } = renderHook(() => useConsoleSelection(rows))
    act(() => {
      result.current.onPointerDown(1, withCtrl)
    })
    act(() => {
      result.current.onPointerDown(3, withShift)
    })
    expect(result.current.count).toBe(3)
    expect(result.current.has(2)).toBe(true)
  })

  it("clears on a plain click once something is picked", () => {
    const { result } = renderHook(() => useConsoleSelection(rows))
    act(() => {
      result.current.onPointerDown(2, withCtrl)
    })
    act(() => {
      result.current.onPointerDown(4, plain)
    })
    expect(result.current.count).toBe(0)
  })
})

describe("dragging", () => {
  it("ignores the row the pointer went down on, so a click is still a click", () => {
    const { result } = renderHook(() => useConsoleSelection(rows))
    act(() => {
      result.current.onPointerDown(2, plain)
    })
    act(() => {
      result.current.onPointerEnter(2)
    })
    expect(result.current.count).toBe(0)
  })

  it("sweeps a range once the pointer leaves that row", () => {
    const { result } = renderHook(() => useConsoleSelection(rows))
    act(() => {
      result.current.onPointerDown(2, plain)
    })
    act(() => {
      result.current.onPointerEnter(4)
    })
    expect(result.current.count).toBe(3)
    expect(result.current.dragging).toBe(true)
  })

  it("shrinks again when the pointer comes back", () => {
    const { result } = renderHook(() => useConsoleSelection(rows))
    act(() => {
      result.current.onPointerDown(1, plain)
    })
    act(() => {
      result.current.onPointerEnter(4)
    })
    act(() => {
      result.current.onPointerEnter(2)
    })
    expect(result.current.count).toBe(2)
  })

  it("stops dragging wherever the button comes up", () => {
    const { result } = renderHook(() => useConsoleSelection(rows))
    act(() => {
      result.current.onPointerDown(1, plain)
    })
    act(() => {
      result.current.onPointerEnter(3)
    })
    act(() => {
      globalThis.dispatchEvent(new Event("pointerup"))
    })
    expect(result.current.dragging).toBe(false)
    // And the sweep survives the release.
    expect(result.current.count).toBe(3)
  })

  it("does not clear on the click that ends a sweep", () => {
    // The pointer-down that starts the next gesture arrives with no modifier;
    // without the guard it would throw the sweep away immediately.
    const { result } = renderHook(() => useConsoleSelection(rows))
    act(() => {
      result.current.onPointerDown(1, plain)
    })
    act(() => {
      result.current.onPointerEnter(3)
    })
    act(() => {
      globalThis.dispatchEvent(new Event("pointerup"))
    })
    act(() => {
      result.current.onPointerDown(3, plain)
    })
    expect(result.current.count).toBe(3)
  })
})

describe("rows leaving the feed", () => {
  it("drops picks the reader can no longer see", () => {
    // Trimmed, filtered out or cleared — a selection that kept them would
    // count and copy events that are not on screen.
    const { result, rerender } = renderHook(
      ({ shown }: { shown: ConsoleRow[] }) => useConsoleSelection(shown),
      { initialProps: { shown: rows } },
    )
    act(() => {
      result.current.onPointerDown(1, withCtrl)
    })
    act(() => {
      result.current.onPointerDown(4, withCtrl)
    })
    expect(result.current.count).toBe(2)
    rerender({ shown: [rows[2] as ConsoleRow, rows[3] as ConsoleRow] })
    expect(result.current.count).toBe(1)
    expect(result.current.has(4)).toBe(true)
  })
})

describe("copying", () => {
  it("copies the picked rows as text, newest-last and blank-line separated", () => {
    const { result } = renderHook(() => useConsoleSelection(rows))
    act(() => {
      result.current.onPointerDown(1, withCtrl)
    })
    act(() => {
      result.current.onPointerDown(3, withCtrl)
    })
    act(() => {
      result.current.copy()
    })
    const written = copyText.mock.calls[0]?.[0] ?? ""
    expect(written).toContain("one")
    expect(written).toContain("three")
    expect(written).not.toContain("two")
    expect(written).toContain("\n\n")
  })

  it("copies as JSON in the export's shape", () => {
    const { result } = renderHook(() => useConsoleSelection(rows))
    act(() => {
      result.current.onPointerDown(2, withCtrl)
    })
    act(() => {
      result.current.copyAsJson()
    })
    const written = JSON.parse(copyText.mock.calls[0]?.[0] ?? "[]")
    expect(written).toHaveLength(1)
    expect(written[0]).toMatchObject({ text: "two", type: "log", level: "info" })
  })

  it("says how many went", async () => {
    const { result } = renderHook(() => useConsoleSelection(rows))
    act(() => {
      result.current.onPointerDown(2, withCtrl)
    })
    await act(async () => {
      result.current.copy()
      await Promise.resolve()
    })
    expect(show).toHaveBeenCalledWith({ message: "Copied 1 logs", ok: true })
  })

  it("does nothing with nothing picked", () => {
    const { result } = renderHook(() => useConsoleSelection(rows))
    act(() => {
      result.current.copy()
    })
    expect(copyText).not.toHaveBeenCalled()
  })
})

function pressCopy() {
  act(() => {
    globalThis.dispatchEvent(new KeyboardEvent("keydown", { key: "c", ctrlKey: true }))
  })
}

describe("the copy shortcut", () => {
  it("copies while rows are picked", () => {
    const { result } = renderHook(() => useConsoleSelection(rows))
    act(() => {
      result.current.onPointerDown(2, withCtrl)
    })
    pressCopy()
    expect(copyText).toHaveBeenCalledOnce()
  })

  it("stays out of the way while nothing is picked", () => {
    // Bound unconditionally it shadows copying text out of the prompt, the
    // filter, or a line highlighted with the mouse.
    renderHook(() => useConsoleSelection(rows))
    pressCopy()
    expect(copyText).not.toHaveBeenCalled()
  })
})
