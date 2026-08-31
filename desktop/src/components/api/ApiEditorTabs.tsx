import { useEffect, useState } from "react"
import { ArrowDownToLine, Copy } from "lucide-react"

import { KeyValueEditor } from "@/components/api/ApiTables"
import { Button, TextInput } from "@/components/Controls"
import { CODE_TARGETS, type CodeTargetName } from "@/lib/api/labels"
import type { ApiKeyValue, AuthSpec, SavedRequest } from "@/lib/api/model"
import { hasQuery, pathVariableNames, queryParameters, removingQuery } from "@/lib/api/query"
import type { VariableScope } from "@/lib/api/variables"
import { apiCode, asDaemonError, copyText } from "@/lib/daemon"

/**
 * The editor's two tabs that are more than a table: Params, which also holds
 * the URL's own query and its path variables, and Code.
 *
 * Split from `ApiRequestEditor` for its line budget — the Mac keeps all seven
 * in one view.
 */

/**
 * Params, plus the two things the Mac puts beside them: the offer to move a
 * pasted URL's query into the table, and a row per `:name` in the path.
 */
export function ApiParamsTab({
  request,
  onChange,
}: {
  request: SavedRequest
  onChange: (change: (request: SavedRequest) => SavedRequest) => void
}) {
  const found = hasQuery(request.url) ? queryParameters(request.url) : []
  const names = pathVariableNames(request.url)

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      {found.length === 0 ? null : (
        <div className="flex items-center gap-2 bg-accent/10 px-3 py-1.5">
          <ArrowDownToLine size={12} className="text-text-tertiary" />
          <span className="text-[12px] text-text-secondary">
            {found.length === 1
              ? "The URL carries 1 parameter."
              : `The URL carries ${String(found.length)} parameters.`}
          </span>
          <button
            type="button"
            title="Take them out of the URL and list them here, where they can be toggled"
            onClick={() => {
              onChange((previous) => ({
                ...previous,
                queryParams: [...previous.queryParams, ...queryParameters(previous.url)],
                url: removingQuery(previous.url),
              }))
            }}
            className="ml-auto text-[12px] text-accent hover:underline"
          >
            Move Into Table
          </button>
        </div>
      )}
      <KeyValueEditor
        title="Query Parameters"
        placeholder="No parameters. These are appended to the URL when the request is sent."
        items={request.queryParams}
        onChange={(queryParams) => {
          onChange((previous) => ({ ...previous, queryParams }))
        }}
      />
      {names.length === 0 ? null : (
        <>
          <div className="h-px bg-border-subtle" />
          <div className="space-y-1 p-3">
            <h3 className="text-[12px] font-medium text-text-primary">Path Variables</h3>
            {names.map((name) => (
              <label key={name} className="flex items-center gap-3">
                <span className="w-[110px] shrink-0 font-mono text-[12px] text-text-secondary">
                  :{name}
                </span>
                <span className="min-w-0 flex-1">
                  <TextInput
                    value={valueFor(request.pathVariables, name)}
                    placeholder="Value"
                    ariaLabel={`Value for :${name}`}
                    onChange={(value) => {
                      onChange((previous) => ({
                        ...previous,
                        pathVariables: withValue(previous.pathVariables, name, value),
                      }))
                    }}
                  />
                </span>
              </label>
            ))}
          </div>
        </>
      )}
    </div>
  )
}

function valueFor(pairs: ApiKeyValue[], name: string): string {
  return pairs.find((pair) => pair.key === name)?.value ?? ""
}

function withValue(pairs: ApiKeyValue[], name: string, value: string): ApiKeyValue[] {
  if (pairs.some((pair) => pair.key === name)) {
    return pairs.map((pair) => (pair.key === name ? { ...pair, value } : pair))
  }
  return [...pairs, { id: `path-${name}`, key: name, value, enabled: true, note: "" }]
}

/**
 * The Code tab.
 *
 * Generated daemon-side rather than here: `CodeGenerator` already emits six
 * targets from the same request the send builds, and a second implementation
 * would be six ways for the two apps to disagree about what they are sending.
 */
export function ApiCodeTab({
  request,
  scope,
  inherited,
}: {
  request: SavedRequest
  scope: VariableScope
  inherited: AuthSpec | null
}) {
  const [target, setTarget] = useState<CodeTargetName>("curl")
  const [code, setCode] = useState("")

  useEffect(() => {
    let cancelled = false
    apiCode({ request, scope, inheritedAuth: inherited, target }).then(
      (answer) => {
        if (!cancelled) setCode(answer.code)
      },
      (thrown: unknown) => {
        if (!cancelled) setCode(`# ${asDaemonError(thrown).message}`)
      },
    )
    return () => {
      cancelled = true
    }
  }, [request, scope, inherited, target])

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-2">
      <div className="flex items-center gap-2 px-3 pt-2">
        <select
          aria-label="Code target"
          value={target}
          onChange={(event) => {
            setTarget(event.target.value as CodeTargetName)
          }}
          className="rounded-md border border-border-subtle bg-bg-root px-2 py-1.5 text-[13px] text-text-primary"
        >
          {CODE_TARGETS.map((one) => (
            <option key={one.value} value={one.value}>
              {one.label}
            </option>
          ))}
        </select>
        <span className="ml-auto">
          <Button
            title="Copy the generated snippet"
            onClick={() => {
              void copyText(code)
            }}
          >
            <span className="flex items-center gap-1.5">
              <Copy size={12} /> Copy
            </span>
          </Button>
        </span>
      </div>
      <pre
        data-selectable
        className="mx-3 mb-3 min-h-0 flex-1 overflow-auto rounded-md border border-border-subtle bg-bg-root p-2 font-mono text-[12px] text-text-primary"
      >
        {code}
      </pre>
    </div>
  )
}
