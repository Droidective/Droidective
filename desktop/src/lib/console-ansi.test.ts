/**
 * Escape-sequence stripping, against what React Native's dev server really
 * sends.
 *
 * The console rendered `ESC[48;2;253;247;231m…NOTE: …` verbatim before this
 * existed — found by opening the pane against a real app. The rules are
 * ADBKit's `ConsoleANSI`, including the one that matters most: an unterminated
 * escape is data, not a sequence, and must not swallow the rest of the line.
 */

import { describe, expect, it } from "vitest"

import { stripAnsi } from "@/lib/console-ansi"

const ESC = "\u001B"

describe("stripAnsi", () => {
  it("leaves text with no escapes exactly alone", () => {
    expect(stripAnsi("plain text")).toBe("plain text")
    expect(stripAnsi("")).toBe("")
  })

  it("removes the SGR colours Metro wraps its notices in", () => {
    // The real line, shortened: this is what rendered as visible gibberish.
    const raw =
      `${ESC}[48;2;253;247;231m${ESC}[30m${ESC}[1mNOTE: ` +
      `${ESC}[22mYou are using an unsupported debugging client.`
    expect(stripAnsi(raw)).toBe("NOTE: You are using an unsupported debugging client.")
  })

  it("removes a reset and a cursor move", () => {
    expect(stripAnsi(`${ESC}[0mhi${ESC}[2K`)).toBe("hi")
  })

  it("removes an OSC ending in BEL", () => {
    expect(stripAnsi(`${ESC}]0;a title\u0007after`)).toBe("after")
  })

  it("removes an OSC ending in the ST pair", () => {
    expect(stripAnsi(`${ESC}]8;;http://x${ESC}\\after`)).toBe("after")
  })

  it("removes the two-byte C1 forms", () => {
    expect(stripAnsi(`a${ESC}Db`)).toBe("ab")
  })

  it("keeps an unterminated CSI rather than swallowing the tail", () => {
    // A lone ESC in real data is data. Eating the rest of the line would hide
    // the message someone is looking for.
    expect(stripAnsi(`${ESC}[38;5`)).toBe(`${ESC}[38;5`)
  })

  it("keeps an unterminated OSC rather than swallowing the tail", () => {
    expect(stripAnsi(`${ESC}]0;no terminator`)).toBe(`${ESC}]0;no terminator`)
  })

  it("keeps a trailing lone escape", () => {
    expect(stripAnsi(`text${ESC}`)).toBe(`text${ESC}`)
  })

  it("keeps an escape followed by something that is no sequence at all", () => {
    expect(stripAnsi(`${ESC}~x`)).toBe(`${ESC}~x`)
  })

  it("survives multi-byte text either side of a sequence", () => {
    // Byte-wise stripping must not cut a UTF-8 character in half.
    expect(stripAnsi(`é${ESC}[31mü→`)).toBe("éü→")
  })
})
