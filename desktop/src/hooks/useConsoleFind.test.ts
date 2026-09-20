import { act, renderHook } from "@testing-library/react"
import { describe, expect, it } from "vitest"

import type { ConsoleRow } from "@/lib/console-feed"
import { useConsoleFind } from "@/hooks/useConsoleFind"

function row(id: number, text: string): ConsoleRow {
  return {
    id,
    level: "info",
    type: "log",
    args: [],
    text,
    timestamp: 0,
    source: null,
    local: false,
  }
}

const rows = [row(1, "loading user"), row(2, "boom"), row(3, "User saved")]

function pressFindKey() {
  act(() => {
    globalThis.dispatchEvent(
      new KeyboardEvent("keydown", { key: "f", ctrlKey: true, metaKey: false, bubbles: true }),
    )
  })
}

describe("the find shortcut", () => {
  it("opens the bar while this tab is the one on screen", () => {
    const { result } = renderHook(() => useConsoleFind(rows, true))
    expect(result.current.open).toBe(false)
    pressFindKey()
    expect(result.current.open).toBe(true)
  })

  it("is ignored by a tab that is only kept alive", () => {
    // Every open tab stays mounted, so without this a hidden console wins the
    // key and opens a find bar nobody can see — the Mac gates ⌘F on
    // `activeTabID` for the same reason.
    const { result } = renderHook(() => useConsoleFind(rows, false))
    pressFindKey()
    expect(result.current.open).toBe(false)
  })

  it("stops listening once the tab goes to the background", () => {
    const { result, rerender } = renderHook(
      ({ active }: { active: boolean }) => useConsoleFind(rows, active),
      { initialProps: { active: true } },
    )
    rerender({ active: false })
    pressFindKey()
    expect(result.current.open).toBe(false)
  })
})

describe("stepping through matches", () => {
  it("counts what the query found", () => {
    const { result } = renderHook(() => useConsoleFind(rows, true))
    act(() => {
      result.current.setQuery("user")
    })
    expect(result.current.count).toBe("1 of 2")
    expect(result.current.current).toBe(1)
  })

  it("walks forward and wraps", () => {
    const { result } = renderHook(() => useConsoleFind(rows, true))
    act(() => {
      result.current.setQuery("user")
    })
    act(() => {
      result.current.next()
    })
    expect(result.current.current).toBe(3)
    act(() => {
      result.current.next()
    })
    expect(result.current.current).toBe(1)
  })

  it("goes back to the first match when the query changes", () => {
    // The matches are a different set now; keeping the position would land on
    // an unrelated row.
    const { result } = renderHook(() => useConsoleFind(rows, true))
    act(() => {
      result.current.setQuery("user")
    })
    act(() => {
      result.current.next()
    })
    act(() => {
      result.current.setQuery("us")
    })
    expect(result.current.count).toBe("1 of 2")
  })

  it("closing clears the query, so reopening is not a stale search", () => {
    const { result } = renderHook(() => useConsoleFind(rows, true))
    act(() => {
      result.current.setQuery("user")
    })
    act(() => {
      result.current.close()
    })
    expect(result.current.open).toBe(false)
    expect(result.current.query).toBe("")
    expect(result.current.current).toBeNull()
  })
})
