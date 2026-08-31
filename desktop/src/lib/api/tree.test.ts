import { describe, expect, it } from "vitest"

import { newCollection, newFolder, newRequest } from "@/lib/api/defaults"
import { itemId, type ApiItem, type SavedRequest } from "@/lib/api/model"
import {
  allRequests,
  appending,
  duplicating,
  enclosingFolderId,
  find,
  findRequest,
  folderChoices,
  moving,
  path,
  reidentifying,
  removing,
  renamingFolder,
  replacing,
  requestCount,
  rows,
  search,
} from "@/lib/api/tree"

function request(id: string, name: string, url = "https://example.test"): SavedRequest {
  return { ...newRequest(), id, name, url }
}

function requestItem(id: string, name: string, url?: string): ApiItem {
  return { kind: "request", request: request(id, name, url) }
}

function folderItem(id: string, name: string, items: ApiItem[] = []): ApiItem {
  return { kind: "folder", folder: { ...newFolder(name), id, items } }
}

/** Two levels deep, so every walk has something to recurse into. */
function sample(): ApiItem[] {
  return [
    requestItem("r1", "Health"),
    folderItem("f1", "Orders", [
      requestItem("r2", "List orders", "https://example.test/orders"),
      folderItem("f2", "Writes", [requestItem("r3", "Create order")]),
    ]),
  ]
}

describe("find and path", () => {
  it("reaches items at every depth", () => {
    const items = sample()
    expect(find("r1", items)).not.toBeNull()
    expect(findRequest("r3", items)?.name).toBe("Create order")
    expect(find("nope", items)).toBeNull()
  })

  it("tells a top-level item apart from one that is not there at all", () => {
    // The distinction a breadcrumb needs: `[]` and null are different answers.
    expect(path("r1", sample())).toEqual([])
    expect(path("r3", sample())).toEqual(["Orders", "Writes"])
    expect(path("nope", sample())).toBeNull()
  })

  it("counts requests through folders and ignores the folders themselves", () => {
    expect(requestCount(sample())).toBe(3)
    expect(allRequests(sample()).map((one) => one.id)).toEqual(["r1", "r2", "r3"])
  })

  it("names the folder an item sits in, and null at the top level", () => {
    expect(enclosingFolderId("r3", sample())).toBe("f2")
    expect(enclosingFolderId("r1", sample())).toBeNull()
  })
})

describe("replacing", () => {
  it("swaps a nested request in place", () => {
    const updated = { ...request("r3", "Create order"), name: "Place order" }
    const result = replacing(updated, sample())
    expect(result).not.toBeNull()
    expect(findRequest("r3", result ?? [])?.name).toBe("Place order")
  })

  /**
   * Null rather than an unchanged tree, because Save uses it to decide whether
   * to insert: an unchanged tree would look like a successful save that wrote
   * nothing.
   */
  it("answers null for an id that is not in the tree", () => {
    expect(replacing(request("nope", "Ghost"), sample())).toBeNull()
  })
})

describe("removing and appending", () => {
  it("removes at depth without disturbing its siblings", () => {
    const result = removing("r3", sample())
    expect(find("r3", result)).toBeNull()
    expect(requestCount(result)).toBe(2)
    expect(find("f2", result)).not.toBeNull()
  })

  it("appends into a named folder, and at the root for null", () => {
    const inside = appending(requestItem("r4", "New"), "f2", sample())
    expect(path("r4", inside)).toEqual(["Orders", "Writes"])

    const top = appending(requestItem("r5", "New"), null, sample())
    expect(path("r5", top)).toEqual([])
  })

  /**
   * A folder that is not there leaves the tree alone rather than dropping the
   * item at the root — a silent relocation is harder to notice than nothing
   * happening.
   */
  it("leaves the tree untouched when the folder does not exist", () => {
    const items = sample()
    expect(appending(requestItem("r6", "New"), "ghost", items)).toEqual(items)
  })
})

describe("moving", () => {
  it("moves an item between folders", () => {
    const result = moving("r1", "f2", sample())
    expect(path("r1", result)).toEqual(["Orders", "Writes"])
    expect(requestCount(result)).toBe(3)
  })

  it("moves an item back to the top level", () => {
    const result = moving("r3", null, sample())
    expect(path("r3", result)).toEqual([])
  })

  /**
   * The move that would lose the subtree: dropping a folder inside itself
   * detaches everything under it from the tree with no way back.
   */
  it("refuses to move a folder into itself or its own descendant", () => {
    const items = sample()
    expect(moving("f1", "f1", items)).toEqual(items)
    expect(moving("f1", "f2", items)).toEqual(items)
  })

  it("ignores an id that is not in the tree", () => {
    const items = sample()
    expect(moving("ghost", "f1", items)).toEqual(items)
  })
})

