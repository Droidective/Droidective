import { describe, expect, it } from "vitest"
import {
  filtered,
  matches,
  moveHighlight,
  nameProblem,
  PANEL_VISIBLE,
  panelSplit,
  PLACEHOLDERS,
  recent,
  type Snippet,
} from "@/lib/snippets"

function snippet(over: Partial<Snippet> & { name: string }): Snippet {
  return { text: `text for ${over.name}`, uses: 0, lastUsedAt: null, ...over }
}

describe("recent", () => {
  it("puts the freshest first", () => {
    const list = [
      snippet({ name: "old", lastUsedAt: 100 }),
      snippet({ name: "new", lastUsedAt: 300 }),
      snippet({ name: "mid", lastUsedAt: 200 }),
    ]
    expect(recent(list).map((s) => s.name)).toEqual(["new", "mid", "old"])
  })

  it("sorts a never-used snippet after every used one", () => {
    // Files written before `lastUsedAt` existed decode with null, and they
    // must not jump to the front of the row.
    const list = [snippet({ name: "never" }), snippet({ name: "used", lastUsedAt: 1 })]
    expect(recent(list).map((s) => s.name)).toEqual(["used", "never"])
  })

  it("ranks never-used snippets by use count", () => {
    const list = [snippet({ name: "once", uses: 1 }), snippet({ name: "twice", uses: 2 })]
    expect(recent(list).map((s) => s.name)).toEqual(["twice", "once"])
  })

  it("breaks a full tie by the order they were saved", () => {
    const list = [snippet({ name: "first" }), snippet({ name: "second" })]
    expect(recent(list).map((s) => s.name)).toEqual(["first", "second"])
  })

  it("takes a limit", () => {
    const list = [
      snippet({ name: "a", lastUsedAt: 3 }),
      snippet({ name: "b", lastUsedAt: 2 }),
      snippet({ name: "c", lastUsedAt: 1 }),
    ]
    expect(recent(list, 2).map((s) => s.name)).toEqual(["a", "b"])
  })

  it("does not mutate what it was given", () => {
    const list = [snippet({ name: "b", lastUsedAt: 1 }), snippet({ name: "a", lastUsedAt: 2 })]
    recent(list)
    expect(list.map((s) => s.name)).toEqual(["b", "a"])
  })

  it("is empty for an empty list", () => {
    expect(recent([])).toEqual([])
  })
})

describe("matches", () => {
  const login = snippet({ name: "Login", text: "me@example.com" })

  it("matches the name, case-insensitively", () => {
    expect(matches(login, "log")).toBe(true)
    expect(matches(login, "LOGIN")).toBe(true)
  })

  it("matches the inserted text too", () => {
    // Somebody looking for the snippet holding their test email searches for
    // the email, not the label they gave it a month ago.
    expect(matches(login, "example.com")).toBe(true)
  })

  it("matches everything for a blank query", () => {
    expect(matches(login, "")).toBe(true)
    expect(matches(login, "   ")).toBe(true)
  })

  it("misses what is in neither", () => {
    expect(matches(login, "zzz")).toBe(false)
  })
})

describe("filtered", () => {
  it("keeps only the matches", () => {
    const list = [snippet({ name: "Login" }), snippet({ name: "Address" })]
    expect(filtered(list, "log").map((s) => s.name)).toEqual(["Login"])
  })
})

describe("nameProblem", () => {
  it("refuses an empty or blank name", () => {
    expect(nameProblem("", [])).toBeTruthy()
    expect(nameProblem("   ", [])).toBeTruthy()
  })

  it("refuses a name already taken", () => {
    expect(nameProblem("Login", [snippet({ name: "Login" })])).toBeTruthy()
    expect(nameProblem("  Login  ", [snippet({ name: "Login" })])).toBeTruthy()
  })

  it("accepts a new name", () => {
    expect(nameProblem("Address", [snippet({ name: "Login" })])).toBeNull()
  })
})

describe("panelSplit", () => {
  const many = Array.from({ length: 8 }, (_, index) =>
    snippet({ name: `s${index}`, lastUsedAt: 100 - index }),
  )

  it("shows five and counts the rest", () => {
    const split = panelSplit(many, false)
    expect(split.shown).toHaveLength(PANEL_VISIBLE)
    expect(split.hidden).toBe(3)
  })

  it("shows everything once expanded", () => {
    expect(panelSplit(many, true)).toEqual({ shown: recent(many), hidden: 0 })
  })

  it("hides nothing when there are five or fewer", () => {
    expect(panelSplit(many.slice(0, 4), false).hidden).toBe(0)
  })
})

describe("moveHighlight", () => {
  it("steps down and up", () => {
    expect(moveHighlight(-1, 1, 5)).toBe(0)
    expect(moveHighlight(2, 1, 5)).toBe(3)
    expect(moveHighlight(2, -1, 5)).toBe(1)
  })

  it("clamps at the bottom rather than wrapping", () => {
    expect(moveHighlight(4, 1, 5)).toBe(4)
  })

  it("returns to the field above the first row", () => {
    // -1 is "nothing highlighted", which is what puts the caret back in the
    // text field rather than jumping to the last snippet.
    expect(moveHighlight(0, -1, 5)).toBe(-1)
    expect(moveHighlight(-1, -1, 5)).toBe(-1)
  })

  it("has nowhere to go in an empty list", () => {
    expect(moveHighlight(-1, 1, 0)).toBe(-1)
  })
})

describe("PLACEHOLDERS", () => {
  it("is SnippetPlaceholders.known's list, in its order", () => {
    expect(PLACEHOLDERS).toEqual(["clipboard", "ip"])
  })
})
