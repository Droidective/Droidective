/**
 * Every edit to the API Testing document, as a pure transform.
 *
 * `ApiClientModel` on the Mac mutates an `@Observable` and calls `persist()`;
 * here the document is React state written back whole, so the same edits are
 * `(data, …) => data`. That is not only a translation convenience — it is what
 * makes them testable without a component, and the tree operations underneath
 * are already pure for the same reason.
 */

import { activeMap, newFolder } from "@/lib/api/defaults"
import {
  type ApiClientData,
  type ApiCollection,
  type ApiEnvironment,
  type ApiItem,
  type ApiKeyValue,
  type AuthSpec,
  type SavedRequest,
} from "@/lib/api/model"
import {
  appending,
  duplicating,
  enclosingFolderId,
  find,
  findRequest,
  moving,
  removing,
  renamingFolder,
  replacing,
} from "@/lib/api/tree"

// MARK: - Collections

export function addCollection(data: ApiClientData, collection: ApiCollection): ApiClientData {
  return { ...data, collections: [...data.collections, collection] }
}

export function deleteCollection(data: ApiClientData, id: string): ApiClientData {
  return { ...data, collections: data.collections.filter((one) => one.id !== id) }
}

export function renameCollection(data: ApiClientData, id: string, name: string): ApiClientData {
  return mapCollection(data, id, (collection) => ({ ...collection, name }))
}

export function setCollectionAuth(
  data: ApiClientData,
  id: string,
  auth: AuthSpec,
): ApiClientData {
  return mapCollection(data, id, (collection) => ({ ...collection, auth }))
}

export function setCollectionVariables(
  data: ApiClientData,
  id: string,
  variables: ApiKeyValue[],
): ApiClientData {
  return mapCollection(data, id, (collection) => ({ ...collection, variables }))
}

// MARK: - Items

export function addFolder(
  data: ApiClientData,
  collectionId: string,
  parentId: string | null,
  name: string,
): ApiClientData {
  return mapItems(data, collectionId, (items) =>
    appending({ kind: "folder", folder: newFolder(name) }, parentId, items),
  )
}

export function renameFolder(
  data: ApiClientData,
  collectionId: string,
  folderId: string,
  name: string,
): ApiClientData {
  return mapItems(data, collectionId, (items) => renamingFolder(folderId, name, items))
}

export function deleteItem(
  data: ApiClientData,
  collectionId: string,
  id: string,
): ApiClientData {
  return mapItems(data, collectionId, (items) => removing(id, items))
}

/**
 * Duplicates in place — the copy lands beside its source rather than at the
 * top level, which is what "Duplicate" means everywhere else.
 */
export function duplicateItem(
  data: ApiClientData,
  collectionId: string,
  id: string,
): ApiClientData {
  const collection = data.collections.find((one) => one.id === collectionId)
  if (collection === undefined) return data
  const item = find(id, collection.items)
  if (item === null) return data
  const parent = enclosingFolderId(id, collection.items)
  return mapItems(data, collectionId, (items) => appending(duplicating(item), parent, items))
}

export function moveItem(
  data: ApiClientData,
  collectionId: string,
  id: string,
  folderId: string | null,
): ApiClientData {
  return mapItems(data, collectionId, (items) => moving(id, folderId, items))
}

/**
 * Saves the open request into a collection, replacing it if it is already
 * there — the fallback to inserting is why `replacing` answers null rather
 * than an unchanged tree.
 */
export function saveRequest(
  data: ApiClientData,
  request: SavedRequest,
  collectionId: string,
  folderId: string | null,
): ApiClientData {
  return mapItems(data, collectionId, (items) => {
    const replaced = replacing(request, items)
    if (replaced !== null) return replaced
    return appending({ kind: "request", request }, folderId, items)
  })
}

// MARK: - Environments and globals

export function addEnvironment(
  data: ApiClientData,
  environment: ApiEnvironment,
): ApiClientData {
  return { ...data, environments: [...data.environments, environment] }
}

