import { useMemo } from "react"

import type { PendingDelete } from "@/components/api/ApiSheetHost"
import type { SidebarActions } from "@/components/api/ApiSidebar"
import type { ApiSheetKind } from "@/components/api/ApiSheets"
import type { ApiClient } from "@/hooks/useApiClient"
import type { ApiFiles } from "@/hooks/useApiFiles"
import { useApiDeletions } from "@/hooks/useApiDeletions"
import type { ApiCollection, ApiEnvironment, SavedRequest } from "@/lib/api/model"
import { duplicateItem, moveItem, setActiveEnvironment } from "@/lib/api/workspace"

/**
 * What the sidebar's rows and menus do.
 *
 * Every destructive verb here raises a confirmation rather than acting — on
 * the Mac all of these used to happen on a single menu click too, which is
 * why that view grew `ApiDeletion`, and the wording below is its wording.
 */
export function useApiSidebarActions({
  client,
  files,
  setSheet,
  setPendingDelete,
}: {
  client: ApiClient
  files: ApiFiles
  setSheet: (sheet: ApiSheetKind | null) => void
  setPendingDelete: (pending: PendingDelete | null) => void
}): SidebarActions {
  const { open, update } = client
  const deletions = useApiDeletions(client, setPendingDelete)

  return useMemo<SidebarActions>(
    () => ({
      onOpen: (request: SavedRequest, collectionId: string) => {
        open(request, collectionId)
      },
      onNewFolderInside: (collectionId, parentId) => {
        setSheet({ kind: "newFolder", collectionId, parent: parentId })
      },
      onRenameFolder: (collectionId, folderId) => {
        setSheet({ kind: "renameFolder", collectionId, folderId })
      },
      onDuplicate: (collectionId, id) => {
        update((previous) => duplicateItem(previous, collectionId, id))
      },
      onMove: (collectionId, id, folderId) => {
        update((previous) => moveItem(previous, collectionId, id, folderId))
      },
      onDeleteRequest: deletions.request,
      onDeleteFolder: deletions.folder,
      onNewCollection: () => {
        setSheet({ kind: "newCollection" })
      },
      onNewFolder: (collectionId) => {
        setSheet({ kind: "newFolder", collectionId, parent: null })
      },
      onRenameCollection: (id) => {
        setSheet({ kind: "renameCollection", id })
      },
      onCollectionAuth: (id) => {
        setSheet({ kind: "collectionAuth", id })
      },
      onCollectionVariables: (id) => {
        setSheet({ kind: "collectionVariables", id })
      },
      onExportCollection: (collection: ApiCollection) => {
        files.exportCollection(collection, false)
      },
      onRunCollection: (collectionId) => {
        setSheet({ kind: "runner", collectionId })
      },
      onDeleteCollection: deletions.collection,
      onOpenHistory: (request: SavedRequest) => {
        open(request, null)
      },
      onClearHistory: deletions.history,
      onNewEnvironment: () => {
        setSheet({ kind: "newEnvironment" })
      },
      onEditEnvironment: (id) => {
        setSheet({ kind: "environment", id })
      },
      onExportEnvironment: (environment: ApiEnvironment) => {
        files.exportEnvironment(environment)
      },
      onDeleteEnvironment: deletions.environment,
      onActivateEnvironment: (id) => {
        update((previous) => setActiveEnvironment(previous, id))
      },
      onEditGlobals: () => {
        setSheet({ kind: "globals" })
      },
    }),
    [open, update, files, setSheet, deletions],
  )
}
