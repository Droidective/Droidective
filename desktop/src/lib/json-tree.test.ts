import { describe, expect, it } from "vitest"
import { jsonMatches } from "@/lib/json-search"
import {
  emptyTreeState,
  pathKey,
  pathsTo,
  rowPreview,
  rowText,
  toggled,
  treeRows,
  type TreeState,
} from "@/lib/json-tree"

function open(...keys: string[]): TreeState {
  return { expanded: new Set(keys), raw: new Set() }
}

describe("treeRows", () => {
  const payload = {
    user: { name: "ada", id: 7 },
    tags: ["a", "b"],
    active: true,
  }

  it("shows the root open, with its children", () => {
    // A tree whose only row is "{ 3 }" is a disclosure triangle where a payload
    // should be.
    const rows = treeRows(payload, emptyTreeState())
    expect(rows.map((row) => row.label)).toEqual(["", "active", "tags", "user"])
  })

  it("sorts object keys and keeps array order", () => {
    // The order `json-search.ts` counts in. If the two disagree, clicking a
    // result scrolls to the wrong row.
    const rows = treeRows(payload, open("1"))
    expect(rows.map((row) => row.label)).toEqual(["", "active", "tags", "[0]", "[1]", "user"])
  })

  it("costs one row per collapsed container however big it is", () => {
    const huge = { deep: Object.fromEntries(Array.from({ length: 5000 }, (_, i) => [`k${i}`, i])) }
    expect(treeRows(huge, emptyTreeState())).toHaveLength(2)
  })

  it("only opens what is expanded", () => {
    const rows = treeRows(payload, open("2"))
    expect(rows.map((row) => row.label)).toEqual(["", "active", "tags", "user", "id", "name"])
  })

  it("reports containers with their child count", () => {
    const rows = treeRows(payload, emptyTreeState())
    const user = rows.find((row) => row.label === "user")
    expect(user).toMatchObject({ isContainer: true, count: 2 })
    expect(rows.find((row) => row.label === "active")).toMatchObject({
      isContainer: false,
      count: 0,
    })
  })

  it("gives every row the ordinal path json-search hands back", () => {
    // The two are coupled on purpose, so this asserts the coupling rather than
    // each side separately.
    const request = {
      data: '{"id":"graphData_v1.3","params":{"storeId":"8052321"}}',
      method: "POST",
    }
    const match = jsonMatches(request, "storeId", { expandingStringifiedJson: true })[0]
    expect(match?.path).toEqual([0, 1, 0])
    const rows = treeRows(request, open(...pathsTo(match?.path ?? [])))
    expect(rows.find((row) => pathKey(row.path) === pathKey(match?.path ?? []))?.label).toBe(
      "storeId",
    )
  })

  it("grafts a stringified payload's rows in the string's place", () => {
    // The escaped wall is not what the reader wants; the object inside it is.
    const rows = treeRows({ body: '{"deep":{"flag":true}}' }, open("0", "0.0"))
    expect(rows.map((row) => row.label)).toEqual(["", "body", "deep", "flag"])
    expect(rows[1]?.isParsed).toBe(true)
  })

  it("hands a row back its raw text when asked", () => {
    // Some payloads are only readable raw — an encoded token, a signed blob.
    const raw: TreeState = { expanded: new Set(["0"]), raw: new Set(["0"]) }
    const rows = treeRows({ body: '{"deep":true}' }, raw)
    expect(rows.map((row) => row.label)).toEqual(["", "body"])
    expect(rows[1]).toMatchObject({ isParsed: false, isContainer: false })
  })

  it("leaves a string that is not JSON as a leaf", () => {
    const rows = treeRows({ note: "storeId was missing" }, emptyTreeState())
    expect(rows[1]).toMatchObject({ isContainer: false, isParsed: false })
  })

  it("stops at the row limit rather than flattening a whole state tree", () => {
    const wide = Object.fromEntries(Array.from({ length: 500 }, (_, i) => [`k${i}`, i]))
    expect(treeRows(wide, emptyTreeState(), 20)).toHaveLength(20)
  })

  it("renders a scalar root as a single row", () => {
    expect(treeRows("just text", emptyTreeState())).toHaveLength(1)
    expect(treeRows(null, emptyTreeState())[0]).toMatchObject({ isContainer: false })
  })
})

describe("pathsTo", () => {
  it("names every ancestor, so opening a result opens the way in", () => {
    // A match three levels down is useless if the reader has to find it.
    expect(pathsTo([0, 1, 2])).toEqual(["0", "0.1", "0.1.2"])
    expect(pathsTo([])).toEqual([])
  })
})

describe("toggled", () => {
  it("adds and removes without touching the original", () => {
    const set = new Set(["a"])
    expect([...toggled(set, "b")].toSorted()).toEqual(["a", "b"])
    expect([...toggled(set, "a")]).toEqual([])
    expect([...set]).toEqual(["a"])
  })
})

const rowFor = (value: unknown) => treeRows({ v: value } as never, emptyTreeState())[1]

describe("rowPreview and rowText", () => {
  it("summarizes a container and quotes a string", () => {
    expect(rowPreview(rowFor({ a: 1, b: 2 })!)).toBe("{ 2 }")
    expect(rowPreview(rowFor([1, 2, 3])!)).toBe("[ 3 ]")
    expect(rowPreview(rowFor("text")!)).toBe('"text"')
    expect(rowPreview(rowFor(42)!)).toBe("42")
    expect(rowPreview(rowFor(null)!)).toBe("null")
  })

  it("clips a long preview but keeps the whole text available", () => {
    // The row is one line; the value is not, and Copy value still yields all
    // of it.
    const long = "x".repeat(1000)
    expect(rowPreview(rowFor(long)!, 50)).toHaveLength(53)
    expect(rowText(rowFor(long)!)).toHaveLength(1000)
  })

  it("renders a non-string value as compact JSON for its full text", () => {
    expect(rowText(rowFor({ b: 1, a: 2 })!)).toBe('{"a":2,"b":1}')
  })
})
