/**
 * Pure operations over a collection's item tree —
 * `ADBKit/Services/ApiClient/ApiCollectionTree.swift`, ported.
 *
 * Every function returns a new tree rather than mutating one, so a screen can
 * apply an edit and persist the result without an intermediate state that is
 * half applied. The port is here rather than behind a daemon route because
 * these run on every keystroke of a rename and every drop of a move: a round
 * trip per edit would make the tree feel like a network.
 */

import { newId } from "@/lib/api/defaults"
import {
  itemId,
  type ApiFolder,
  type ApiItem,
  type ApiKeyValue,
  type SavedRequest,
} from "@/lib/api/model"

// MARK: - Lookup

/** The item with `id`, depth-first through folders. */
export function find(id: string, items: ApiItem[]): ApiItem | null {
  for (const item of items) {
    if (itemId(item) === id) return item
    if (item.kind === "folder") {
      const hit = find(id, item.folder.items)
      if (hit !== null) return hit
    }
  }
  return null
}

export function findRequest(id: string, items: ApiItem[]): SavedRequest | null {
  const hit = find(id, items)
  return hit !== null && hit.kind === "request" ? hit.request : null
}

/**
 * Folder names from the root down to `id`, excluding the item itself.
 *
 * `[]` is the top level and `null` is "not in this tree" — a breadcrumb needs
 * to tell those apart, which is why this does not just return an array.
 */
export function path(id: string, items: ApiItem[]): string[] | null {
  for (const item of items) {
    if (itemId(item) === id) return []
    if (item.kind !== "folder") continue
    const deeper = path(id, item.folder.items)
    if (deeper !== null) return [item.folder.name, ...deeper]
  }
  return null
}

/** Every request in the tree, depth-first, in display order. */
export function allRequests(items: ApiItem[]): SavedRequest[] {
  const out: SavedRequest[] = []
  for (const item of items) {
    if (item.kind === "request") out.push(item.request)
    else out.push(...allRequests(item.folder.items))
  }
  return out
}

export function requestCount(items: ApiItem[]): number {
  return allRequests(items).length
}

/** The enclosing folder's id, or null when the item sits at the top level. */
export function enclosingFolderId(id: string, items: ApiItem[]): string | null {
  for (const item of items) {
    if (item.kind !== "folder") continue
    if (item.folder.items.some((child) => itemId(child) === id)) return item.folder.id
    const deeper = enclosingFolderId(id, item.folder.items)
    if (deeper !== null) return deeper
  }
  return null
}

/** Every folder in the tree with its `A / B` path, for a Move To menu. */
export function folderChoices(
  items: ApiItem[],
  excluding: string | null = null,
  prefix = "",
): { id: string; name: string }[] {
  const out: { id: string; name: string }[] = []
  for (const item of items) {
    if (item.kind !== "folder" || item.folder.id === excluding) continue
    const label = prefix === "" ? item.folder.name : `${prefix} / ${item.folder.name}`
    out.push({ id: item.folder.id, name: label }, ...folderChoices(item.folder.items, excluding, label))
  }
  return out
}

// MARK: - Mutation

/**
 * Replaces the request carrying `request.id`.
 *
 * Null when the id is not in the tree, so a caller can fall back to inserting
 * — which is exactly what Save does for a request being saved the first time.
 */
export function replacing(request: SavedRequest, items: ApiItem[]): ApiItem[] | null {
  let changed = false
  const out: ApiItem[] = items.map((item) => {
    if (item.kind === "request" && item.request.id === request.id) {
      changed = true
      return { kind: "request", request }
    }
    if (item.kind === "folder") {
      const updated = replacing(request, item.folder.items)
      if (updated !== null) {
        changed = true
        return { kind: "folder", folder: { ...item.folder, items: updated } }
      }
    }
    return item
  })
  return changed ? out : null
}

/** Renames a folder in place, keeping its children. */
export function renamingFolder(folderId: string, name: string, items: ApiItem[]): ApiItem[] {
  return items.map((item) => {
    if (item.kind !== "folder") return item
    if (item.folder.id === folderId) return { kind: "folder", folder: { ...item.folder, name } }
    return {
      kind: "folder",
      folder: { ...item.folder, items: renamingFolder(folderId, name, item.folder.items) },
    }
  })
}

/** Removes the item with `id` wherever it sits. */
export function removing(id: string, items: ApiItem[]): ApiItem[] {
  const out: ApiItem[] = []
  for (const item of items) {
    if (itemId(item) === id) continue
    if (item.kind === "folder") {
      out.push({ kind: "folder", folder: { ...item.folder, items: removing(id, item.folder.items) } })
    } else {
      out.push(item)
    }
  }
  return out
}

