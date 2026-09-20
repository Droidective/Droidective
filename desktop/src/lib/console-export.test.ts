import { describe, expect, it } from "vitest"

import { consoleJson, exportFileName, exportType } from "@/lib/console-export"
import type { ConsoleRow } from "@/lib/console-feed"
import type { RemoteObject } from "@/lib/cdp"

const value = { type: "string", value: "x" } as unknown as RemoteObject

function row(over: Partial<ConsoleRow> = {}): ConsoleRow {
  return {
    id: 1,
    level: "info",
    type: "log",
    args: [],
    text: "hello",
    timestamp: Date.UTC(2026, 8, 20, 12, 30, 45, 123),
    source: null,
    local: false,
    ...over,
  }
}

describe("exportType", () => {
  it("calls an app's console line a log", () => {
    expect(exportType(row())).toBe("log")
  })

  it("calls a thrown exception an error", () => {
    expect(exportType(row({ type: "error", level: "error" }))).toBe("error")
  })

  it("calls the prompt echo an input", () => {
    // `localRow` writes the echo with a leading U+203A, which is the only thing
    // separating it from a notice this app wrote.
    expect(exportType(row({ local: true, text: "› store.getState()" }))).toBe("input")
  })

  it("calls an evaluated value a result", () => {
    expect(exportType(row({ local: true, args: [value] }))).toBe("result")
  })

  it("calls a connection message a notice", () => {
    expect(exportType(row({ local: true, text: "Connected to Hermes" }))).toBe("notice")
  })

  it("does not mistake an app's own line starting with the echo mark", () => {
    // The marker only means input on a row this app wrote; an app is free to
    // log one.
    expect(exportType(row({ local: false, text: "› from the app" }))).toBe("log")
  })
})

describe("consoleJson", () => {
  it("writes the Mac's four keys in sorted order", () => {
    const written = consoleJson([row()])
    expect(JSON.parse(written)).toEqual([
      { level: "info", text: "hello", timestamp: "2026-09-20T12:30:45.123Z", type: "log" },
    ])
    // Sorted keys, as `JSONEncoder.sortedKeys` writes them — so a dump from
    // either app diffs against the other.
    expect(Object.keys(JSON.parse(written)[0])).toEqual(["level", "text", "timestamp", "type"])
  })

  it("omits level for an entry that has none, rather than writing null", () => {
    const [entry] = JSON.parse(consoleJson([row({ local: true, text: "› 1 + 1" })]))
    expect("level" in entry).toBe(false)
    expect(entry.type).toBe("input")
  })

  it("keeps fractional seconds, since a burst lands inside one second", () => {
    const [entry] = JSON.parse(consoleJson([row()]))
    expect(entry.timestamp).toBe("2026-09-20T12:30:45.123Z")
  })

  it("keeps the order it was given", () => {
    const written = JSON.parse(consoleJson([row({ text: "first" }), row({ text: "second" })]))
    expect(written.map((one: { text: string }) => one.text)).toEqual(["first", "second"])
  })

  it("writes an empty array for an empty feed rather than failing", () => {
    expect(JSON.parse(consoleJson([]))).toEqual([])
  })
})

describe("exportFileName", () => {
  it("stamps like ScreenCaptureService, so both apps' files sort as one set", () => {
    // Local time, `yyyy-MM-dd_HH-mm-ss`, which is what the Mac writes.
    const name = exportFileName(new Date(2026, 8, 20, 9, 5, 3))
    expect(name).toBe("js-console_2026-09-20_09-05-03.json")
  })
})
