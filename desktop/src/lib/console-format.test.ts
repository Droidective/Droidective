/**
 * The console's value rendering, pinned to ADBKit's own vectors.
 *
 * Every expectation here is copied from `CDPProtocolTests.inlineSummary*` in
 * ADBKit. That is the point: the two apps must render the same log line the
 * same way, and a loose port would drift one character at a time — a nested
 * object shown as `Object` instead of `{…}`, or an array missing its `(3)`.
 * The payload shapes are real Hermes output, not invented.
 */

import { describe, expect, it } from "vitest"

import { asRemoteObject } from "@/lib/cdp"
import {
  argumentSummary,
  functionSummary,
  inlineSummary,
  isExpandable,
  quoted,
  tokensFor,
} from "@/lib/console-format"
import type { RemoteObject } from "@/lib/cdp"

function remote(json: string): RemoteObject {
  const parsed = asRemoteObject(JSON.parse(json))
  if (parsed === null) throw new Error(`not a RemoteObject: ${json}`)
  return parsed
}

describe("primitives", () => {
  it("renders each type the way Chrome does", () => {
    expect(inlineSummary(remote('{"type":"string","value":"hi"}'))).toBe("'hi'")
    expect(inlineSummary(remote('{"type":"number","value":42}'))).toBe("42")
    expect(inlineSummary(remote('{"type":"number","value":3.5}'))).toBe("3.5")
    expect(inlineSummary(remote('{"type":"boolean","value":true}'))).toBe("true")
    expect(inlineSummary(remote('{"type":"undefined"}'))).toBe("undefined")
    expect(inlineSummary(remote('{"type":"object","subtype":"null","value":null}'))).toBe("null")
    expect(inlineSummary(remote('{"type":"symbol","description":"Symbol(sym)"}'))).toBe(
      "Symbol(sym)",
    )
  })

  it("renders the Hermes unserialisables and bigint", () => {
    // Hermes: -0 / Infinity / NaN carry description + unserializableValue and
    // no value at all.
    expect(
      inlineSummary(remote('{"type":"number","description":"-0","unserializableValue":"-0"}')),
    ).toBe("-0")
    expect(
      inlineSummary(
        remote('{"type":"number","description":"Infinity","unserializableValue":"Infinity"}'),
      ),
    ).toBe("Infinity")
    expect(
      inlineSummary(remote('{"type":"number","description":"NaN","unserializableValue":"NaN"}')),
    ).toBe("NaN")
    // Hermes reports bigint as type "".
    expect(
      inlineSummary(remote('{"type":"","description":"123n","unserializableValue":"123n"}')),
    ).toBe("123n")
  })

  it("renders functions and errors", () => {
    expect(
      inlineSummary(
        remote('{"type":"function","description":"function adder(a0, a1) { [bytecode] }"}'),
      ),
    ).toBe("ƒ adder(a0, a1)")
    expect(
      inlineSummary(
        remote('{"type":"object","subtype":"error","description":"Error: boom\\n   at x:1:1"}'),
      ),
    ).toBe("Error: boom")
  })
})

function arrayOf(length: number, properties: string): string {
  return `{"type":"object","subtype":"array","description":"Array(${String(length)})","preview":{"type":"object",
   "subtype":"array","description":"Array(${String(length)})","overflow":false,"properties":[${properties}]}}`
}

