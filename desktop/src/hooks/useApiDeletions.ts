import { useMemo } from "react"

import type { PendingDelete } from "@/components/api/ApiSheetHost"
import type { ApiClient } from "@/hooks/useApiClient"
import { clearHistory } from "@/lib/api/history"
import type { ApiCollection, ApiEnvironment, SavedRequest } from "@/lib/api/model"
import { requestCount } from "@/lib/api/tree"
import { deleteCollection, deleteEnvironment, deleteItem } from "@/lib/api/workspace"

export interface ApiDeletions {
  request: (collectionId: string, request: SavedRequest) => void
  folder: (collectionId: string, folderId: string, name: string, count: number) => void
  collection: (collection: ApiCollection) => void
  environment: (environment: ApiEnvironment) => void
  history: () => void
}

/**
 * The five things that ask before they happen.
 *
 * Their own hook because they share one shape — a titled question, a sentence
 * saying what goes with it, and a verb — and because the wording is the Mac's
 * `ApiDeletion`, which is worth keeping in one place to compare against.
 * Deleting a collection or a folder takes everything inside it, and clearing
 * history cannot be undone; all of these used to happen on a single click.
 */
export function useApiDeletions(
  client: ApiClient,
  setPendingDelete: (pending: PendingDelete | null) => void,
): ApiDeletions {
  const { update, data } = client
  const historyCount = data.history.length

  return useMemo(
    () => ({
      request: (collectionId, request) => {
        setPendingDelete({
          title: `Delete “${request.name}”?`,
          message: "This can't be undone.",
          confirmLabel: "Delete Request",
          run: () => {
            update((previous) => deleteItem(previous, collectionId, request.id))
          },
        })
      },
      folder: (collectionId, folderId, name, count) => {
        setPendingDelete({
          title: `Delete “${name}”?`,
          message:
            count === 0
              ? "The folder is empty. This can't be undone."
              : `Its ${String(count)} request${count === 1 ? "" : "s"} are deleted with it.` +
                " This can't be undone.",
          confirmLabel: "Delete Folder",
          run: () => {
            update((previous) => deleteItem(previous, collectionId, folderId))
          },
        })
      },
      collection: (collection) => {
        const count = requestCount(collection.items)
        setPendingDelete({
          title: `Delete “${collection.name}”?`,
          message:
            count === 1
              ? "Its 1 request is deleted with it. This can't be undone."
              : `Its ${String(count)} requests are deleted with it. This can't be undone.`,
          confirmLabel: "Delete Collection",
          run: () => {
            update((previous) => deleteCollection(previous, collection.id))
          },
        })
      },
      environment: (environment) => {
        setPendingDelete({
          title: `Delete “${environment.name}”?`,
          message: "Requests using its variables will have nothing to resolve them to.",
          confirmLabel: "Delete Environment",
          run: () => {
            update((previous) => deleteEnvironment(previous, environment.id))
          },
        })
      },
      history: () => {
        setPendingDelete({
          title: "Clear history?",
          message:
            `${String(historyCount)} entr${historyCount === 1 ? "y" : "ies"} are removed.` +
            " This can't be undone.",
          confirmLabel: "Clear History",
          run: () => {
            update(clearHistory)
          },
        })
      },
    }),
    [update, setPendingDelete, historyCount],
  )
}
