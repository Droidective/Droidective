import { Minus, Plus } from "lucide-react"

import { EmptyNote, IconButton, SectionHeader } from "@/components/api/ApiKit"
import { Button, TextInput } from "@/components/Controls"
import { newFormField, newKeyValue } from "@/lib/api/defaults"
import type { ApiFormField, ApiKeyValue } from "@/lib/api/model"

/**
 * The key/value table behind Params, Headers, form bodies and every variables
 * sheet — the Mac's `ApiKeyValueEditor`.
 *
 * The checkbox is not decoration: a disabled row stays in the list and out of
 * the request, which is how someone keeps a header around without sending it.
 */
export function KeyValueEditor({
  title,
  placeholder,
  items,
  onChange,
}: {
  title: string
  placeholder: string
  items: ApiKeyValue[]
  onChange: (items: ApiKeyValue[]) => void
}) {
  const replace = (id: string, change: (item: ApiKeyValue) => ApiKeyValue) => {
    onChange(items.map((item) => (item.id === id ? change(item) : item)))
  }

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <SectionHeader title={title}>
        <IconButton
          label="Add a row"
          onClick={() => {
            onChange([...items, newKeyValue()])
          }}
        >
          <Plus size={13} />
        </IconButton>
      </SectionHeader>
      {items.length === 0 ? (
        <EmptyNote title={placeholder} />
      ) : (
        <div className="min-h-0 flex-1 overflow-auto px-3 pb-3">
          {items.map((item) => (
            <div key={item.id} className="flex items-center gap-1.5 py-0.5">
              <input
                type="checkbox"
                aria-label={`Include ${item.key === "" ? "this row" : item.key}`}
                title="Include this row"
                checked={item.enabled}
                onChange={(event) => {
                  replace(item.id, (row) => ({ ...row, enabled: event.target.checked }))
                }}
                className="accent-[var(--color-accent)]"
              />
              <div className="min-w-0 flex-1">
                <TextInput
                  value={item.key}
                  placeholder="Key"
                  ariaLabel="Key"
                  onChange={(value) => {
                    replace(item.id, (row) => ({ ...row, key: value }))
                  }}
                />
              </div>
              <div className="min-w-0 flex-1">
                <TextInput
                  value={item.value}
                  placeholder="Value"
                  ariaLabel="Value"
                  onChange={(value) => {
                    replace(item.id, (row) => ({ ...row, value }))
                  }}
                />
              </div>
              <IconButton
                label="Remove this row"
                onClick={() => {
                  onChange(items.filter((row) => row.id !== item.id))
                }}
              >
                <Minus size={13} className="text-danger" />
              </IconButton>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

/** The multipart table — the Mac's `ApiMultipartEditor`, two rows per part. */
export function MultipartEditor({
  fields,
  onChange,
  onPickFile,
}: {
  fields: ApiFormField[]
  onChange: (fields: ApiFormField[]) => void
  onPickFile: (id: string) => void
}) {
  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <SectionHeader title="Form Data">
        <IconButton
          label="Add a part"
          onClick={() => {
            onChange([...fields, newFormField()])
          }}
        >
          <Plus size={13} />
        </IconButton>
      </SectionHeader>
      {fields.length === 0 ? (
        <EmptyNote title="No parts yet. Text parts and file parts can be mixed." />
      ) : (
        <div className="min-h-0 flex-1 space-y-2 overflow-auto px-3 pb-3">
          {fields.map((field) => (
            <PartRow
              key={field.id}
              field={field}
              onChange={(next) => {
                onChange(fields.map((row) => (row.id === field.id ? next : row)))
              }}
              onRemove={() => {
                onChange(fields.filter((row) => row.id !== field.id))
              }}
              onPickFile={() => {
                onPickFile(field.id)
              }}
            />
          ))}
        </div>
      )}
    </div>
  )
}

/**
 * One part: the name row, then the value row.
 *
 * Two rows because a file part needs a path, a Choose… button and a
 * Content-Type beside its name — on one line the name field would be a
 * sliver.
 */
function PartRow({
  field,
  onChange,
  onRemove,
  onPickFile,
}: {
  field: ApiFormField
  onChange: (field: ApiFormField) => void
  onRemove: () => void
  onPickFile: () => void
}) {
  return (
    <div className="space-y-1">
      <div className="flex items-center gap-1.5">
        <input
          type="checkbox"
          aria-label={`Include ${field.key === "" ? "this part" : field.key}`}
          checked={field.enabled}
          onChange={(event) => {
            onChange({ ...field, enabled: event.target.checked })
          }}
          className="accent-[var(--color-accent)]"
        />
        <div className="min-w-0 flex-1">
          <TextInput
            value={field.key}
            placeholder="Key"
            ariaLabel="Part name"
            onChange={(value) => {
              onChange({ ...field, key: value })
            }}
          />
        </div>
        <select
          aria-label="Part kind"
          value={field.kind}
          onChange={(event) => {
            onChange({ ...field, kind: event.target.value === "file" ? "file" : "text" })
          }}
          className="rounded-md border border-border-subtle bg-bg-root px-2 py-1.5 text-[13px] text-text-primary"
        >
          <option value="text">Text</option>
          <option value="file">File</option>
        </select>
        <IconButton label="Remove this part" onClick={onRemove}>
          <Minus size={13} className="text-danger" />
        </IconButton>
      </div>
      <div className="flex items-center gap-1.5 pl-5">
        <div className="min-w-0 flex-1">
          <TextInput
            value={field.value}
            placeholder={field.kind === "file" ? "File path" : "Value"}
            ariaLabel={field.kind === "file" ? "File path" : "Part value"}
            onChange={(value) => {
              onChange({ ...field, value })
            }}
          />
        </div>
        {field.kind === "file" ? <Button onClick={onPickFile}>Choose…</Button> : null}
        <div className="w-[150px] shrink-0">
          <TextInput
            value={field.contentType}
            placeholder="Content-Type"
            ariaLabel="Part Content-Type"
            onChange={(value) => {
              onChange({ ...field, contentType: value })
            }}
          />
        </div>
      </div>
    </div>
  )
}
