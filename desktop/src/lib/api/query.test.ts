import { describe, expect, it } from "vitest"

import { hasQuery, pathVariableNames, queryParameters, removingQuery, splitUrl } from "@/lib/api/query"

describe("splitUrl", () => {
  it("takes the fragment off before the query, so a `?` inside it is not one", () => {
    expect(splitUrl("https://example.test/a?b=1#frag?x")).toEqual({
      base: "https://example.test/a",
      query: "b=1",
      fragment: "frag?x",
    })
  })

  it("copes with a URL that has neither", () => {
    expect(splitUrl("https://example.test")).toEqual({
      base: "https://example.test",
      query: "",
      fragment: "",
    })
  })
})

describe("queryParameters", () => {
  it("reads pairs in the order they appear", () => {
    expect(queryParameters("https://example.test?a=1&b=2").map((p) => [p.key, p.value])).toEqual([
      ["a", "1"],
      ["b", "2"],
    ])
  })

  /** A bare flag is how servers read `?debug`, so it becomes an empty value. */
  it("keeps a bare flag with no value", () => {
    expect(queryParameters("https://example.test?debug").map((p) => [p.key, p.value])).toEqual([
      ["debug", ""],
    ])
  })

  it("decodes percent-escapes and treats + as a space", () => {
    expect(queryParameters("https://example.test?q=a%20b&r=c+d").map((p) => p.value)).toEqual([
      "a b",
      "c d",
    ])
  })

  /**
   * A stray `%` should give someone their URL back rather than an empty table:
   * `decodeURIComponent` throws on it, and throwing here would lose the row.
   */
  it("survives a malformed escape", () => {
    expect(queryParameters("https://example.test?q=100%").map((p) => p.value)).toEqual(["100%"])
  })

  it("skips a pair with no name, and answers nothing for a URL with no query", () => {
    expect(queryParameters("https://example.test?=1&a=2").map((p) => p.key)).toEqual(["a"])
    expect(queryParameters("https://example.test")).toEqual([])
  })

  it("gives every row its own id, so two rows are two rows", () => {
    const rows = queryParameters("https://example.test?a=1&a=2")
    expect(rows).toHaveLength(2)
    expect(rows[0]?.id).not.toBe(rows[1]?.id)
  })
})

describe("removingQuery", () => {
  /**
   * The round trip the Params tab offers: extract into the table, strip from
   * the bar, and what the builder sends is unchanged.
   */
  it("strips the query and keeps the fragment", () => {
    expect(removingQuery("https://example.test/a?b=1#frag")).toBe("https://example.test/a#frag")
    expect(removingQuery("https://example.test/a?b=1")).toBe("https://example.test/a")
  })

  it("leaves a URL with no query exactly as it was", () => {
    expect(removingQuery("https://example.test/a#frag")).toBe("https://example.test/a#frag")
  })
})

describe("hasQuery", () => {
  it("is true only when there is something after the question mark", () => {
    expect(hasQuery("https://example.test?a=1")).toBe(true)
    expect(hasQuery("https://example.test?")).toBe(false)
    expect(hasQuery("https://example.test")).toBe(false)
  })
})

describe("pathVariableNames", () => {
  it("finds `:name` segments in the path", () => {
    expect(pathVariableNames("https://example.test/orders/:id/items/:itemId")).toEqual([
      "id",
      "itemId",
    ])
  })

  /**
   * The one that matters: a port is not a path variable, and treating
   * `localhost:3000` as one would put a nonsense row in the Params tab for
   * every local request.
   */
  it("does not mistake a port for a variable", () => {
    expect(pathVariableNames("http://localhost:3000/orders")).toEqual([])
    expect(pathVariableNames("http://localhost:3000/orders/:id")).toEqual(["id"])
  })

  it("ignores the query string and a scheme-less URL", () => {
    expect(pathVariableNames("https://example.test/a?x=:notAVariable")).toEqual([])
    expect(pathVariableNames("example.test/:id")).toEqual([])
  })

  it("ignores a bare colon with no name after it", () => {
    expect(pathVariableNames("https://example.test/a/:/b")).toEqual([])
  })
})
