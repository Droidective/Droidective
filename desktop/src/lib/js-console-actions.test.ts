import { describe, expect, it } from "vitest"

import { consoleRestartTarget, reloadMessage, reloadStep } from "@/lib/js-console-actions"

describe("reloadStep", () => {
  it("is done when the runtime accepted Page.reload", () => {
    expect(reloadStep(null)).toBe("done")
  })

  it("falls back when the runtime refused the method", () => {
    // Hermes answers method-not-found on releases that do not implement it,
    // which is the case the device-side reload keys exist for.
    expect(reloadStep({ code: -32601, message: "Method not found" })).toBe("fall-back")
  })

  it("falls back on any other protocol error, not just method-not-found", () => {
    // Deliberately not a check for one code: the Mac treats every refusal the
    // same, and a console that only handled -32601 would leave the bundle
    // unreloaded for every other reason with nothing said.
    expect(reloadStep({ code: -32000, message: "Not attached" })).toBe("fall-back")
  })

  it("falls back when nothing answered at all", () => {
    // A silent runtime and a missing one are indistinguishable from here, and
    // leaving the bundle unreloaded is the worse of the two answers.
    expect(reloadStep({ code: 0, message: "The runtime did not answer." })).toBe("fall-back")
  })
})

describe("reloadMessage", () => {
  it("reports the reload when the runtime took it", () => {
    expect(reloadMessage("done", null)).toContain("Reloading")
  })

  it("says the device was used instead, so a backgrounded app explains itself", () => {
    const message = reloadMessage("fall-back", { ok: true })
    expect(message).toContain("Page.reload")
    expect(message).toContain("device")
  })

  it("reports both halves failing rather than only the second", () => {
    const message = reloadMessage("fall-back", { ok: false })
    expect(message).toContain("refused")
    expect(message).toContain("reload keys")
  })

  it("does not claim a device fallback when there was no device", () => {
    expect(reloadMessage("fall-back", null)).not.toContain("device instead")
  })
})

describe("consoleRestartTarget", () => {
  it("takes the application id Metro reported", () => {
    expect(consoleRestartTarget("com.example.app")).toEqual({
      kind: "package",
      packageId: "com.example.app",
    })
  })

  it("asks when nothing is connected", () => {
    // Guessing from the foreground app would restart whatever happens to be in
    // front, which is not the app under debug.
    expect(consoleRestartTarget(null)).toEqual({ kind: "ask", reason: "no-client" })
  })

  it("treats a blank appId as nothing reported", () => {
    // Metro's placeholder entries carry an empty id, and a restart aimed at ""
    // is a `pm` call that fails for a reason nobody can read.
    expect(consoleRestartTarget("   ")).toEqual({ kind: "ask", reason: "no-client" })
  })

  it("trims what it was given", () => {
    expect(consoleRestartTarget(" com.example.app ")).toEqual({
      kind: "package",
      packageId: "com.example.app",
    })
  })
})
