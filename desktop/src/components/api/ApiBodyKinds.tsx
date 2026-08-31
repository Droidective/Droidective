import { TriangleAlert } from "lucide-react"

import { Button, TextInput } from "@/components/Controls"
import { RAW_LANGUAGES, rawContentType, type RequestBodySpec } from "@/lib/api/model"
import { cn } from "@/lib/cn"

/**
 * The four body kinds that are an editor rather than a table.
 *
 * Split from `ApiBodyEditor` for its line budget; the Mac keeps them in the
 * same view. The JSON validity note and the Format/Minify pair are
 * `JSONFormatter` there and `JSON.parse`/`stringify` here — the same answer
 * for the same input, and nothing is sent to check it: an invalid body is
 * still a body someone may want to send, and the builder warns rather than
 * refusing.
 */

export function JsonBody({
  body,
  onChange,
}: {
  body: RequestBodySpec
  onChange: (change: (body: RequestBodySpec) => RequestBodySpec) => void
}) {
  const invalid = body.jsonText !== "" && !isValidJson(body.jsonText)
  return (
    <div className="flex min-h-0 flex-1 flex-col gap-1">
      <div className="flex items-center gap-3 px-3">
        {invalid ? (
          <span className="flex items-center gap-1 text-[12px] text-warn">
            <TriangleAlert size={11} /> Not valid JSON
          </span>
        ) : null}
        <span className="ml-auto flex gap-3">
          <LinkButton
            label="Format"
            onClick={() => {
              onChange((previous) => ({
                ...previous,
                jsonText: reformat(previous.jsonText, 2) ?? previous.jsonText,
              }))
            }}
          />
          <LinkButton
            label="Minify"
            onClick={() => {
              onChange((previous) => ({
                ...previous,
                jsonText: reformat(previous.jsonText, 0) ?? previous.jsonText,
              }))
            }}
          />
        </span>
      </div>
      <CodeArea
        label="JSON body"
        value={body.jsonText}
        onChange={(jsonText) => {
          onChange((previous) => ({ ...previous, jsonText }))
        }}
      />
    </div>
  )
}

export function RawBody({
  body,
  onChange,
}: {
  body: RequestBodySpec
  onChange: (change: (body: RequestBodySpec) => RequestBodySpec) => void
}) {
  return (
    <div className="flex min-h-0 flex-1 flex-col gap-1">
      <div className="flex items-center gap-2 px-3">
        <select
          aria-label="Syntax"
          value={body.rawLanguage}
          onChange={(event) => {
            onChange((previous) => ({
              ...previous,
              rawLanguage: event.target.value as RequestBodySpec["rawLanguage"],
            }))
          }}
          className="rounded-md border border-border-subtle bg-bg-root px-2 py-1.5 text-[13px] text-text-primary"
        >
          {RAW_LANGUAGES.map((language) => (
            <option key={language} value={language}>
              {language[0]?.toUpperCase()}
              {language.slice(1)}
            </option>
          ))}
        </select>
        <div className="min-w-0 flex-1">
          <TextInput
            value={body.rawContentType}
            placeholder={rawContentType(body.rawLanguage)}
            ariaLabel="Content-Type override"
            onChange={(value) => {
              onChange((previous) => ({ ...previous, rawContentType: value }))
            }}
          />
        </div>
      </div>
      <CodeArea
        label="Raw body"
        value={body.rawText}
        onChange={(rawText) => {
          onChange((previous) => ({ ...previous, rawText }))
        }}
      />
    </div>
  )
}

export function GraphqlBody({
  body,
  onChange,
}: {
  body: RequestBodySpec
  onChange: (change: (body: RequestBodySpec) => RequestBodySpec) => void
}) {
  const invalid = body.graphqlVariables !== "" && !isValidJson(body.graphqlVariables)
  return (
    <div className="flex min-h-0 flex-1 flex-col gap-1">
      <span className="px-3 text-[12px] text-text-secondary">Query</span>
      <CodeArea
        label="GraphQL query"
        value={body.graphqlQuery}
        onChange={(graphqlQuery) => {
          onChange((previous) => ({ ...previous, graphqlQuery }))
        }}
      />
      <div className="h-px bg-border-subtle" />
      <span className="px-3 text-[12px] text-text-secondary">
        Variables (JSON)
        {invalid ? <span className="text-warn"> · not valid JSON</span> : null}
      </span>
      <CodeArea
        label="GraphQL variables"
        value={body.graphqlVariables}
        rows={5}
        onChange={(graphqlVariables) => {
          onChange((previous) => ({ ...previous, graphqlVariables }))
        }}
      />
    </div>
  )
}

export function BinaryBody({
  body,
  onChange,
  onPickFile,
}: {
  body: RequestBodySpec
  onChange: (change: (body: RequestBodySpec) => RequestBodySpec) => void
  onPickFile: (assign: (path: string) => void) => void
}) {
  return (
    <div className="flex flex-col gap-2 p-3">
      <div className="flex items-center gap-2">
        <div className="min-w-0 flex-1">
          <TextInput
            value={body.binaryFilePath}
            placeholder="File path"
            ariaLabel="Binary body file"
            onChange={(binaryFilePath) => {
              onChange((previous) => ({ ...previous, binaryFilePath }))
            }}
          />
        </div>
        <Button
          onClick={() => {
            onPickFile((path) => {
              onChange((previous) => ({ ...previous, binaryFilePath: path }))
            })
          }}
        >
          Choose…
        </Button>
      </div>
      <span className="text-[12px] text-text-secondary">
        The file&apos;s bytes are sent as the whole body.
      </span>
    </div>
  )
}

function CodeArea({
  label,
  value,
  onChange,
  rows,
}: {
  label: string
  value: string
  onChange: (value: string) => void
  rows?: number
}) {
  return (
    <textarea
      aria-label={label}
      value={value}
      rows={rows}
      spellCheck={false}
      onChange={(event) => {
        onChange(event.target.value)
      }}
      className={cn(
        "mx-3 mb-3 min-h-0 flex-1 resize-none rounded-md border border-border-subtle",
        "bg-bg-root p-2 font-mono text-[12px] text-text-primary outline-none focus:border-accent",
      )}
    />
  )
}

function LinkButton({ label, onClick }: { label: string; onClick: () => void }) {
  return (
    <button type="button" onClick={onClick} className="text-[12px] text-accent hover:underline">
      {label}
    </button>
  )
}

function isValidJson(text: string): boolean {
  try {
    JSON.parse(text)
    return true
  } catch {
    return false
  }
}

/** Pretty at two spaces, minified at zero. Null when it is not JSON at all. */
function reformat(text: string, indent: number): string | null {
  try {
    return JSON.stringify(JSON.parse(text), null, indent)
  } catch {
    return null
  }
}
