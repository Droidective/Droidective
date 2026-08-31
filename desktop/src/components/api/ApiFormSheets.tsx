import { useState } from "react"

import { ApiAuthEditor } from "@/components/api/ApiAuthEditor"
import { ApiSheet } from "@/components/api/ApiKit"
import { KeyValueEditor } from "@/components/api/ApiTables"
import { Button, TextInput } from "@/components/Controls"
import { newAuth } from "@/lib/api/defaults"
import type { ApiCollection, ApiKeyValue, AuthSpec, SavedRequest } from "@/lib/api/model"
import { folderChoices } from "@/lib/api/tree"

/**
 * The three sheets with a form in them: Save Request, a variables list, and a
 * collection's auth.
 *
 * Split from `ApiSheets` for its line budget; the Mac keeps all of them in one
 * `ApiClientSheetView`.
 */

/** Naming a request and choosing where it lands — the Mac's `SaveRequestSheet`. */
export function SaveRequestSheet({
  request,
  collections,
  currentCollectionId,
  onSave,
  onDismiss,
}: {
  request: SavedRequest
  collections: ApiCollection[]
  currentCollectionId: string | null
  onSave: (name: string, collectionId: string | null, folderId: string | null) => void
  onDismiss: () => void
}) {
  const [name, setName] = useState(request.name)
  const [collectionId, setCollectionId] = useState<string | null>(
    currentCollectionId ?? collections[0]?.id ?? null,
  )
  const [folderId, setFolderId] = useState<string | null>(null)
  const [newCollectionName, setNewCollectionName] = useState("")

  const collection = collections.find((one) => one.id === collectionId)
  const folders = collection === undefined ? [] : folderChoices(collection.items)
  const canSave =
    name.trim() !== "" &&
    (collections.length === 0 ? newCollectionName.trim() !== "" : collectionId !== null)

  return (
    <ApiSheet
      title="Save Request"
      onDismiss={onDismiss}
      footer={
        <>
          <Button onClick={onDismiss}>Cancel</Button>
          <Button
            tone="primary"
            disabled={!canSave}
            onClick={() => {
              onSave(
                name.trim(),
                collections.length === 0 ? null : collectionId,
                folderId,
              )
              onDismiss()
            }}
          >
            Save
          </Button>
        </>
      }
    >
      <TextInput value={name} onChange={setName} placeholder="Name" ariaLabel="Request name" />
      {collections.length === 0 ? (
        <>
          <TextInput
            value={newCollectionName}
            onChange={setNewCollectionName}
            placeholder="New collection name"
          />
          <p className="text-[12px] text-text-secondary">
            Your first collection will be created to hold this request.
          </p>
        </>
      ) : (
        <>
          <Picker
            label="Collection"
            value={collectionId ?? ""}
            options={collections.map((one) => ({ value: one.id, label: one.name }))}
            onChange={(value) => {
              setCollectionId(value)
              setFolderId(null)
            }}
          />
          {folders.length === 0 ? null : (
            <Picker
              label="Folder"
              value={folderId ?? ""}
              options={[
                { value: "", label: "Top level" },
                ...folders.map((one) => ({ value: one.id, label: one.name })),
              ]}
              onChange={(value) => {
                setFolderId(value === "" ? null : value)
              }}
            />
          )}
        </>
      )}
    </ApiSheet>
  )
}

/**
 * A named list of `{{variables}}` — globals, an environment, or a collection's
 * own. The Mac's `VariablesSheet`, with the same one-line explanation.
 */
export function VariablesSheet({
  title,
  initialName,
  initialVariables,
  onSave,
  onDismiss,
}: {
  title: string
  /** Null for globals and collection variables, which have no name of their own. */
  initialName: string | null
  initialVariables: ApiKeyValue[]
  onSave: (name: string, variables: ApiKeyValue[]) => void
  onDismiss: () => void
}) {
  const [name, setName] = useState(initialName ?? "")
  const [variables, setVariables] = useState(initialVariables)
  const invalid = initialName !== null && name.trim() === ""

  return (
    <ApiSheet
      title={title}
      width={520}
      onDismiss={onDismiss}
      footer={
        <>
          <Button onClick={onDismiss}>Cancel</Button>
          <Button
            tone="primary"
            disabled={invalid}
            onClick={() => {
              onSave(name.trim(), variables)
              onDismiss()
            }}
          >
            Save
          </Button>
        </>
      }
    >
      {initialName === null ? null : (
        <TextInput value={name} onChange={setName} placeholder="Name" ariaLabel="Environment name" />
      )}
      <p className="text-[12px] text-text-secondary">
        {"Reference these anywhere with {{name}}."}
      </p>
      <div className="flex min-h-[220px] flex-col rounded-md border border-border-subtle">
        <KeyValueEditor
          title="Variables"
          placeholder="No variables yet."
          items={variables}
          onChange={setVariables}
        />
      </div>
    </ApiSheet>
  )
}

/** The collection's own auth — applied to requests whose auth is None. */
export function CollectionAuthSheet({
  initial,
  onSave,
  onDismiss,
}: {
  initial: AuthSpec | undefined
  onSave: (auth: AuthSpec) => void
  onDismiss: () => void
}) {
  const [auth, setAuth] = useState<AuthSpec>(initial ?? newAuth())

  return (
    <ApiSheet
      title="Collection Auth"
      onDismiss={onDismiss}
      footer={
        <>
          <Button onClick={onDismiss}>Cancel</Button>
          <Button
            tone="primary"
            onClick={() => {
              onSave(auth)
              onDismiss()
            }}
          >
            Save
          </Button>
        </>
      }
    >
      <p className="text-[12px] text-text-secondary">
        Applied to every request in this collection that has its auth set to None.
      </p>
      <ApiAuthEditor
        auth={auth}
        onChange={(change) => {
          setAuth(change)
        }}
      />
    </ApiSheet>
  )
}

function Picker({
  label,
  value,
  options,
  onChange,
}: {
  label: string
  value: string
  options: { value: string; label: string }[]
  onChange: (value: string) => void
}) {
  return (
    <label className="flex items-center gap-3 text-[12px] text-text-secondary">
      <span className="w-[80px] shrink-0">{label}</span>
      <select
        value={value}
        onChange={(event) => {
          onChange(event.target.value)
        }}
        className="min-w-0 flex-1 rounded-md border border-border-subtle bg-bg-root px-2 py-1.5 text-[13px] text-text-primary"
      >
        {options.map((option) => (
          <option key={option.value} value={option.value}>
            {option.label}
          </option>
        ))}
      </select>
    </label>
  )
}
