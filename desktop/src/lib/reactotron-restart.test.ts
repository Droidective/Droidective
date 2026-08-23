import { describe, expect, it } from "vitest"
import {
  clearAction,
  restartMessage,
  restartTarget,
  type TargetInputs,
} from "@/lib/reactotron-restart"

const installed = ["com.streamlab", "com.acme.myapp", "com.android.launcher3", "com.example.shop"]

function inputs(over: Partial<TargetInputs> = {}): TargetInputs {
  return { clientName: "StreamLab", installed, foreground: null, ...over }
}

describe("restartTarget", () => {
  it("takes the connected client's own name first", () => {
    // The only signal that names the app actually talking to us.
    expect(restartTarget(inputs())).toEqual({ kind: "package", packageId: "com.streamlab" })
  })

  it("asks when no client is connected, whatever is in front", () => {
    // With nothing connected the foreground app could be anything, and
    // restarting whatever happens to be open is worse than a question.
    expect(restartTarget(inputs({ clientName: null, foreground: "com.acme.myapp" }))).toEqual({
      kind: "ask",
      reason: "no-client",
    })
    expect(restartTarget(inputs({ clientName: "   " }))).toMatchObject({ reason: "no-client" })
  })

  it("falls back to the foreground app when the client's name matches nothing", () => {
    expect(
      restartTarget(inputs({ clientName: "Unrecognised", foreground: "com.acme.myapp" })),
    ).toEqual({ kind: "package", packageId: "com.acme.myapp" })
  })

  it("refuses a foreground package it cannot see installed", () => {
    // The device reported it; we have no listing for it. Acting on a name we
    // cannot corroborate is how the launcher gets its data cleared.
    expect(
      restartTarget(inputs({ clientName: "Unrecognised", foreground: "com.unknown.thing" })),
    ).toEqual({ kind: "ask", reason: "no-match" })
  })

  it("asks rather than guessing when nothing matches at all", () => {
    expect(restartTarget(inputs({ clientName: "Unrecognised" }))).toEqual({
      kind: "ask",
      reason: "no-match",
    })
  })

  it("asks when the client's name is ambiguous", () => {
    // Two packages could be "shop"; the matcher refuses, and so does this.
    const ambiguous = [...installed, "org.other.shop"]
    expect(restartTarget(inputs({ clientName: "Shop", installed: ambiguous }))).toMatchObject({
      kind: "ask",
    })
  })
})

describe("clearAction", () => {
  it("names the adb verb for each scope", () => {
    expect(clearAction("cache")).toBe("clearCache")
    expect(clearAction("data")).toBe("clearData")
  })
})

describe("restartMessage", () => {
  it("says only what happened when nothing was wiped", () => {
    expect(restartMessage({ packageId: "com.x", scope: null, cleared: true })).toBe(
      "Restarting com.x…",
    )
  })

  it("admits a clear that did not finish rather than claiming it did", () => {
    // A failed clear is reported, not fatal: the restart proceeds either way,
    // and someone who asked for a clean start deserves to know they did not get
    // one.
    expect(restartMessage({ packageId: "com.x", scope: "cache", cleared: false })).toBe(
      "Cache clear didn't finish — restarting com.x…",
    )
    expect(restartMessage({ packageId: "com.x", scope: "data", cleared: false })).toBe(
      "Data clear failed — restarting com.x…",
    )
  })

  it("confirms a clear that worked", () => {
    expect(restartMessage({ packageId: "com.x", scope: "cache", cleared: true })).toBe(
      "Cleared cache — restarting com.x…",
    )
    expect(restartMessage({ packageId: "com.x", scope: "data", cleared: true })).toBe(
      "Cleared data — restarting com.x…",
    )
  })

  it("distinguishes the two scopes' wording", () => {
    // "didn't finish" for a cache clear that hit its timeout; "failed" for a
    // data clear, which returns reliably and so genuinely refused.
    const cache = restartMessage({ packageId: "com.x", scope: "cache", cleared: false })
    const data = restartMessage({ packageId: "com.x", scope: "data", cleared: false })
    expect(cache).not.toBe(data)
  })
})
