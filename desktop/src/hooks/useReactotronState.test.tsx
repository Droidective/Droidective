import { act, renderHook } from "@testing-library/react"
import { beforeEach, describe, expect, it, vi } from "vitest"
import { useReactotronState } from "@/hooks/useReactotronState"
import type { TimelineRow } from "@/lib/reactotron-rows"

const send = vi.hoisted(() => vi.fn())
vi.mock("@/lib/daemon", () => ({ reactotronSend: send }))

/**
 * The hook against a fake timeline.
 *
 * What is worth testing here is the join the protocol does not make for us: a
 * request goes out on one channel and the answer arrives as an ordinary row on
 * another, so nothing but this hook knows they belong together.
 */
function row(id: number, type: string, payload: unknown): TimelineRow {
  return {
    id,
    event: { kind: "log" } as TimelineRow["event"],
    command: { type, payload } as TimelineRow["command"],
    connection: 1,
    important: false,
    bytes: 0,
    receivedAt: 1000 + id,
    searchText: "",
  }
}

describe("useReactotronState", () => {
  beforeEach(() => {
    send.mockReset()
    send.mockResolvedValue({ delivered: 1 })
  })

  it("asks both ways for the store", () => {
    const { result } = renderHook(({ rows }) => useReactotronState(rows), {
      initialProps: { rows: [] as TimelineRow[] },
    })
    act(() => {
      result.current.loadTree()
    })
    expect(send.mock.calls.map((call) => call[0])).toEqual([
      "state.values.request",
      "state.backup.request",
    ])
  })

  it("takes the tree from a reply that arrives on the timeline", () => {
    const { result, rerender } = renderHook(({ rows }) => useReactotronState(rows), {
      initialProps: { rows: [] as TimelineRow[] },
    })
    act(() => {
      result.current.loadTree()
    })
    rerender({ rows: [row(1, "state.values.response", { value: { user: { name: "Ada" } } })] })
    expect(result.current.tree).toEqual({ user: { name: "Ada" } })
    expect(result.current.loadingTree).toBe(false)
  })

  /**
   * The one ambiguity in the protocol: `state.backup.response` answers both
   * "load the tree" and "take a snapshot", and only the asker knows which.
   */
  it("reads a backup as the tree, unless a snapshot was asked for", () => {
    const { result, rerender } = renderHook(({ rows }) => useReactotronState(rows), {
      initialProps: { rows: [] as TimelineRow[] },
    })
    act(() => {
      result.current.loadTree()
    })
    rerender({ rows: [row(1, "state.backup.response", { state: { a: 1 } })] })
    expect(result.current.tree).toEqual({ a: 1 })
    expect(result.current.snapshots).toHaveLength(0)

    act(() => {
      result.current.snapshot()
    })
    rerender({ rows: [
      row(1, "state.backup.response", { state: { a: 1 } }),
      row(2, "state.backup.response", { state: { a: 2 } }),
    ] })
    expect(result.current.snapshots).toHaveLength(1)
    expect(result.current.snapshots[0]?.state).toEqual({ a: 2 })
    // The tree is untouched: that reply belonged to the snapshot.
    expect(result.current.tree).toEqual({ a: 1 })
  })

  it("does not replay rows it has already folded in", () => {
    // The feed hands back a new array on every flush. Re-reading it would add
    // the same snapshot again on each render.
    const { result, rerender } = renderHook(({ rows }) => useReactotronState(rows), {
      initialProps: { rows: [] as TimelineRow[] },
    })
    act(() => {
      result.current.snapshot()
    })
    const rows = [row(1, "state.backup.response", { state: { a: 1 } })]
    rerender({ rows })
    rerender({ rows: [...rows] })
    expect(result.current.snapshots).toHaveLength(1)
  })

})

describe("useReactotronState — watching and dispatching", () => {
  beforeEach(() => {
    send.mockReset()
    send.mockResolvedValue({ delivered: 1 })
  })

  it("sends the whole watch list when one is added, then when one is removed", () => {
    const { result } = renderHook(({ rows }) => useReactotronState(rows), {
      initialProps: { rows: [] as TimelineRow[] },
    })
    act(() => {
      result.current.addWatch("user.name")
    })
    act(() => {
      result.current.addWatch("cart.total")
    })
    // Two arguments: the wrapper supplies the connection default, not the hook.
    expect(send.mock.calls.at(-1)).toEqual([
      "state.values.subscribe",
      { paths: ["user.name", "cart.total"] },
    ])

    act(() => {
      result.current.removeWatch("user.name")
    })
    expect(send.mock.calls.at(-1)).toEqual([
      "state.values.subscribe",
      { paths: ["cart.total"] },
    ])
    expect(result.current.watches.map((watch) => watch.path)).toEqual(["cart.total"])
  })

  it("updates a watched value from a change event", () => {
    const { result, rerender } = renderHook(({ rows }) => useReactotronState(rows), {
      initialProps: { rows: [] as TimelineRow[] },
    })
    act(() => {
      result.current.addWatch("user.name")
    })
    rerender({ rows: [
      row(1, "state.values.change", { changes: [{ path: "user.name", value: "Ada" }] }),
    ] })
    expect(result.current.watches[0]?.value).toBe("Ada")
  })

  it("refuses an action that is not an action, without sending anything", () => {
    const { result } = renderHook(({ rows }) => useReactotronState(rows), {
      initialProps: { rows: [] as TimelineRow[] },
    })
    act(() => {
      result.current.dispatch("not json")
    })
    expect(send).not.toHaveBeenCalled()
    expect(result.current.notice).toBe("Invalid action JSON")
  })

  it("says so when nothing is connected, rather than looking like it worked", () => {
    send.mockResolvedValue({ delivered: 0 })
    const { result } = renderHook(({ rows }) => useReactotronState(rows), {
      initialProps: { rows: [] as TimelineRow[] },
    })
    return act(async () => {
      result.current.dispatch('{ "type": "INCREMENT" }')
      await Promise.resolve()
    }).then(() => {
      expect(result.current.notice).toBe("No app is connected.")
    })
  })
})
