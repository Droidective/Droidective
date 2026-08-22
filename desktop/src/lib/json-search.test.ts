import { describe, expect, it } from "vitest"
import { jsonMatches, maxStringifiedBytes, valuePreview } from "@/lib/json-search"

/**
 * Searching a payload whose value is a *stringified* JSON body — the tree view
 * renders it as its object, so the find has to agree with what is on screen.
 * The same cases as ADBKit's `JSONSearchStringifiedTests`.
 */

/** An API request the way `reactotron-react-native` reports one: `data` is the
 * raw string handed to `xhr.send`. */
const request = {
  data: '{"id":"graphData_v1.3","params":{"storeId":"8052321","interval":"hour"}}',
  method: "POST",
  url: "https://example.test/stats",
}

describe("jsonMatches", () => {
  it("matches only the blob when expansion is off", () => {
    const matches = jsonMatches(request, "storeId")
    expect(matches).toHaveLength(1)
    // The escaped body, as one line — what a caller rendering the string as a
    // string should get.
    expect(matches[0]?.displayPath).toBe("data")
    expect(matches[0]?.preview).toContain("graphData_v1.3")
  })

  it("finds the leaf inside the stringified body when expansion is on", () => {
    const matches = jsonMatches(request, "storeId", { expandingStringifiedJson: true })
    expect(matches.map((match) => match.displayPath)).toEqual(["data.params.storeId"])
    expect(matches[0]?.preview).toBe('"8052321"')
  })

  it("previews an expanded payload as its object", () => {
    // `data` matches by key and `graphData_v1.3` by value; the point is the
    // first — its preview is the object the reader sees, not the escaped text.
    const matches = jsonMatches(request, "data", { expandingStringifiedJson: true })
    expect(matches.map((match) => match.displayPath)).toEqual(["data", "data.id"])
    expect(matches[0]?.preview).toBe("{ 2 }")
    expect(matches[0]?.isContainer).toBe(true)
  })

  it("keeps ordinal paths aligned with the tree's rows", () => {
    // The view grafts a parse's rows in the string's place, so the path to a
    // leaf is the string's own path plus the parse's ordinals (keys sorted:
    // data, method, url → data is 0; id, params → params is 1; interval,
    // storeId → storeId is 1).
    const matches = jsonMatches(request, "8052321", { expandingStringifiedJson: true })
    expect(matches.map((match) => match.path)).toEqual([[0, 1, 1]])
  })

  it("expands a whole chain of nested stringified payloads", () => {
    const root = { body: JSON.stringify({ payload: '{"deep":{"flag":true}}' }) }
    const matches = jsonMatches(root, "flag", { expandingStringifiedJson: true })
    expect(matches.map((match) => match.displayPath)).toEqual(["body.payload.deep.flag"])
  })

  it("still matches a string that is not JSON as text", () => {
    const matches = jsonMatches({ note: "storeId was missing" }, "storeId", {
      expandingStringifiedJson: true,
    })
    expect(matches.map((match) => match.displayPath)).toEqual(["note"])
  })

  it("searches a payload past the cap as text", () => {
    const huge = `{"pad":"${"x".repeat(maxStringifiedBytes)}","k":1}`
    const matches = jsonMatches({ data: huge }, "pad", { expandingStringifiedJson: true })
    // Found, but as the string it is — the parse is skipped at this size.
    expect(matches).toHaveLength(1)
    expect(matches[0]?.isContainer).toBe(false)
  })

  it("finds nothing for an empty query", () => {
    expect(jsonMatches(request, "")).toEqual([])
    expect(jsonMatches(request, "   ")).toEqual([])
  })

  it("matches a key or a value, case-insensitively", () => {
    expect(jsonMatches({ Method: "post" }, "method").map((m) => m.displayPath)).toEqual(["Method"])
    expect(jsonMatches({ a: "POST" }, "post").map((m) => m.displayPath)).toEqual(["a"])
  })

  it("matches numbers and booleans by how they read", () => {
    expect(jsonMatches({ status: 404 }, "404")).toHaveLength(1)
    expect(jsonMatches({ ok: false }, "false")).toHaveLength(1)
  })

  it("does not match a null on the word null", () => {
    // Parity with the Mac: null prints as "null" but a search for the word
    // wants the app's own text, and a store full of empty fields would bury it.
    expect(jsonMatches({ value: null }, "null")).toEqual([])
  })

  it("never matches the root itself", () => {
    // The root has no row to scroll to, so a match on it would be a result that
    // cannot be clicked.
    expect(jsonMatches({ deep: { deep: 1 } }, "deep").map((m) => m.displayPath)).toEqual([
      "deep",
      "deep.deep",
    ])
  })

  it("stops at the result limit", () => {
    const many = Object.fromEntries(Array.from({ length: 50 }, (_, i) => [`key${i}`, i]))
    expect(jsonMatches(many, "key", { limit: 10 })).toHaveLength(10)
  })

  it("stops at the visit limit rather than walking a pathological payload", () => {
    // A keystroke has a budget. Without this, a deeply nested state tree makes
    // every character typed into the find box a stall.
    const wide = Object.fromEntries(Array.from({ length: 5000 }, (_, i) => [`k${i}`, "hit"]))
    expect(jsonMatches(wide, "hit", { maxVisited: 20 }).length).toBeLessThan(25)
  })
})

describe("valuePreview", () => {
  it("summarizes containers and quotes strings", () => {
    expect(valuePreview({ a: 1, b: 2 })).toBe("{ 2 }")
    expect(valuePreview([1, 2, 3])).toBe("[ 3 ]")
    expect(valuePreview("text")).toBe('"text"')
    expect(valuePreview(2)).toBe("2")
    expect(valuePreview(2.5)).toBe("2.5")
    expect(valuePreview(true)).toBe("true")
    expect(valuePreview(null)).toBe("null")
  })
})
