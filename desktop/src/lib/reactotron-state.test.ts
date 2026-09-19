import { describe, expect, it } from "vitest"
import {
  applyChanges,
  evaluate,
  listReplNames,
  readReplEvent,
  dispatchAction,
  loadStateTree,
  parseAction,
  readStateEvent,
  restoreSnapshot,
  subscribeTo,
  takeSnapshot,
  withoutWatch,
  withWatch,
  type Watch,
} from "@/lib/reactotron-state"

describe("what the pane sends", () => {
  /// Upstream's shape, not belt and braces: redux answers the backup request,
  /// mst the values one, and an app has only one of the two plugins.
  it("asks two ways for the store, because the plugins differ", () => {
    expect(loadStateTree()).toEqual([
      { kind: "state.values.request", payload: {} },
      { kind: "state.backup.request", payload: {} },
    ])
  })

  it("sends the whole watch list, because subscribe replaces rather than adds", () => {
    // The trap this guards: sending only the new path silently stops watching
    // everything already on screen.
    expect(subscribeTo(["user.name", "cart.total"])).toEqual({
      kind: "state.values.subscribe",
      payload: { paths: ["user.name", "cart.total"] },
    })
  })

  it("takes a snapshot and restores one", () => {
    expect(takeSnapshot()).toEqual({ kind: "state.backup.request", payload: {} })
    expect(restoreSnapshot({ a: 1 })).toEqual({
      kind: "state.restore.request",
      payload: { state: { a: 1 } },
    })
  })

  it("wraps a dispatched action the way the client expects", () => {
    expect(dispatchAction({ type: "INCREMENT" })).toEqual({
      kind: "state.action.dispatch",
      payload: { action: { type: "INCREMENT" } },
    })
  })
})

describe("the watch list", () => {
  it("adds a trimmed path", () => {
    expect(withWatch([], "  user.name  ")).toEqual(["user.name"])
  })

  it("refuses a blank or a duplicate, so no round trip happens", () => {
    // Null rather than the unchanged list: the caller skips the send.
    expect(withWatch([], "   ")).toBeNull()
    expect(withWatch(["user.name"], "user.name")).toBeNull()
  })

  it("removes one and leaves the order alone", () => {
    expect(withoutWatch(["a", "b", "c"], "b")).toEqual(["a", "c"])
  })
})

describe("parseAction", () => {
  it("takes an object with a type", () => {
    const parsed = parseAction('{ "type": "INCREMENT", "by": 2 }')
    expect(parsed).toEqual({ ok: true, action: { type: "INCREMENT", by: 2 } })
  })

  it("refuses what JSON.parse accepts but a store does not", () => {
    // Each of these parses cleanly and then fails inside the app, where the
    // failure is a red screen rather than a line in this pane.
    expect(parseAction('"INCREMENT"').ok).toBe(false)
    expect(parseAction("[1, 2]").ok).toBe(false)
    expect(parseAction('{ "by": 2 }').ok).toBe(false)
  })

  it("says which way it was wrong", () => {
    expect(parseAction("{").ok).toBe(false)
    const broken = parseAction("{")
    expect(broken.ok ? "" : broken.reason).toBe("Invalid action JSON")
    const empty = parseAction("  ")
    expect(empty.ok ? "" : empty.reason).toBe("Enter an action first.")
  })
})

describe("reading what comes back", () => {
  it("takes the whole tree from either plugin's answer", () => {
    expect(readStateEvent("state.keys.response", { value: { a: 1 } }))
      .toEqual({ kind: "tree", state: { a: 1 } })
    expect(readStateEvent("state.values.response", { value: { a: 1 } }))
      .toEqual({ kind: "tree", state: { a: 1 } })
  })

  it("reads a backup under either key upstream has used", () => {
    expect(readStateEvent("state.backup.response", { state: { a: 1 } }))
      .toEqual({ kind: "backup", state: { a: 1 } })
    expect(readStateEvent("state.backup.response", { value: { a: 1 } }))
      .toEqual({ kind: "backup", state: { a: 1 } })
  })

  it("reads subscription changes", () => {
    expect(readStateEvent("state.values.change", {
      changes: [{ path: "user.name", value: "Ada" }],
    })).toEqual({ kind: "values", changes: [{ path: "user.name", value: "Ada" }] })
  })

  it("ignores everything else on the timeline", () => {
    // The pane watches the same feed the log rows come from, so most of what
    // arrives is not an answer to anything it asked.
    expect(readStateEvent("log", { message: "hi" })).toBeNull()
    expect(readStateEvent("state.values.change", { changes: [] })).toBeNull()
    expect(readStateEvent("state.keys.response", {})).toBeNull()
    expect(readStateEvent("state.values.response", "not an object")).toBeNull()
  })

  it("keeps a change with a null value, which is a real value", () => {
    expect(readStateEvent("state.values.change", {
      changes: [{ path: "user.name", value: null }],
    })).toEqual({ kind: "values", changes: [{ path: "user.name", value: null }] })
  })
})

describe("applyChanges", () => {
  const watches: Watch[] = [
    { path: "user.name", value: "Ada", at: 1 },
    { path: "cart.total", value: 0, at: null },
  ]

  it("updates only the paths that changed, in place", () => {
    const next = applyChanges(watches, [{ path: "cart.total", value: 42 }], 99)
    expect(next).toEqual([
      { path: "user.name", value: "Ada", at: 1 },
      { path: "cart.total", value: 42, at: 99 },
    ])
  })

  it("ignores a change for a path nobody is watching", () => {
    // The client answers with whatever it was last told to watch, which can lag
    // a removal by one message.
    expect(applyChanges(watches, [{ path: "gone", value: 1 }], 99)).toEqual(watches)
  })
})

describe("the REPL", () => {
  it("lists what the app registered", () => {
    expect(listReplNames()).toEqual({ kind: "repl.ls", payload: null })
  })

  it("sends the expression as a bare string, which is what the client reads", () => {
    // `repl.execute` is the one state command whose payload is not a wrapper.
    // Sending `{ code }` is evaluated as nothing, silently.
    expect(evaluate("  store.getState()  ")).toEqual({
      kind: "repl.execute",
      payload: "store.getState()",
    })
  })

  it("reads the names back", () => {
    expect(readReplEvent("repl.ls.response", ["store", "api"]))
      .toEqual({ kind: "names", names: ["store", "api"] })
  })

  it("prints undefined rather than nothing, so a run is distinguishable", () => {
    // An expression returning nothing still ran; a blank panel cannot say which
    // of the two happened.
    expect(readReplEvent("repl.execute.response", null)).toEqual({
      kind: "result",
      text: "undefined",
    })
  })

  it("pretty-prints a value", () => {
    expect(readReplEvent("repl.execute.response", { a: 1 })).toEqual({
      kind: "result",
      text: '{\n  "a": 1\n}',
    })
  })

  it("ignores anything that is not a REPL reply", () => {
    expect(readReplEvent("log", {})).toBeNull()
    expect(readReplEvent("repl.ls.response", "not a list")).toBeNull()
  })
})
