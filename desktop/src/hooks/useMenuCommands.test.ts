// @vitest-environment node
//
// A source-reading test, so it runs in node rather than the project's default
// jsdom: jsdom rewrites `import.meta.url` to an http URL, and `readFileSync`
// then refuses it ("The URL must be of scheme file"). Nothing here touches a
// DOM, so the override costs nothing.
import { readFileSync } from "node:fs"
import { describe, expect, it } from "vitest"
import { goRank, menuCommandIds } from "@/hooks/useMenuCommands"

/**
 * The menu's command ids, read out of the Rust table that declares them.
 *
 * A source read rather than a second list, for the reason `hints.test.ts` reads
 * the pane router: the menu is built in Rust because a webview has no menu of
 * its own, and the handlers are here because that is where the state is. Two
 * halves of one contract in two languages is exactly the shape that drifts, and
 * a menu item that quietly does nothing is invisible until someone clicks it.
 */
function declaredIds(): string[] {
  const source = readFileSync(
    new URL("../../src-tauri/src/menu.rs", import.meta.url),
    "utf8",
  )
  // `id: "terminal.new",` — the table's only use of that key.
  return [...source.matchAll(/^\s*id:\s*"([^"]+)"/gmu)]
    .map((match) => match[1] ?? "")
    .filter((id) => id.length > 0)
}

describe("the window menu", () => {
  it("answers every command the menu declares", () => {
    const handled = new Set(menuCommandIds())
    for (const id of declaredIds()) {
      expect(handled, `${id} is a menu item with no handler`).toContain(id)
    }
  })

  it("handles nothing the menu does not offer", () => {
    // The other direction: a handler for an id that no longer exists is dead
    // code that reads as a working command.
    const declared = new Set(declaredIds())
    for (const id of menuCommandIds()) {
      expect(declared, `${id} is handled but is not a menu item`).toContain(id)
    }
  })

  it("finds the ids it is meant to be checking", () => {
    // A regex over a source file is only as good as the file's shape. Without
    // this, a rewritten table would make both tests above pass over nothing.
    const declared = declaredIds()
    expect(declared.length).toBeGreaterThan(15)
    expect(declared).toContain("terminal.split-beside")
    expect(declared).toContain("tab.close")
  })

  it("reads a Go row's rank off its id", () => {
    // The Go rows are generated in Rust rather than tabled, so they are matched
    // by prefix here — which means the parsing is this app's problem.
    expect(goRank("go.row-0")).toBe(0)
    expect(goRank("go.row-9")).toBe(9)
    expect(goRank("tab.close")).toBeNull()
    // Malformed rather than absent: a rank that is not a number must not become
    // NaN and index into the sidebar.
    expect(goRank("go.row-")).toBeNull()
    expect(goRank("go.row-x")).toBeNull()
    expect(goRank("go.row--1")).toBeNull()
  })
})