/**
 * Appends inside `folderId`, or at the top level when it is null.
 *
 * A folder that is not there leaves the tree unchanged rather than dropping
 * the item at the root — a silent relocation is harder to notice than nothing
 * happening.
 */
export function appending(item: ApiItem, folderId: string | null, items: ApiItem[]): ApiItem[] {
  if (folderId === null) return [...items, item]
  let found = false
  const insert = (nodes: ApiItem[]): ApiItem[] =>
    nodes.map((node) => {
      if (node.kind !== "folder") return node
      if (node.folder.id === folderId) {
        found = true
        return { kind: "folder", folder: { ...node.folder, items: [...node.folder.items, item] } }
      }
      return { kind: "folder", folder: { ...node.folder, items: insert(node.folder.items) } }
    })
  const result = insert(items)
  return found ? result : items
}

/**
 * Moves `id` into `folderId` (null = top level).
 *
 * A folder cannot be moved into itself or one of its own descendants: that
 * would detach the subtree from the tree entirely, and the item would be gone
 * with no way back.
 */
export function moving(id: string, folderId: string | null, items: ApiItem[]): ApiItem[] {
  const moved = find(id, items)
  if (moved === null) return items
  if (folderId !== null) {
    if (folderId === id) return items
    if (moved.kind === "folder" && find(folderId, moved.folder.items) !== null) return items
  }
  return appending(moved, folderId, removing(id, items))
}

/**
 * A deep copy with fresh ids, so a duplicate never shares identity with its
 * source — which would make both sides of the tree edit together.
 */
export function duplicating(item: ApiItem, nameSuffix = " Copy"): ApiItem {
  if (item.kind === "request") {
    const stamp = Date.now() / 1000
    return {
      kind: "request",
      request: {
        ...item.request,
        id: newId(),
        name: item.request.name + nameSuffix,
        createdAt: stamp,
        modifiedAt: stamp,
      },
    }
  }
  const folder: ApiFolder = {
    ...item.folder,
    id: newId(),
    name: item.folder.name + nameSuffix,
    items: item.folder.items.map((child) => duplicating(child, "")),
  }
  return { kind: "folder", folder }
}

/** Fresh ids throughout, names untouched. */
export function reidentifying(items: ApiItem[]): ApiItem[] {
  return items.map((item) => {
    if (item.kind === "folder") {
      return {
        kind: "folder",
        folder: { ...item.folder, id: newId(), items: reidentifying(item.folder.items) },
      }
    }
    const request = item.request
    return {
      kind: "request",
      request: {
        ...request,
        id: newId(),
        headers: reidentify(request.headers),
        queryParams: reidentify(request.queryParams),
        pathVariables: reidentify(request.pathVariables),
        body: { ...request.body, formFields: reidentify(request.body.formFields) },
      },
    }
  })
}

function reidentify(pairs: ApiKeyValue[]): ApiKeyValue[] {
  return pairs.map((pair) => ({ ...pair, id: newId() }))
}

// MARK: - Rows and search

export interface TreeRow {
  item: ApiItem
  depth: number
}

/**
 * The tree flattened to the rows currently on screen — a collapsed folder
 * contributes itself and nothing under it.
 *
 * Flat rather than nested for the reason the Mac's sidebar is: nesting a
 * folder's children inside their parent's row gave them different insets from
 * the requests above, so the gaps between rows were visibly uneven.
 */
export function rows(items: ApiItem[], expanded: ReadonlySet<string>, depth = 0): TreeRow[] {
  const out: TreeRow[] = []
  for (const item of items) {
    out.push({ item, depth })
    if (item.kind === "folder" && expanded.has(item.folder.id)) {
      out.push(...rows(item.folder.items, expanded, depth + 1))
    }
  }
  return out
}

export interface SearchHit {
  path: string[]
  request: SavedRequest
}

/**
 * Requests whose name, URL or method matches. An empty query matches nothing —
 * the caller shows the ordinary tree instead.
 */
export function search(query: string, items: ApiItem[]): SearchHit[] {
  const needle = query.trim().toLowerCase()
  if (needle === "") return []
  const out: SearchHit[] = []
  const walk = (nodes: ApiItem[], prefix: string[]) => {
    for (const node of nodes) {
      if (node.kind === "folder") {
        walk(node.folder.items, [...prefix, node.folder.name])
        continue
      }
      const request = node.request
      const haystack = `${request.name} ${request.url} ${request.method}`.toLowerCase()
      if (haystack.includes(needle)) out.push({ path: prefix, request })
    }
  }
  walk(items, [])
  return out
}
