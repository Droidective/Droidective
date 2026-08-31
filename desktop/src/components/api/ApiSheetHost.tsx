import { CollectionAuthSheet, SaveRequestSheet } from "@/components/api/ApiFormSheets"
import { ApiRunnerSheet } from "@/components/api/ApiRunnerSheet"
import { ApiNameSheets } from "@/components/api/ApiNameSheets"
import { ApiVariableSheets } from "@/components/api/ApiVariableSheets"
import { CurlImportSheet, type ApiSheetKind } from "@/components/api/ApiSheets"
import type { ApiClient } from "@/hooks/useApiClient"
import { newCollection } from "@/lib/api/defaults"
import { scopeFor } from "@/lib/api/variables"
import { addCollection, collectionFor, saveRequest, setCollectionAuth } from "@/lib/api/workspace"
import { apiCurl, asDaemonError } from "@/lib/daemon"

/** A destructive action waiting on a confirmation — the Mac's `ApiDeletion`. */
export interface PendingDelete {
  title: string
  message: string
  confirmLabel: string
  run: () => void
}

/**
 * Which sheet is up, and what committing it does.
 *
 * One component rather than twelve conditionals in the pane, and the reason is
 * the same as the Mac's `ApiClientSheetView`: every sheet's *effect* is one
 * pure document transform, so keeping them together is keeping the whole set
 * of edits in one readable place.
 */
export function ApiSheetHost({
  sheet,
  client,
  onDismiss,
}: {
  sheet: ApiSheetKind | null
  client: ApiClient
  onDismiss: () => void
}) {
  if (sheet === null) return null
  const { data, update } = client

  switch (sheet.kind) {
    case "newCollection":
    case "renameCollection":
    case "newFolder":
    case "renameFolder":
    case "newEnvironment":
      return <ApiNameSheets sheet={sheet} client={client} onDismiss={onDismiss} />

    case "importCurl":
      return (
        <CurlImportSheet
          onDismiss={onDismiss}
          onImport={async (text) => {
            try {
              const answer = await apiCurl(text)
              client.open(answer.request, client.currentCollectionId)
              return null
            } catch (thrown) {
              return asDaemonError(thrown).message
            }
          }}
        />
      )

    case "saveRequest":
      return (
        <SaveRequestSheet
          request={client.current}
          collections={data.collections}
          currentCollectionId={client.currentCollectionId}
          onDismiss={onDismiss}
          onSave={(name, collectionId, folderId) => {
            // A first save with no collections creates one to hold it, which is
            // what the Mac's sheet offers instead of an empty picker.
            const target = collectionId ?? newCollection(name).id
            const request = { ...client.current, name, modifiedAt: Date.now() / 1000 }
            client.setCurrent(() => request)
            client.setCurrentCollectionId(target)
            update((previous) => {
              const withCollection =
                collectionId === null
                  ? addCollection(previous, { ...newCollection(name), id: target })
                  : previous
              return saveRequest(withCollection, request, target, folderId)
            })
          }}
        />
      )

    case "collectionAuth":
      return (
        <CollectionAuthSheet
          initial={collectionFor(data, sheet.id)?.auth}
          onDismiss={onDismiss}
          onSave={(auth) => {
            update((previous) => setCollectionAuth(previous, sheet.id, auth))
          }}
        />
      )

    case "collectionVariables":
    case "environment":
    case "globals":
      return <ApiVariableSheets sheet={sheet} client={client} onDismiss={onDismiss} />

    case "runner": {
      const collection = collectionFor(data, sheet.collectionId)
      return (
        <ApiRunnerSheet
          collection={collection ?? undefined}
          scope={scopeFor(data, collection)}
          onDismiss={onDismiss}
        />
      )
    }
  }
}

/** Re-exported so the pane names the host and its sheet kind in one import. */
export type { ApiSheetKind }
