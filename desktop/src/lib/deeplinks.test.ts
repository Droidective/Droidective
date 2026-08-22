import { describe, expect, it } from "vitest"
import { draftLink, isSubmittable, launchSummary, removeLink, upsert } from "@/lib/deeplinks"
import type { DeepLink } from "@/lib/wire"

function link(id: string, url: string): DeepLink {
  return { id, label: id, url, createdAt: 1 }
}

describe("isSubmittable", () => {
  it("wants a url and nothing else — the Mac's own rule", () => {
    expect(isSubmittable("app://orders")).toBe(true)
    expect(isSubmittable("")).toBe(false)
    expect(isSubmittable("   ")).toBe(false)
  })
})

describe("draftLink", () => {
  it("trims, so a pasted url does not carry its whitespace", () => {
    expect(draftLink("a", "  Orders  ", "  app://orders\n", 7)).toEqual({
      id: "a",
      label: "Orders",
      url: "app://orders",
      createdAt: 7,
    })
  })
})

describe("upsert", () => {
  const links = [link("a", "app://a"), link("b", "app://b")]

  it("appends a new one", () => {
    expect(upsert(links, link("c", "app://c")).map((entry) => entry.id)).toEqual(["a", "b", "c"])
  })

  it("replaces an existing one in place", () => {
    // An edit that moved the row to the bottom would reorder a list nobody
    // asked to reorder.
    const edited = upsert(links, link("a", "app://changed"))
    expect(edited.map((entry) => entry.id)).toEqual(["a", "b"])
    expect(edited[0]?.url).toBe("app://changed")
  })

  it("does not mutate what it was given", () => {
    upsert(links, link("c", "app://c"))
    expect(links).toHaveLength(2)
  })
})

describe("removeLink", () => {
  it("takes one out and leaves the rest", () => {
    const links = [link("a", "app://a"), link("b", "app://b")]
    expect(removeLink(links, "a").map((entry) => entry.id)).toEqual(["b"])
    // An id nothing matches is a no-op rather than a throw.
    expect(removeLink(links, "gone")).toHaveLength(2)
  })
})

describe("launchSummary", () => {
  it("keeps one device's own message", () => {
    // Where adb's reason for refusing a scheme actually shows up.
    expect(
      launchSummary([{ serial: "A", ok: false, message: "No Activity found to handle Intent" }]),
    ).toEqual({ ok: false, message: "No Activity found to handle Intent" })
  })

  it("counts a clean fan-out", () => {
    expect(
      launchSummary([
        { serial: "A", ok: true, message: "Launched" },
        { serial: "B", ok: true, message: "Launched" },
      ]),
    ).toEqual({ ok: true, message: "Launched on 2 devices" })
  })

  it("names which devices failed", () => {
    const summary = launchSummary([
      { serial: "A", ok: true, message: "Launched" },
      { serial: "B", ok: false, message: "no handler" },
    ])
    expect(summary.ok).toBe(false)
    expect(summary.message).toBe("Launched on 1 of 2 — failed on B")
  })

  it("says so when there was nothing to launch on", () => {
    expect(launchSummary([])).toEqual({ ok: false, message: "No device connected." })
  })
})