describe("arrays and objects from a preview", () => {
  const array = `{"type":"object","subtype":"array","description":"Array(3)","preview":{"type":"object","subtype":"array",
   "description":"Array(3)","overflow":false,"properties":[{"name":"0","type":"number","value":"1"},
   {"name":"1","type":"string","value":"two"},{"name":"2","type":"object","value":"Array(2)"}]}}`

  const object = `{"type":"object","className":"Object","description":"Object","preview":{"type":"object","description":"Object",
   "overflow":true,"properties":[{"name":"id","type":"number","value":"1"},{"name":"name","type":"string","value":"x"}]}}`

  it("leads a multi-element array with its length", () => {
    expect(inlineSummary(remote(array))).toBe("(3) [1, 'two', Array(2)]")
  })

  it("marks an overflowing object with Chrome's ellipsis", () => {
    expect(inlineSummary(remote(object))).toBe("{id: 1, name: 'x', …}")
  })

  /**
   * The length prefix appears only where it says something: an empty or
   * single-element array reads fine without it.
   */
  it("omits the length prefix for zero and one element", () => {
    expect(inlineSummary(remote(arrayOf(0, "")))).toBe("[]")
    expect(inlineSummary(remote(arrayOf(1, '{"name":"0","type":"number","value":"7"}')))).toBe("[7]")
    expect(
      inlineSummary(
        remote(
          arrayOf(2, '{"name":"0","type":"number","value":"7"},{"name":"1","type":"number","value":"8"}'),
        ),
      ),
    ).toBe("(2) [7, 8]")
  })

  it("renders a nested plain object as {…} and keeps every other name", () => {
    const nested = `{"type":"object","description":"Object","preview":{"type":"object","description":"Object","overflow":false,
     "properties":[{"name":"meta","type":"object","value":"Object"},
     {"name":"list","subtype":"array","type":"object","value":"Array(3)"},
     {"name":"widget","type":"object","value":"Widget"},
     {"name":"none","type":"object","subtype":"null","value":"null"}]}}`
    expect(inlineSummary(remote(nested))).toBe(
      "{meta: {…}, list: Array(3), widget: Widget, none: null}",
    )
  })

  /**
   * Hermes replays its buffered console history with no preview, so the whole
   * pre-connect backlog lands here. `{…}` reads as "open me"; the bare word
   * "Object" does not.
   */
  it("falls back to {…} for a previewless plain object", () => {
    expect(inlineSummary(remote('{"type":"object","className":"Object","description":"Object"}'))).toBe(
      "{…}",
    )
    expect(inlineSummary(remote('{"type":"object","description":"Array(2)"}'))).toBe("Array(2)")
  })
})

describe("console argument style", () => {
  it("prints a top-level string bare, as Chrome does", () => {
    const text = remote('{"type":"string","value":"[StreamLab] hello"}')
    expect(inlineSummary(text, "consoleArgument")).toBe("[StreamLab] hello")
    expect(tokensFor(text, "consoleArgument")[0]?.kind).toBe("plain")
  })

  it("still quotes a string nested inside a value", () => {
    // `console.log('a', {b: 'c'})` is `a {b: 'c'}` — only the top level is bare.
    const args = [
      remote('{"type":"string","value":"a"}'),
      remote(
        `{"type":"object","description":"Object","preview":{"type":"object","description":"Object",
          "overflow":false,"properties":[{"name":"b","type":"string","value":"c"}]}}`,
      ),
    ]
    expect(argumentSummary(args)).toBe("a {b: 'c'}")
  })
})

describe("quoted", () => {
  it("uses single quotes and escapes what would break a row", () => {
    expect(quoted("hi")).toBe("'hi'")
    expect(quoted("a\nb")).toBe("'a\\nb'")
    expect(quoted("a\tb")).toBe("'a\\tb'")
    expect(quoted("back\\slash")).toBe("'back\\\\slash'")
  })

  it("switches to double quotes when the text already has a single one", () => {
    expect(quoted("it's")).toBe('"it\'s"')
  })

  it("escapes the single quote when both kinds are present", () => {
    expect(quoted(`it's "x"`)).toBe(`'it\\'s "x"'`)
  })
})

describe("functionSummary", () => {
  it("answers a bare marker for an empty description", () => {
    expect(functionSummary(undefined as unknown as string | undefined)).toBe("ƒ ()")
    expect(functionSummary("")).toBe("ƒ ()")
  })

  it("keeps an arrow function's own text", () => {
    expect(functionSummary("(a) => a + 1")).toBe("ƒ (a) => a + 1")
  })
})

describe("isExpandable", () => {
  it("is true only for an object with a handle", () => {
    expect(isExpandable(remote('{"type":"object","objectId":"1","description":"Object"}'))).toBe(
      true,
    )
    expect(isExpandable(remote('{"type":"string","value":"hi"}'))).toBe(false)
    // Null has a handle in some runtimes and nothing to open.
    expect(
      isExpandable(remote('{"type":"object","subtype":"null","objectId":"2","value":null}')),
    ).toBe(false)
    expect(isExpandable(remote('{"type":"object","description":"Object"}'))).toBe(false)
  })
})
