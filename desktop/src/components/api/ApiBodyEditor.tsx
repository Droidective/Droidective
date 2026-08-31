import { EmptyNote } from "@/components/api/ApiKit"
import { BinaryBody, GraphqlBody, JsonBody, RawBody } from "@/components/api/ApiBodyKinds"
import { KeyValueEditor, MultipartEditor } from "@/components/api/ApiTables"
import { bodyLabel } from "@/lib/api/labels"
import { BODY_TYPES, type BodyType, type RequestBodySpec } from "@/lib/api/model"
import { cn } from "@/lib/cn"

/**
 * The Body tab — the Mac's `bodyTab`, six kinds behind one picker.
 *
 * The JSON validity note and the Format/Minify pair are `JSONFormatter` on the
 * Mac; here they are `JSON.parse`/`stringify`, which is the same answer for the
 * same input. Nothing about the body is sent for validation: an invalid body
 * is still a body someone may want to send, and the builder warns about it
 * rather than refusing.
 */
export function ApiBodyEditor({
  body,
  onChange,
  onPickFile,
}: {
  body: RequestBodySpec
  onChange: (change: (body: RequestBodySpec) => RequestBodySpec) => void
  onPickFile: (assign: (path: string) => void) => void
}) {
  return (
    <div className="flex min-h-0 flex-1 flex-col gap-2">
      <div className="flex flex-wrap gap-1 px-3 pt-2">
        {BODY_TYPES.map((type) => (
          <button
            key={type}
            type="button"
            onClick={() => {
              onChange((previous) => ({ ...previous, type }))
            }}
            className={cn(
              "rounded-md px-2 py-1 text-[12px] transition",
              body.type === type
                ? "bg-bg-raised text-text-primary"
                : "text-text-secondary hover:text-text-primary",
            )}
          >
            {bodyLabel(type)}
          </button>
        ))}
      </div>
      <Content body={body} onChange={onChange} onPickFile={onPickFile} />
    </div>
  )
}

function Content({
  body,
  onChange,
  onPickFile,
}: {
  body: RequestBodySpec
  onChange: (change: (body: RequestBodySpec) => RequestBodySpec) => void
  onPickFile: (assign: (path: string) => void) => void
}) {
  switch (body.type) {
    case "none":
      return <EmptyNote title="This request has no body." />
    case "json":
      return <JsonBody body={body} onChange={onChange} />
    case "raw":
      return <RawBody body={body} onChange={onChange} />
    case "formUrlEncoded":
      return (
        <KeyValueEditor
          title="Form Fields"
          placeholder="No fields yet. Sent as application/x-www-form-urlencoded."
          items={body.formFields}
          onChange={(formFields) => {
            onChange((previous) => ({ ...previous, formFields }))
          }}
        />
      )
    case "multipart":
      return (
        <MultipartEditor
          fields={body.multipartFields}
          onChange={(multipartFields) => {
            onChange((previous) => ({ ...previous, multipartFields }))
          }}
          onPickFile={(id) => {
            onPickFile((path) => {
              onChange((previous) => ({
                ...previous,
                multipartFields: previous.multipartFields.map((field) =>
                  field.id === id ? { ...field, value: path } : field,
                ),
              }))
            })
          }}
        />
      )
    case "graphql":
      return <GraphqlBody body={body} onChange={onChange} />
    case "binary":
      return <BinaryBody body={body} onChange={onChange} onPickFile={onPickFile} />
  }
}

export function bodyMarker(type: BodyType): string {
  return type === "none" ? "Body" : "Body •"
}
