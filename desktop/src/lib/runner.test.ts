import { describe, expect, it } from "vitest"
import { runOnTargets, type RunOne } from "@/lib/runner"
import type { RunResponse } from "@/lib/wire"

function reply(overrides: Partial<RunResponse> = {}): RunResponse {
  return {
    ok: true,
    message: "Sent",
    copyText: null,
    revealPath: null,
    needsAdbKeyboard: false,
    ...overrides,
  }
}

/** Records what it was asked to run, and answers per serial. */
function runner(answers: Record<string, RunResponse> = {}) {
  const calls: string[] = []
  // Not `async`: it hands back a resolved promise so it satisfies `RunOne`
  // without an await to wait for.
  const run: RunOne = (args) => {
    calls.push(args.serial)
    return Promise.resolve(answers[args.serial] ?? reply())
  }
  return { run, calls }
}

const request = { featureId: "send-text", platform: "android", fields: { text: "hi" } }

describe("runOnTargets", () => {
  it("runs on each target, in order", async () => {
    const { run, calls } = runner()
    await runOnTargets(run, { ...request, serials: ["A", "B", "C"] })
    // Order matters: the selected device leads the list, so its result is the
    // one that arrives first.
    expect(calls).toEqual(["A", "B", "C"])
  })

  it("hands back one device's own reply untouched", async () => {
    const { run } = runner({
      A: reply({ message: "Copied 10.0.0.5", copyText: "10.0.0.5", needsAdbKeyboard: true }),
    })
    expect(await runOnTargets(run, { ...request, serials: ["A"] })).toEqual(
      reply({ message: "Copied 10.0.0.5", copyText: "10.0.0.5", needsAdbKeyboard: true }),
    )
  })

  it("collapses several into one line and drops the extras", async () => {
    // A copyable value from whichever device answered first would be a value
    // for a device nobody asked about.
    const { run } = runner({
      A: reply({ copyText: "10.0.0.5", revealPath: "/tmp/a.png" }),
      B: reply({ copyText: "10.0.0.6", revealPath: "/tmp/b.png" }),
    })
    const result = await runOnTargets(run, { ...request, serials: ["A", "B"] })
    expect(result).toEqual(
      reply({ message: "Ran on 2 devices", copyText: null, revealPath: null }),
    )
  })

  it("reports which devices failed", async () => {
    const { run } = runner({ B: reply({ ok: false, message: "closed" }) })
    const result = await runOnTargets(run, { ...request, serials: ["A", "B"] })
    expect(result?.ok).toBe(false)
    expect(result?.message).toBe("Ran on 1 of 2 — failed on B")
  })

  it("carries the keyboard hint if any device needed it", async () => {
    // The instruction is the same for all of them, and only has to be said once.
    const { run } = runner({ B: reply({ needsAdbKeyboard: true }) })
    const result = await runOnTargets(run, { ...request, serials: ["A", "B"] })
    expect(result?.needsAdbKeyboard).toBe(true)
  })

  it("answers nothing when there was nothing to run on", async () => {
    const { run, calls } = runner()
    expect(await runOnTargets(run, { ...request, serials: [] })).toBeNull()
    expect(calls).toEqual([])
  })

  it("omits fields entirely when there are none", async () => {
    // `runFields` answers undefined for a feature with no parameters, and the
    // daemon must see "not given" rather than an empty object.
    const seen: (Record<string, unknown> | undefined)[] = []
    const run: RunOne = (args) => {
      seen.push(args.fields)
      return Promise.resolve(reply())
    }
    await runOnTargets(run, { ...request, fields: undefined, serials: ["A"] })
    expect(seen).toEqual([undefined])
  })
})