export function updateEnvironment(
  data: ApiClientData,
  environment: ApiEnvironment,
): ApiClientData {
  return {
    ...data,
    environments: data.environments.map((one) =>
      one.id === environment.id ? environment : one,
    ),
  }
}

/**
 * Deleting the active environment clears the selection too — leaving it set to
 * an environment that no longer exists would resolve every variable to nothing
 * with the picker still naming it.
 */
export function deleteEnvironment(data: ApiClientData, id: string): ApiClientData {
  return {
    ...data,
    environments: data.environments.filter((one) => one.id !== id),
    activeEnvironmentId: data.activeEnvironmentId === id ? null : data.activeEnvironmentId,
  }
}

export function setActiveEnvironment(data: ApiClientData, id: string | null): ApiClientData {
  return { ...data, activeEnvironmentId: id }
}

export function setGlobals(data: ApiClientData, globals: ApiKeyValue[]): ApiClientData {
  return { ...data, globals }
}

// MARK: - Import

/** Appends what a Postman file held. The daemon has already re-identified it. */
export function mergeImport(
  data: ApiClientData,
  imported: { collections: ApiCollection[]; environments: ApiEnvironment[] },
): ApiClientData {
  return {
    ...data,
    collections: [...data.collections, ...imported.collections],
    environments: [...data.environments, ...imported.environments],
  }
}

// MARK: - Dirt

/**
 * Whether the open request differs from what is stored.
 *
 * Drives the confirmation on New Request, which used to throw away several
 * minutes of typing without a word. Both timestamps are zeroed on either
 * side first, because neither is part of what the user typed:
 *
 * - `modifiedAt` moves on every save, so comparing it would call an
 *   untouched request dirty the moment it was saved.
 * - `createdAt` is stable for one request, but not across two constructions
 *   of the same content: `newRequest()` stamps both from `Date.now() / 1000`,
 *   so a request rebuilt from defaults — an import, a round-trip through the
 *   Postman format — differs from its stored copy by whichever millisecond
 *   each was made in, and reports changes nobody made.
 *
 * Leaving `createdAt` in also made this rule's own test nondeterministic:
 * `workspace.test.ts` builds two fixtures back to back and expects them to
 * match, which held only while both landed in the same millisecond.
 */
export function hasUnsavedChanges(
  data: ApiClientData,
  current: SavedRequest,
  collectionId: string | null,
): boolean {
  const collection =
    collectionId === null ? undefined : data.collections.find((one) => one.id === collectionId)
  const stored = collection === undefined ? null : findRequest(current.id, collection.items)
  // Never saved: only worth protecting once there is something in it.
  if (stored === null) return current.url.trim() !== ""
  return content(stored) !== content(current)
}

/** A request stripped of the timestamps, for comparing what it actually holds. */
function content(request: SavedRequest): string {
  return JSON.stringify({ ...request, createdAt: 0, modifiedAt: 0 })
}

/** The collection an open request belongs to, or null for a scratch one. */
export function collectionFor(
  data: ApiClientData,
  collectionId: string | null,
): ApiCollection | null {
  if (collectionId === null) return null
  return data.collections.find((one) => one.id === collectionId) ?? null
}

/** A collection's auth, when it has one to lend. */
export function inheritedAuth(collection: ApiCollection | null): AuthSpec | null {
  if (collection === null || collection.auth.type === "none") return null
  return collection.auth
}

/** Whether an environment holds anything a request could resolve against. */
export function environmentIsEmpty(environment: ApiEnvironment): boolean {
  return Object.keys(activeMap(environment.variables)).length === 0
}

// MARK: - Shared

function mapCollection(
  data: ApiClientData,
  id: string,
  change: (collection: ApiCollection) => ApiCollection,
): ApiClientData {
  return {
    ...data,
    collections: data.collections.map((one) => (one.id === id ? change(one) : one)),
  }
}

function mapItems(
  data: ApiClientData,
  id: string,
  change: (items: ApiItem[]) => ApiItem[],
): ApiClientData {
  return mapCollection(data, id, (collection) => ({
    ...collection,
    items: change(collection.items),
  }))
}
