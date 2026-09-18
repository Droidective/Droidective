import { describe, expect, it } from "vitest"
import { entryAsText, exitLabel, hasOutput, logAsText, succeeded, timeLabel } from "@/lib/commandlog"
import type { CommandLogEntry } from "@/lib/wire"

function entry(over: Partial<CommandLogEntry> = {}): CommandLogEntry {
  return {
    id: "1",
    at: Date.UTC(2026, 0, 2, 3, 4, 5),
    command: "adb -s emulator-5554 shell input text hi",
    exitCode: 0,
    durationMs: 12,
    stdout: "",
    stderr: "",
    ...over,
  }
}

describe("exitLabel", () => {
  it("reads as the Mac's row does", () => {
    expect(exitLabel(entry({ exitCode: 0, durationMs: 12 }))).toBe("exit 0 · 12ms")
  })

  it("says killed rather than inventing a code", () => {
    // A timed-out adb call has no exit code. Rendering it as 0 would claim the
    // command succeeded, which is the one thing the log must not do.
    expect(exitLabel(entry({ exitCode: null, durationMs: 30_000 }))).toBe("exit killed · 30000ms")
  })

  it("carries a non-zero code through", () => {
    expect(exitLabel(entry({ exitCode: 1, durationMs: 4 }))).toBe("exit 1 · 4ms")
  })
})

describe("succeeded", () => {
  it("is true only for exit 0", () => {
    expect(succeeded(entry({ exitCode: 0 }))).toBe(true)
    expect(succeeded(entry({ exitCode: 1 }))).toBe(false)
    // Killed is a failure, not an unknown: the Mac tints it red.
    expect(succeeded(entry({ exitCode: null }))).toBe(false)
  })
})

describe("hasOutput", () => {
  it("is false only when both streams are empty", () => {
    expect(hasOutput(entry())).toBe(false)
    expect(hasOutput(entry({ stdout: "ok" }))).toBe(true)
    expect(hasOutput(entry({ stderr: "boom" }))).toBe(true)
  })
})

describe("timeLabel", () => {
  it("formats as a local wall-clock time", () => {
    // Pinned to a fixed locale and a UTC instant so the assertion is about the
    // shape rather than about the machine running it.
    const label = timeLabel(Date.UTC(2026, 0, 2, 15, 4, 5), "en-GB")
    expect(label).toMatch(/^\d{2}:\d{2}:\d{2}$/u)
  })
})

describe("entryAsText", () => {
  it("leads with the time and the command, then the status", () => {
    const text = entryAsText(entry({ stdout: "", stderr: "" }), "en-GB")
    const lines = text.split("\n")
    expect(lines[0]).toContain("adb -s emulator-5554 shell input text hi")
    expect(lines[1]).toBe("exit 0 · 12ms")
  })

  it("includes both streams when there are both", () => {
    const text = entryAsText(entry({ stdout: "out\n", stderr: "err\n" }), "en-GB")
    expect(text).toContain("out")
    expect(text).toContain("err")
    // The trailing newline each stream carries would otherwise stack blank
    // lines between entries in a pasted report.
    expect(text.endsWith("err")).toBe(true)
  })

  it("omits an empty stream rather than leaving a blank block", () => {
    const text = entryAsText(entry({ stdout: "out" }), "en-GB")
    expect(text.split("\n").filter((line) => line === "").length).toBe(1)
  })
})

describe("logAsText", () => {
  it("keeps the order it was given, blank-line separated", () => {
    const text = logAsText(
      [entry({ id: "1", command: "adb devices" }), entry({ id: "2", command: "adb shell id" })],
      "en-GB",
    )
    expect(text.indexOf("adb devices")).toBeLessThan(text.indexOf("adb shell id"))
    expect(text).toContain("\n\n")
  })

  it("is empty for an empty log", () => {
    expect(logAsText([], "en-GB")).toBe("")
  })
})
