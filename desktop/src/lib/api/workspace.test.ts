import { describe, expect, it } from "vitest"

import { emptyWorkspace, newCollection, newEnvironment, newRequest } from "@/lib/api/defaults"
import type { ApiClientData, SavedRequest } from "@/lib/api/model"
import { allRequests, findRequest, path, requestCount } from "@/lib/api/tree"
import { addToHistory, clearHistory, historyEntry } from "@/lib/api/history"
import {
  addCollection,
  addFolder,
  collectionFor,
  deleteCollection,
  deleteEnvironment,
  deleteItem,
  duplicateItem,
  inheritedAuth,
  mergeImport,
  moveItem,
  renameCollection,
  renameFolder,
  saveRequest,
  setActiveEnvironment,
  setCollectionAuth,
  setCollectionVariables,
  setGlobals,
  updateEnvironment,
} from "@/lib/api/workspace"

function withCollection(): { data: ApiClientData; id: string } {
  const collection = { ...newCollection("Orders"), id: "c1" }
  return { data: addCollection(emptyWorkspace(), collection), id: "c1" }
}

function request(over: Partial<SavedRequest> = {}): SavedRequest {
  return { ...newRequest(), id: "r1", name: "List", url: "https://example.test", ...over }
}

describe("collections", () => {
  it("adds, renames and deletes", () => {
    const { data, id } = withCollection()
    expect(data.collections).toHaveLength(1)
    expect(renameCollection(data, id, "Checkout").collections[0]?.name).toBe("Checkout")
    expect(deleteCollection(data, id).collections).toEqual([])
  })

  it("sets auth and variables on the right collection only", () => {
    const { data, id } = withCollection()
    const two = addCollection(data, { ...newCollection("Other"), id: "c2" })
    const withAuth = setCollectionAuth(two, id, {
      ...newRequest().auth,
      type: "bearer",
      bearerToken: "t",
    })
    expect(withAuth.collections[0]?.auth.type).toBe("bearer")
    expect(withAuth.collections[1]?.auth.type).toBe("none")

    const withVariables = setCollectionVariables(withAuth, id, [
      { id: "v1", key: "base", value: "https://example.test", enabled: true, note: "" },
    ])
    expect(withVariables.collections[0]?.variables).toHaveLength(1)
    expect(withVariables.collections[1]?.variables).toEqual([])
  })

  it("ignores an id that is not there rather than inventing a collection", () => {
    const { data } = withCollection()
    expect(renameCollection(data, "ghost", "X")).toEqual(data)
  })
})

describe("saveRequest", () => {
  it("inserts the first time and replaces after that", () => {
    const { data, id } = withCollection()
    const saved = saveRequest(data, request(), id, null)
    expect(requestCount(saved.collections[0]?.items ?? [])).toBe(1)

    const again = saveRequest(saved, request({ name: "List orders" }), id, null)
    expect(requestCount(again.collections[0]?.items ?? [])).toBe(1)
    expect(findRequest("r1", again.collections[0]?.items ?? [])?.name).toBe("List orders")
  })

  it("saves into a folder when one is chosen", () => {
    const { data, id } = withCollection()
    const withFolder = addFolder(data, id, null, "Writes")
    const folderId = withFolder.collections[0]?.items[0]
    const target = folderId?.kind === "folder" ? folderId.folder.id : null
    const saved = saveRequest(withFolder, request(), id, target)
    expect(path("r1", saved.collections[0]?.items ?? [])).toEqual(["Writes"])
  })

  /**
   * Replacing looks through the whole tree, so a request saved inside a folder
   * stays there rather than being duplicated at the level Save last named.
   */
  it("replaces a nested request in place rather than adding a second copy", () => {
    const { data, id } = withCollection()
    const withFolder = addFolder(data, id, null, "Writes")
    const first = withFolder.collections[0]?.items[0]
    const target = first?.kind === "folder" ? first.folder.id : null
    const saved = saveRequest(withFolder, request(), id, target)
    const again = saveRequest(saved, request({ name: "Renamed" }), id, null)

    expect(requestCount(again.collections[0]?.items ?? [])).toBe(1)
    expect(path("r1", again.collections[0]?.items ?? [])).toEqual(["Writes"])
  })
})

