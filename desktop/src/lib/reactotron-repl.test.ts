import { describe, expect, it } from "vitest"
import { evaluate, listReplNames, readReplEvent } from "@/lib/reactotron-repl"

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
