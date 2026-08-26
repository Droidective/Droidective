/**
 * The decompiled-tree rules, tested without a decompiler.
 *
 * The shapes here are what jadx and apktool actually write — a package chain
 * that is one directory deep for four levels, then a fan of classes — because
 * that shape is what `defaultExpanded` exists for.
 */

import { describe, expect, it } from "vitest"

import {
  ancestors,
  defaultExpanded,
  hitsByFile,
  isBinary,
  isDirectory,
  languageOf,
  relativePath,
  toggleExpanded,
  visibleRows,
} from "@/lib/decompile"
import type { DecompileHit, DecompileNode } from "@/lib/wire"

function dir(name: string, path: string, children: DecompileNode[]): DecompileNode {
  return { name, path, children }
}

function file(name: string, path: string): DecompileNode {
  return { name, path }
}

/** `/out/sources/com/example/{App.java,Other.java}` plus a sibling resource. */
const root = dir("out", "/out", [
  dir("sources", "/out/sources", [
    dir("com", "/out/sources/com", [
      dir("example", "/out/sources/com/example", [
        file("App.java", "/out/sources/com/example/App.java"),
        file("Other.java", "/out/sources/com/example/Other.java"),
      ]),
    ]),
  ]),
])

describe("isDirectory", () => {
  it("reads a node with children as a directory", () => {
    expect(isDirectory(dir("a", "/a", []))).toBe(true)
  })

  it("reads an empty directory as a directory, not a file", () => {
    // `children: []` is a real directory. Reading it as a file would put a
    // source viewer behind a folder.
    expect(isDirectory({ name: "res", path: "/r/res", children: [] })).toBe(true)
  })

  it("reads a node with no children key as a file", () => {
    expect(isDirectory(file("A.java", "/a/A.java"))).toBe(false)
  })
})

describe("visibleRows", () => {
  it("does not draw the root, whose name is a cache key", () => {
    const rows = visibleRows(root, new Set())
    expect(rows.map((row) => row.node.name)).toEqual(["sources"])
  })

  it("draws a directory's children only when it is expanded", () => {
    const rows = visibleRows(root, new Set(["/out/sources"]))
    expect(rows.map((row) => row.node.name)).toEqual(["sources", "com"])
  })

  it("indents by depth, with the root's children at zero", () => {
    const rows = visibleRows(root, new Set(["/out/sources", "/out/sources/com"]))
    expect(rows.map((row) => [row.node.name, row.depth])).toEqual([
      ["sources", 0],
      ["com", 1],
      ["example", 2],
    ])
  })

  it("reports which rows are open", () => {
    const rows = visibleRows(root, new Set(["/out/sources"]))
    expect(rows[0]?.expanded).toBe(true)
    expect(rows[1]?.expanded).toBe(false)
  })

  it("answers nothing for an empty tree", () => {
    expect(visibleRows(dir("out", "/out", []), new Set())).toEqual([])
  })

  it("answers nothing when the root is somehow a file", () => {
    expect(visibleRows(file("out", "/out"), new Set())).toEqual([])
  })
})

describe("defaultExpanded", () => {
  it("opens the package chain and stops where the tree branches", () => {
    // sources → com → example, then two classes: that is the choice point.
    expect([...defaultExpanded(root)].toSorted()).toEqual([
      "/out/sources",
      "/out/sources/com",
      "/out/sources/com/example",
    ])
  })

  it("stops at once when the root already branches", () => {
    const branched = dir("out", "/out", [dir("a", "/out/a", []), dir("b", "/out/b", [])])
    expect(defaultExpanded(branched).size).toBe(0)
  })

  it("stops at a directory that sits beside a file", () => {
    // A lone directory *plus* a file is still a choice — apktool writes
    // AndroidManifest.xml next to its smali directory.
    const mixed = dir("out", "/out", [
      dir("smali", "/out/smali", []),
      file("AndroidManifest.xml", "/out/AndroidManifest.xml"),
    ])
    expect(defaultExpanded(mixed).size).toBe(0)
  })

  it("cannot run away on a pathological chain", () => {
    let node: DecompileNode = file("leaf", "/out" + "/x".repeat(40) + "/leaf")
    for (let depth = 40; depth > 0; depth -= 1) {
      node = dir("x", "/out" + "/x".repeat(depth), [node])
    }
    expect(defaultExpanded(dir("out", "/out", [node]), 12).size).toBeLessThanOrEqual(12)
  })

  it("answers nothing for an empty tree", () => {
    expect(defaultExpanded(dir("out", "/out", [])).size).toBe(0)
  })
})

