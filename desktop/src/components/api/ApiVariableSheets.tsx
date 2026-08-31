import { VariablesSheet } from "@/components/api/ApiFormSheets"
import type { ApiSheetKind } from "@/components/api/ApiSheets"
import type { ApiClient } from "@/hooks/useApiClient"
import {
  collectionFor,
  setCollectionVariables,
  setGlobals,
  updateEnvironment,
} from "@/lib/api/workspace"

/** The three sheets that edit a list of `{{variables}}`. */
type VariableSheet = Extract<
  ApiSheetKind,
  { kind: "collectionVariables" | "environment" | "globals" }
>

/**
 * Globals, an environment, and a collection's own variables.
 *
 * One component because they are one editor over three different lists — the
 * only differences are the title and whether the list has a name of its own.
 */
export function ApiVariableSheets({
  sheet,
  client,
  onDismiss,
}: {
  sheet: VariableSheet
  client: ApiClient
  onDismiss: () => void
}) {
  const { data, update } = client

  if (sheet.kind === "globals") {
    return (
      <VariablesSheet
        title="Global Variables"
        initialName={null}
        initialVariables={data.globals}
        onDismiss={onDismiss}
        onSave={(_name, variables) => {
          update((previous) => setGlobals(previous, variables))
        }}
      />
    )
  }

  if (sheet.kind === "collectionVariables") {
    return (
      <VariablesSheet
        title="Collection Variables"
        initialName={null}
        initialVariables={collectionFor(data, sheet.id)?.variables ?? []}
        onDismiss={onDismiss}
        onSave={(_name, variables) => {
          update((previous) => setCollectionVariables(previous, sheet.id, variables))
        }}
      />
    )
  }

  const environment = data.environments.find((one) => one.id === sheet.id)
  if (environment === undefined) return null
  return (
    <VariablesSheet
      title="Edit Environment"
      initialName={environment.name}
      initialVariables={environment.variables}
      onDismiss={onDismiss}
      onSave={(name, variables) => {
        update((previous) => updateEnvironment(previous, { ...environment, name, variables }))
      }}
    />
  )
}
