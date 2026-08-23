import { describe, expect, it } from "vitest"
import { compactPreview, repairSentinels } from "@/lib/json"

/**
 * The Reactotron client's sentinel encoding, undone.
 *
 * The same cases ADBKit's `ReactotronProtocolTests` covers, because both apps
 * repair the same wire: a payload that arrives with a `"~~~ false ~~~"` in it
 * must not render as that text on either.
 */
describe("repairSentinels", () => {
  it("maps the named falsy markers back to real values", () => {
    expect(repairSentinels("~~~ null ~~~")).toBeNull()
    expect(repairSentinels("~~~ undefined ~~~")).toBeNull()
    expect(repairSentinels("~~~ false ~~~")).toBe(false)
    expect(repairSentinels("~~~ zero ~~~")).toBe(0)
    expect(repairSentinels("~~~ empty string ~~~")).toBe("")
  })

  it("matches a marker whatever its case, like the original", () => {
    expect(repairSentinels("~~~ FALSE ~~~")).toBe(false)
    expect(repairSentinels("~~~ Zero ~~~")).toBe(0)
  })

  it("strips the tildes off any other marker and leaves a string", () => {
    // Functions, circular references and Infinity arrive this way. There is no
    // JSON value for them, so the description is the honest thing to show.
    expect(repairSentinels("~~~ fetchUser() ~~~")).toBe("fetchUser()")
    expect(repairSentinels("~~~ Circular ~~~")).toBe("Circular")
  })

  it("leaves ordinary text alone, tildes and all", () => {
    expect(repairSentinels("no markers here")).toBe("no markers here")
    // Too short to be a marker, and not the shape of one.
    expect(repairSentinels("~~~ x ~~~")).toBe("~~~ x ~~~")
    expect(repairSentinels("~~~ unterminated")).toBe("~~~ unterminated")
  })

  it("repairs markers nested anywhere in the payload", () => {
    const repaired = repairSentinels({
      important: "~~~ false ~~~",
      list: ["~~~ zero ~~~", 1],
      deep: { fn: "~~~ handler() ~~~" },
    })
    expect(repaired).toEqual({
      important: false,
      list: [0, 1],
      deep: { fn: "handler()" },
    })
  })

  it("returns a clean payload as the very same object", () => {
    // Not just equal — identical. A streaming timeline repairs every frame, and
    // rebuilding an untouched tree per frame is the cost this avoids.
    const clean = { a: 1, b: ["x", { c: true }] }
    expect(repairSentinels(clean)).toBe(clean)
  })

  it("leaves the untouched branches of a repaired tree shared", () => {
    const untouched = { deep: [1, 2, 3] }
    const repaired = repairSentinels({ flag: "~~~ false ~~~", untouched })
    expect(repaired).toEqual({ flag: false, untouched: { deep: [1, 2, 3] } })
    expect((repaired as { untouched: unknown }).untouched).toBe(untouched)
  })
})

/**
 * The bounded preview a collapsed log row shows.
 *
 * The bound is the point: `console.log` of a megabyte object must cost the same
 * as one of a small object, because it happens on the feed's own path.
 */
describe("compactPreview", () => {
  it("reads like compact JSON with sorted keys", () => {
    expect(compactPreview({ b: 1, a: "x" }, 100)).toBe('{"a":"x","b":1}')
    expect(compactPreview([1, true, null], 100)).toBe("[1,true,null]")
  })

  it("prints a whole number without a decimal point", () => {
    expect(compactPreview({ n: 2 }, 100)).toBe('{"n":2}')
    expect(compactPreview({ n: 2.5 }, 100)).toBe('{"n":2.5}')
  })

  it("escapes what JSON escapes", () => {
    expect(compactPreview({ s: 'a"b\\c\nd\te' }, 100)).toBe('{"s":"a\\"b\\\\c\\nd\\te"}')
  })

  it("stops at the budget rather than serializing the whole value", () => {
    const preview = compactPreview({ pad: "x".repeat(100_000) }, 20)
    expect(preview).toHaveLength(20)
    expect(preview.startsWith('{"pad":"xxx')).toBe(true)
  })

  it("costs the budget, not the payload", () => {
    // The guard against a preview that walks its input: a value a thousand
    // times bigger must not produce a longer answer.
    const small = compactPreview({ items: Array.from({ length: 10 }, (_, i) => i) }, 30)
    const huge = compactPreview({ items: Array.from({ length: 10_000 }, (_, i) => i) }, 30)
    expect(small.length).toBeLessThanOrEqual(30)
    expect(huge).toHaveLength(30)
  })

  it("cuts mid-token rather than pretending to be valid JSON", () => {
    // Stated so nobody feeds a preview back to a parser: it is display text.
    expect(() => JSON.parse(compactPreview({ a: "long value here" }, 8))).toThrow()
  })

  it("gives back nothing for a zero budget", () => {
    expect(compactPreview({ a: 1 }, 0)).toBe("")
  })

  it("keeps a large object's own key order once sorting stops paying", () => {
    // Past 128 keys the sort is skipped — nothing human reads every key of such
    // an object, and sorting one on the feed's path is real time.
    const many = Object.fromEntries(Array.from({ length: 200 }, (_, i) => [`k${200 - i}`, i]))
    expect(compactPreview(many, 12).startsWith('{"k200":0')).toBe(true)
  })
})
