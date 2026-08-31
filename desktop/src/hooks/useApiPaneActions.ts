import { useCallback, useMemo } from "react"

import type { PendingDelete } from "@/components/api/ApiSheetHost"
import type { RequestBarActions } from "@/components/api/ApiRequestBar"
import type { SidebarActions } from "@/components/api/ApiSidebar"
import type { ApiSheetKind } from "@/components/api/ApiSheets"
import type { ApiClient } from "@/hooks/useApiClient"
import type { ApiFiles } from "@/hooks/useApiFiles"
import { useApiSidebarActions } from "@/hooks/useApiSidebarActions"
import { setActiveEnvironment } from "@/lib/api/workspace"
import { apiCurl } from "@/lib/daemon"

/**
 * Everything the pane's chrome can ask for, in one place.
 *
 * The pane is a layout; this is its behaviour. Split because the two together
 * were one very long component, and because a destructive verb here raises a
 * confirmation rather than acting — every one of these used to happen on a
 * single menu click on the Mac too, which is why it grew `ApiDeletion`.
 */
export function useApiPaneActions({
  client,
  files,
  setSheet,
  setPendingDelete,
  setPendingNew,
}: {
  client: ApiClient
  files: ApiFiles
  setSheet: (sheet: ApiSheetKind | null) => void
  setPendingDelete: (pending: PendingDelete | null) => void
  setPendingNew: (pending: boolean) => void
}): {
  sidebar: SidebarActions
  bar: Omit<RequestBarActions, "onToggleSidebar">
  setUrl: (url: string) => void
  pickFile: (assign: (path: string) => void) => void
} {
  const { update, open, setCurrent, data } = client

  /**
   * A pasted cURL command imports itself, which is how most requests start
   * life. Typed text is left alone: the guard is the `curl` prefix and enough
   * length that nobody types it by accident.
   */
  const setUrl = useCallback(
    (url: string) => {
      setCurrent((previous) => ({ ...previous, url }))
      const trimmed = url.trim()
      if (trimmed.length <= 5 || !trimmed.toLowerCase().startsWith("curl")) return
      void apiCurl(trimmed).then(
        (answer) => {
          open(answer.request, client.currentCollectionId)
        },
        () => {
          // Not a cURL command after all — leave what was typed alone. The
          // sheet is where a failed parse is worth saying out loud.
        },
      )
    },
    [setCurrent, open, client.currentCollectionId],
  )

  const pickFile = useCallback(
    (assign: (path: string) => void) => {
      void files.choose().then((path) => {
        if (path !== null) assign(path)
      })
    },
    [files],
  )

  const sidebar = useApiSidebarActions({ client, files, setSheet, setPendingDelete })

  const bar = useMemo<Omit<RequestBarActions, "onToggleSidebar">>(
    () => ({
      onSend: client.send,
      onCancel: client.cancelSend,
      onImportCurl: () => {
        setSheet({ kind: "importCurl" })
      },
      onSave: () => {
        setSheet({ kind: "saveRequest" })
      },
      onNewRequest: () => {
        // The Mac asks before throwing an unsaved request away; it is often
        // several minutes of typing.
        if (client.hasUnsaved) setPendingNew(true)
        else client.startNewRequest()
      },
      onImportFile: files.importFile,
      onExportCollection: (collectionId, includeSecrets) => {
        const collection = data.collections.find((one) => one.id === collectionId)
        if (collection !== undefined) files.exportCollection(collection, includeSecrets)
      },
      onRunCollection: (collectionId) => {
        setSheet({ kind: "runner", collectionId })
      },
      onExportWorkspace: () => {
        files.exportWorkspace(data)
      },
      onEditGlobals: () => {
        setSheet({ kind: "globals" })
      },
      onEditActiveEnvironment: () => {
        setSheet(
          data.activeEnvironmentId === null
            ? { kind: "globals" }
            : { kind: "environment", id: data.activeEnvironmentId },
        )
      },
      onSetEnvironment: (id) => {
        update((previous) => setActiveEnvironment(previous, id))
      },
    }),
    [client, files, data, setSheet, setPendingNew, update],
  )

  return { sidebar, bar, setUrl, pickFile }
}
