import { renderHook, act } from "@testing-library/react"
import { describe, expect, it } from "vitest"

import { useLatestRequest } from "@/hooks/useLatestRequest"

describe("useLatestRequest", () => {
  it("keeps an answer to the question still being asked", () => {
    const { result } = renderHook(() => useLatestRequest())
    const current = result.current.begin()
    expect(current()).toBe(true)
  })

  it("drops an answer to a question that has moved on", () => {
    const { result } = renderHook(() => useLatestRequest())
    const forDeviceA = result.current.begin()
    act(() => {
      result.current.restart()
    })
    expect(forDeviceA()).toBe(false)
  })

  /** Two loads in flight at once: only the newest may write. */
  it("keeps only the newest of several in-flight requests", () => {
    const { result } = renderHook(() => useLatestRequest())
    const first = result.current.begin()
    act(() => {
      result.current.restart()
    })
    const second = result.current.begin()
    expect(first()).toBe(false)
    expect(second()).toBe(true)
  })

  /** Two requests started for the same question both stand — a refresh
   * racing its own initial load is not a stale answer. */
  it("keeps both tokens taken for the same question", () => {
    const { result } = renderHook(() => useLatestRequest())
    const load = result.current.begin()
    const refresh = result.current.begin()
    expect(load()).toBe(true)
    expect(refresh()).toBe(true)
  })

  /** It lives in dependency arrays, so a new identity every render would
   * re-run the very effects it guards. */
  it("is stable across renders", () => {
    const { result, rerender } = renderHook(() => useLatestRequest())
    const first = result.current
    rerender()
    expect(result.current).toBe(first)
  })

  it("survives more restarts than a session could produce", () => {
    const { result } = renderHook(() => useLatestRequest())
    const stale = result.current.begin()
    act(() => {
      for (let i = 0; i < 1000; i += 1) result.current.restart()
    })
    expect(stale()).toBe(false)
    expect(result.current.begin()()).toBe(true)
  })
})
