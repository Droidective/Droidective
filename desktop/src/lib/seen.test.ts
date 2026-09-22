import { describe, expect, it } from "vitest"

import { hasSeen, markSeen, seenKey } from "@/lib/seen"

/** A `localStorage` stand-in, optionally one that refuses. */
function store(options: { throws?: boolean } = {}): Storage {
  const values = new Map<string, string>()
  return {
    getItem(key) {
      if (options.throws === true) throw new Error("blocked")
      return values.get(key) ?? null
    },
    setItem(key, value) {
      if (options.throws === true) throw new Error("blocked")
      values.set(key, value)
    },
  } as Storage
}

describe("one-time notices", () => {
  it("is unseen until it is marked", () => {
    const storage = store()
    expect(hasSeen(storage, "reactotron-intro")).toBe(false)
    markSeen(storage, "reactotron-intro")
    expect(hasSeen(storage, "reactotron-intro")).toBe(true)
  })

  it("keeps one notice from answering for another", () => {
    const storage = store()
    markSeen(storage, "reactotron-intro")
    expect(hasSeen(storage, "something-else")).toBe(false)
  })

  it("namespaces its keys away from the layout's", () => {
    // Both live in the same `localStorage`; a bare "reactotron-intro" would sit
    // next to "droidective.layout" with nothing saying which app owns it.
    expect(seenKey("reactotron-intro")).toBe("droidective.seen.reactotron-intro")
  })

  it("reads as unseen when storage refuses, rather than throwing", () => {
    // A private window throws on access. Showing the notice once more is the
    // safe direction; failing the render is not.
    const storage = store({ throws: true })
    expect(hasSeen(storage, "reactotron-intro")).toBe(false)
    expect(() => {
      markSeen(storage, "reactotron-intro")
    }).not.toThrow()
  })

  it("survives having no storage at all", () => {
    expect(hasSeen(undefined, "reactotron-intro")).toBe(false)
    expect(() => {
      markSeen(undefined, "reactotron-intro")
    }).not.toThrow()
  })
})
