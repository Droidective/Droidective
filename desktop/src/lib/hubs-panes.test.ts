// @vitest-environment node
//
// A source-reading test, so it runs in node rather than the project's default
// jsdom: jsdom rewrites `import.meta.url` to an http URL and `readFileSync`
// then refuses it. Nothing here touches a DOM.
import { readFileSync } from "node:fs"
import { describe, expect, it } from "vitest"

import { IMPLEMENTED_HUBS } from "@/lib/hubs"

/**
 * Every hub in `IMPLEMENTED_HUBS` has a pane, read out of the router itself.
 *
 * This is the failure the set exists to prevent, and the one nothing else
 * catches: an id added here folds its members out of the sidebar, the catalog
 * and the palette *immediately*, so a hub whose pane has not landed hides
 * working features behind a screen that renders "not built yet". The members
 * are not merely relocated — they become unreachable.
 *
 * Read from the source rather than restated as a list, for the reason
 * `hints.test.ts` gives: a second list is a list that goes stale, and the
 * router is the thing that actually answers the question.
 */
function routedIDs(): Set<string> {
  const router = readFileSync(new URL("../components/FeaturePane.tsx", import.meta.url), "utf8")
  return new Set(
    router
      .split(/\n\s*case "/u)
      .slice(1)
      .map((block) => block.slice(0, block.indexOf('"'))),
  )
}

describe("every implemented hub has a pane", () => {
  it("finds the router it is meant to be reading", () => {
    // A regex over a source file is only as good as that file's shape: if the
    // router is rewritten into something this cannot read, the test below
    // would pass over an empty set and prove nothing.
    const ids = routedIDs()
    expect(ids.size).toBeGreaterThan(20)
    expect(ids).toContain("logcat")
  })

  it("routes every hub claimed as implemented", () => {
    const ids = routedIDs()
    for (const hub of IMPLEMENTED_HUBS) {
      expect(ids.has(hub), `${hub} folds its members away but has no pane in FeaturePane`).toBe(
        true,
      )
    }
  })
})