describe("duplicating", () => {
  it("gives the copy a fresh id so the two do not edit together", () => {
    const original = requestItem("r1", "Health")
    const copy = duplicating(original)
    expect(itemId(copy)).not.toBe("r1")
    expect(copy.kind === "request" && copy.request.name).toBe("Health Copy")
  })

  /** Only the top node is renamed; the children keep the names they had. */
  it("copies a folder's whole subtree with new ids and unchanged child names", () => {
    const copy = duplicating(folderItem("f1", "Orders", [requestItem("r2", "List orders")]))
    expect(copy.kind).toBe("folder")
    if (copy.kind !== "folder") return
    expect(copy.folder.name).toBe("Orders Copy")
    expect(copy.folder.items[0]?.kind === "request" && copy.folder.items[0].request.name).toBe(
      "List orders",
    )
    expect(itemId(copy.folder.items[0] as ApiItem)).not.toBe("r2")
  })
})

describe("reidentifying", () => {
  /**
   * Importing the same file twice must not produce two trees that share every
   * id — the second would then overwrite the first everywhere a lookup goes by
   * id.
   */
  it("replaces every id in the tree, and every row id inside a request", () => {
    const original = sample()
    const withRows = appending(
      {
        kind: "request",
        request: {
          ...request("r7", "With rows"),
          headers: [{ id: "h1", key: "X", value: "1", enabled: true, note: "" }],
          queryParams: [{ id: "q1", key: "page", value: "2", enabled: true, note: "" }],
        },
      },
      null,
      original,
    )

    const fresh = reidentifying(withRows)
    expect(fresh.map((item) => itemId(item))).not.toEqual(withRows.map((item) => itemId(item)))
    const request7 = allRequests(fresh).find((one) => one.name === "With rows")
    expect(request7?.id).not.toBe("r7")
    expect(request7?.headers[0]?.id).not.toBe("h1")
    expect(request7?.queryParams[0]?.id).not.toBe("q1")
    // Names and values are untouched — only identity changes.
    expect(request7?.headers[0]?.key).toBe("X")
  })
})

describe("rows", () => {
  it("shows a collapsed folder without its contents", () => {
    const visible = rows(sample(), new Set())
    expect(visible.map((row) => itemId(row.item))).toEqual(["r1", "f1"])
  })

  it("indents a folder's contents by one level when it is open", () => {
    const visible = rows(sample(), new Set(["f1"]))
    expect(visible.map((row) => itemId(row.item))).toEqual(["r1", "f1", "r2", "f2"])
    expect(visible.find((row) => itemId(row.item) === "r2")?.depth).toBe(1)
  })

  it("goes two deep when both folders are open", () => {
    const visible = rows(sample(), new Set(["f1", "f2"]))
    expect(visible.find((row) => itemId(row.item) === "r3")?.depth).toBe(2)
  })
})

describe("search", () => {
  it("matches on name, URL and method, and carries the folder path", () => {
    expect(search("list", sample()).map((hit) => hit.request.id)).toEqual(["r2"])
    expect(search("example.test/orders", sample())[0]?.path).toEqual(["Orders"])
    expect(search("get", sample())).toHaveLength(3)
  })

  /**
   * A folder called Orders does not make its requests match "orders" — the
   * hits are requests, and matching on an ancestor's name would surface every
   * request in a folder whose name happened to be typed.
   */
  it("matches the request, not the folder it sits in", () => {
    expect(search("orders", sample()).map((hit) => hit.request.id)).toEqual(["r2"])
  })

  /** An empty query means "show the tree", not "show everything flattened". */
  it("matches nothing for an empty or whitespace query", () => {
    expect(search("", sample())).toEqual([])
    expect(search("   ", sample())).toEqual([])
  })
})

describe("folderChoices", () => {
  it("lists every folder with its path, and can leave one out", () => {
    expect(folderChoices(sample())).toEqual([
      { id: "f1", name: "Orders" },
      { id: "f2", name: "Orders / Writes" },
    ])
    // The moving item's own folder is not a place it can go.
    expect(folderChoices(sample(), "f1")).toEqual([])
  })
})

describe("renamingFolder", () => {
  it("renames at depth and keeps the children", () => {
    const result = renamingFolder("f2", "Mutations", sample())
    expect(path("r3", result)).toEqual(["Orders", "Mutations"])
  })
})

describe("newCollection", () => {
  it("starts empty, with no auth and no variables", () => {
    const collection = newCollection("Orders")
    expect(collection.items).toEqual([])
    expect(collection.auth.type).toBe("none")
    expect(collection.variables).toEqual([])
  })
})