describe("toggleExpanded", () => {
  it("opens a shut directory and shuts an open one", () => {
    const opened = toggleExpanded(new Set(), "/out/a")
    expect(opened.has("/out/a")).toBe(true)
    expect(toggleExpanded(opened, "/out/a").has("/out/a")).toBe(false)
  })

  it("does not mutate what it was given", () => {
    const before = new Set(["/out/a"])
    toggleExpanded(before, "/out/b")
    expect([...before]).toEqual(["/out/a"])
  })
})

describe("ancestors", () => {
  it("names every directory on the way down, but not the file", () => {
    expect(ancestors("/out", "/out/sources/com/App.java")).toEqual([
      "/out/sources",
      "/out/sources/com",
    ])
  })

  it("answers nothing for a file directly in the root", () => {
    expect(ancestors("/out", "/out/App.java")).toEqual([])
  })

  it("answers nothing for a path outside the root", () => {
    expect(ancestors("/out", "/elsewhere/App.java")).toEqual([])
  })

  it("does not treat a prefix-sharing sibling as inside", () => {
    expect(ancestors("/out", "/out-other/App.java")).toEqual([])
  })
})

describe("relativePath", () => {
  it("strips the root", () => {
    expect(relativePath("/out", "/out/com/App.java")).toBe("com/App.java")
  })

  it("leaves a path that is not under the root alone", () => {
    expect(relativePath("/out", "/elsewhere/App.java")).toBe("/elsewhere/App.java")
  })
})

function hit(path: string, line: number): DecompileHit {
  return { path, line, text: `line ${line}` }
}

describe("hitsByFile", () => {
  it("groups by file in first-seen order", () => {
    const grouped = hitsByFile([hit("/a.java", 1), hit("/b.java", 2), hit("/a.java", 3)])
    expect(grouped.map((one) => one.path)).toEqual(["/a.java", "/b.java"])
    expect(grouped[0]?.hits.map((one) => one.line)).toEqual([1, 3])
  })

  it("answers nothing for no hits", () => {
    expect(hitsByFile([])).toEqual([])
  })
})

describe("languageOf", () => {
  it("names what the two decompilers emit", () => {
    expect(languageOf("/o/App.java")).toBe("java")
    expect(languageOf("/o/App.kt")).toBe("kotlin")
    expect(languageOf("/o/App.smali")).toBe("smali")
    expect(languageOf("/o/AndroidManifest.xml")).toBe("xml")
  })

  it("is case-insensitive about the extension", () => {
    expect(languageOf("/o/App.JAVA")).toBe("java")
  })

  it("falls back to plain text, which is right for an unknown asset", () => {
    expect(languageOf("/o/blob")).toBe("text")
    expect(languageOf("/o/classes.dex")).toBe("text")
  })
})

describe("isBinary", () => {
  it("names the assets apktool copies through", () => {
    // Handing one to a text viewer shows a screen of replacement characters.
    expect(isBinary("/o/res/icon.png")).toBe(true)
    expect(isBinary("/o/lib/libnative.so")).toBe(true)
    expect(isBinary("/o/resources.arsc")).toBe(true)
  })

  it("leaves source alone", () => {
    expect(isBinary("/o/App.java")).toBe(false)
    expect(isBinary("/o/App.smali")).toBe(false)
  })

  it("treats an extensionless file as text", () => {
    expect(isBinary("/o/LICENSE")).toBe(false)
  })
})
