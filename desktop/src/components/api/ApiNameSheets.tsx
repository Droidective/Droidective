import { NameSheet, type ApiSheetKind } from "@/components/api/ApiSheets"
import type { ApiClient } from "@/hooks/useApiClient"
import { newCollection, newEnvironment } from "@/lib/api/defaults"
import {
  addCollection,
  addEnvironment,
  addFolder,
  collectionFor,
  renameCollection,
  renameFolder,
} from "@/lib/api/workspace"

/** The sheets that ask for one name and nothing else. */
type NamingSheet = Extract<
  ApiSheetKind,
  { kind: "newCollection" | "renameCollection" | "newFolder" | "renameFolder" | "newEnvironment" }
>

/**
 * The five one-field prompts.
 *
 * Together rather than beside the sheets with forms in them, because what they
 * have in common is their whole shape: a title, a field, and a verb.
 */
export function ApiNameSheets({
  sheet,
  client,
  onDismiss,
}: {
  sheet: NamingSheet
  client: ApiClient
  onDismiss: () => void
}) {
  const { data, update } = client

  switch (sheet.kind) {
    case "newCollection":
      return (
        <NameSheet
          title="New Collection"
          placeholder="Name"
          action="Create"
          onDismiss={onDismiss}
          onCommit={(name) => {
            const collection = newCollection(name)
            client.setCurrentCollectionId(collection.id)
            update((previous) => addCollection(previous, collection))
          }}
        />
      )
    case "renameCollection":
      return (
        <NameSheet
          title="Rename Collection"
          placeholder="Name"
          action="Rename"
          initial={collectionFor(data, sheet.id)?.name ?? ""}
          onDismiss={onDismiss}
          onCommit={(name) => {
            update((previous) => renameCollection(previous, sheet.id, name))
          }}
        />
      )
    case "newFolder":
      return (
        <NameSheet
          title="New Folder"
          placeholder="Name"
          action="Create"
          onDismiss={onDismiss}
          onCommit={(name) => {
            update((previous) => addFolder(previous, sheet.collectionId, sheet.parent, name))
          }}
        />
      )
    case "renameFolder":
      return (
        <NameSheet
          title="Rename Folder"
          placeholder="Name"
          action="Rename"
          onDismiss={onDismiss}
          onCommit={(name) => {
            update((previous) => renameFolder(previous, sheet.collectionId, sheet.folderId, name))
          }}
        />
      )
    case "newEnvironment":
      return (
        <NameSheet
          title="New Environment"
          placeholder="Name"
          action="Create"
          onDismiss={onDismiss}
          onCommit={(name) => {
            update((previous) => addEnvironment(previous, newEnvironment(name)))
          }}
        />
      )
  }
}
