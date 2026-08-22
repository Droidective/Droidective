import { describe, expect, it } from "vitest"
import { looksLikeJson, maxEmbeddedBytes, parseEmbedded } from "@/lib/embedded-json"

/**
 * Recognizing and parsing a stringified payload — the `data: "{…}"` field an RN
 * app sends on an `api.response`. The same cases as ADBKit's
 * `EmbeddedJSONTests`, because both apps have to make the same call about the
 * same wire.
 *
 * The recognition half runs per row render, so it must answer without walking
 * (or copying) the payload.
 */
describe("looksLikeJson", () => {
  it("recognizes an object string", () => {
    expect(looksLikeJson('{"id":"graphData_v1.3"}')).toBe(true)
  })

  it("recognizes an array string", () => {
    expect(looksLikeJson("[1,2,3]")).toBe(true)
  })

  it("tolerates surrounding whitespace", () => {
    expect(looksLikeJson('\n  {"a":1}\t\n')).toBe(true)
  })

  it("rejects plain text", () => {
    expect(looksLikeJson("not json at all")).toBe(false)
    expect(looksLikeJson("")).toBe(false)
    expect(looksLikeJson("   ")).toBe(false)
    expect(looksLikeJson("42")).toBe(false)
    expect(looksLikeJson('"{\\"a\\":1}"')).toBe(false)
  })

  it("rejects an unclosed shape", () => {
    expect(looksLikeJson('{"a":1')).toBe(false)
    expect(looksLikeJson("[1,2")).toBe(false)
    // Opener and closer must match each other, not just both be brackets.
    expect(looksLikeJson("{1,2]")).toBe(false)
  })

  it("rejects a lone bracket", () => {
    expect(looksLikeJson("{")).toBe(false)
    expect(looksLikeJson("[")).toBe(false)
  })

  it("rejects a payload past the parse cap", () => {
    const huge = `{"a":"${"x".repeat(maxEmbeddedBytes)}"}`
    expect(looksLikeJson(huge)).toBe(false)
    expect(parseEmbedded(huge)).toBeNull()
  })

  it("measures the cap in bytes, not characters", () => {
    // Just inside the budget as characters, well past it as UTF-8. A check on
    // `.length` alone would parse three times the intended maximum.
    const multiByte = `{"a":"${"日".repeat(maxEmbeddedBytes / 2)}"}`
    expect(multiByte.length).toBeLessThan(maxEmbeddedBytes)
    expect(looksLikeJson(multiByte)).toBe(false)
  })
})

describe("parseEmbedded", () => {
  it("parses a stringified request body", () => {
    const text = '{"id":"graphData_v1.3","params":{"storeId":"8052321","interval":"hour"}}'
    expect(parseEmbedded(text)).toEqual({
      id: "graphData_v1.3",
      params: { storeId: "8052321", interval: "hour" },
    })
  })

  it("parses an array body", () => {
    expect(parseEmbedded("[1,2,3]")).toEqual([1, 2, 3])
  })

  it("parses nested stringified JSON one level at a time", () => {
    // The inner value stays a string — the row that opens it parses it in turn,
    // so a doubly-encoded payload is never walked all at once.
    const parsed = parseEmbedded('{"data":"{\\"deep\\":true}"}')
    const nested = (parsed as { data: string }).data
    expect(nested).toBe('{"deep":true}')
    expect(parseEmbedded(nested)).toEqual({ deep: true })
  })

  it("does not parse malformed JSON", () => {
    expect(parseEmbedded("{oops}")).toBeNull()
    expect(parseEmbedded('{"a":}')).toBeNull()
    expect(parseEmbedded("[1,2]]")).toBeNull()
  })

  it("never turns a scalar into a tree", () => {
    // Shaped like neither an object nor an array: there is nothing to show as a
    // tree, so these must not offer the toggle.
    expect(parseEmbedded("42")).toBeNull()
    expect(parseEmbedded('"quoted"')).toBeNull()
    expect(parseEmbedded("null")).toBeNull()
  })
})