describe("items", () => {
  it("adds and renames a folder, and deletes an item", () => {
    const { data, id } = withCollection()
    const withFolder = addFolder(data, id, null, "Writes")
    const folder = withFolder.collections[0]?.items[0]
    const folderId = folder?.kind === "folder" ? folder.folder.id : ""

    const renamed = renameFolder(withFolder, id, folderId, "Mutations")
    const after = renamed.collections[0]?.items[0]
    expect(after?.kind === "folder" && after.folder.name).toBe("Mutations")

    expect(deleteItem(renamed, id, folderId).collections[0]?.items).toEqual([])
  })

  /**
   * A duplicate lands beside its source, not at the top level — otherwise
   * duplicating something three folders deep silently moves the copy to the
   * root, where it is hard to find.
   */
  it("duplicates in place", () => {
    const { data, id } = withCollection()
    const withFolder = addFolder(data, id, null, "Writes")
    const folder = withFolder.collections[0]?.items[0]
    const folderId = folder?.kind === "folder" ? folder.folder.id : null
    const saved = saveRequest(withFolder, request(), id, folderId)

    const duplicated = duplicateItem(saved, id, "r1")
    const names = allRequests(duplicated.collections[0]?.items ?? []).map((one) => one.name)
    expect(names).toEqual(["List", "List Copy"])
    expect(path("r1", duplicated.collections[0]?.items ?? [])).toEqual(["Writes"])
  })

  it("moves an item to the top level", () => {
    const { data, id } = withCollection()
    const withFolder = addFolder(data, id, null, "Writes")
    const folder = withFolder.collections[0]?.items[0]
    const folderId = folder?.kind === "folder" ? folder.folder.id : null
    const saved = saveRequest(withFolder, request(), id, folderId)

    const moved = moveItem(saved, id, "r1", null)
    expect(path("r1", moved.collections[0]?.items ?? [])).toEqual([])
  })
})

describe("environments", () => {
  it("adds, updates and selects", () => {
    const environment = { ...newEnvironment("Staging"), id: "e1" }
    const data = { ...emptyWorkspace(), environments: [environment] }
    const renamed = updateEnvironment(data, { ...environment, name: "Prod" })
    expect(renamed.environments[0]?.name).toBe("Prod")
    expect(setActiveEnvironment(renamed, "e1").activeEnvironmentId).toBe("e1")
  })

  /**
   * Deleting the active one has to clear the selection: leaving it pointing at
   * an environment that is gone resolves every variable to nothing while the
   * picker still names it.
   */
  it("clears the selection when the active environment is deleted", () => {
    const data: ApiClientData = {
      ...emptyWorkspace(),
      environments: [{ ...newEnvironment("Staging"), id: "e1" }],
      activeEnvironmentId: "e1",
    }
    const after = deleteEnvironment(data, "e1")
    expect(after.environments).toEqual([])
    expect(after.activeEnvironmentId).toBeNull()
  })

  it("leaves a different selection alone", () => {
    const data: ApiClientData = {
      ...emptyWorkspace(),
      environments: [
        { ...newEnvironment("Staging"), id: "e1" },
        { ...newEnvironment("Prod"), id: "e2" },
      ],
      activeEnvironmentId: "e2",
    }
    expect(deleteEnvironment(data, "e1").activeEnvironmentId).toBe("e2")
  })

  it("replaces the globals wholesale", () => {
    const globals = [{ id: "g1", key: "token", value: "abc", enabled: true, note: "" }]
    expect(setGlobals(emptyWorkspace(), globals).globals).toEqual(globals)
  })
})

describe("history", () => {
  it("puts the newest first and caps the list", () => {
    let data = emptyWorkspace()
    for (let index = 0; index < 205; index += 1) {
      data = addToHistory(data, historyEntry(request(), { url: `https://example.test/${index}` }))
    }
    expect(data.history).toHaveLength(200)
    expect(data.history[0]?.url).toBe("https://example.test/204")
    expect(clearHistory(data).history).toEqual([])
  })

  /**
   * A token must never reach disk in a file someone might share. The URL
   * survives, because it is what makes history navigable.
   */
  it("scrubs the request's secrets but keeps its URL", () => {
    const entry = historyEntry(
      request({
        auth: { ...newRequest().auth, type: "bearer", bearerToken: "super-secret" },
        headers: [{ id: "h1", key: "Authorization", value: "Bearer x", enabled: true, note: "" }],
      }),
      { url: "https://example.test/orders", statusCode: 200, elapsedMs: 12 },
    )
    expect(entry.request.auth.bearerToken).toBe("")
    expect(entry.request.headers[0]?.value).toBe("•••")
    expect(entry.url).toBe("https://example.test/orders")
    expect(entry.statusCode).toBe(200)
  })

  it("records a failed send with its reason and no status", () => {
    const entry = historyEntry(request(), {
      url: "https://example.test",
      errorText: "No response within 60s",
    })
    expect(entry.statusCode).toBeNull()
    expect(entry.errorText).toBe("No response within 60s")
  })
})

describe("mergeImport", () => {
  it("appends rather than replacing what was already there", () => {
    const { data } = withCollection()
    const merged = mergeImport(data, {
      collections: [newCollection("Imported")],
      environments: [newEnvironment("Imported env")],
    })
    expect(merged.collections.map((one) => one.name)).toEqual(["Orders", "Imported"])
    expect(merged.environments).toHaveLength(1)
  })
})

describe("collectionFor and inheritedAuth", () => {
  it("finds the collection and lends its auth only when it has one", () => {
    const { data, id } = withCollection()
    expect(collectionFor(data, id)?.name).toBe("Orders")
    expect(collectionFor(data, null)).toBeNull()
    expect(collectionFor(data, "ghost")).toBeNull()

    expect(inheritedAuth(collectionFor(data, id))).toBeNull()
    const withAuth = setCollectionAuth(data, id, {
      ...newRequest().auth,
      type: "basic",
      basicUsername: "u",
    })
    expect(inheritedAuth(collectionFor(withAuth, id))?.type).toBe("basic")
  })
})
