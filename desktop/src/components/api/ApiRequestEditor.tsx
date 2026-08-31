import { ApiAuthEditor } from "@/components/api/ApiAuthEditor"
import { ApiBodyEditor, bodyMarker } from "@/components/api/ApiBodyEditor"
import { ApiCodeTab, ApiParamsTab } from "@/components/api/ApiEditorTabs"
import { ApiSettingsEditor } from "@/components/api/ApiSettingsEditor"
import { ApiTestsEditor } from "@/components/api/ApiTestsEditor"
import { KeyValueEditor } from "@/components/api/ApiTables"
import type { AuthSpec, SavedRequest } from "@/lib/api/model"
import type { VariableScope } from "@/lib/api/variables"
import type { AssertionOutcomeWire } from "@/lib/daemon"
import { cn } from "@/lib/cn"

export type RequestTab =
  | "params"
  | "headers"
  | "body"
  | "auth"
  | "tests"
  | "settings"
  | "code"

const TABS: RequestTab[] = ["params", "headers", "body", "auth", "tests", "settings", "code"]

/** The editor half — the Mac's `ApiRequestEditor`, seven tabs. */
export function ApiRequestEditor({
  request,
  onChange,
  inherited,
  scope,
  assertionResults,
  tab,
  onTab,
  onPickFile,
}: {
  request: SavedRequest
  onChange: (change: (request: SavedRequest) => SavedRequest) => void
  inherited: AuthSpec | null
  scope: VariableScope
  assertionResults: AssertionOutcomeWire[]
  tab: RequestTab
  onTab: (tab: RequestTab) => void
  onPickFile: (assign: (path: string) => void) => void
}) {
  return (
    <div className="flex h-full min-h-0 flex-col bg-bg-surface/50">
      <div className="flex flex-wrap gap-1 px-2 py-1.5">
        {TABS.map((one) => (
          <button
            key={one}
            type="button"
            onClick={() => {
              onTab(one)
            }}
            className={cn(
              "rounded-md px-2 py-1 text-[12px] transition",
              tab === one
                ? "bg-bg-raised text-text-primary"
                : "text-text-secondary hover:text-text-primary",
            )}
          >
            {tabLabel(one, request)}
          </button>
        ))}
      </div>
      <div className="h-px bg-border-subtle" />
      <Body
        tab={tab}
        request={request}
        onChange={onChange}
        inherited={inherited}
        scope={scope}
        assertionResults={assertionResults}
        onPickFile={onPickFile}
      />
    </div>
  )
}

function tabLabel(tab: RequestTab, request: SavedRequest): string {
  switch (tab) {
    case "params": {
      const count = request.queryParams.length + request.pathVariables.length
      return count > 0 ? `Params (${String(count)})` : "Params"
    }
    case "headers":
      return request.headers.length > 0
        ? `Headers (${String(request.headers.length)})`
        : "Headers"
    case "body":
      return bodyMarker(request.body.type)
    case "auth":
      return request.auth.type === "none" ? "Auth" : "Auth •"
    case "tests":
      return request.assertions.length > 0
        ? `Tests (${String(request.assertions.length)})`
        : "Tests"
    case "settings":
      return "Settings"
    case "code":
      return "Code"
  }
}

function Body({
  tab,
  request,
  onChange,
  inherited,
  scope,
  assertionResults,
  onPickFile,
}: {
  tab: RequestTab
  request: SavedRequest
  onChange: (change: (request: SavedRequest) => SavedRequest) => void
  inherited: AuthSpec | null
  scope: VariableScope
  assertionResults: AssertionOutcomeWire[]
  onPickFile: (assign: (path: string) => void) => void
}) {
  switch (tab) {
    case "params":
      return <ApiParamsTab request={request} onChange={onChange} />
    case "headers":
      return (
        <KeyValueEditor
          title="Headers"
          placeholder="No headers yet. Click + to add one."
          items={request.headers}
          onChange={(headers) => {
            onChange((previous) => ({ ...previous, headers }))
          }}
        />
      )
    case "body":
      return (
        <ApiBodyEditor
          body={request.body}
          onChange={(change) => {
            onChange((previous) => ({ ...previous, body: change(previous.body) }))
          }}
          onPickFile={onPickFile}
        />
      )
    case "auth":
      return (
        <ApiAuthEditor
          auth={request.auth}
          inherited={inherited}
          onChange={(change) => {
            onChange((previous) => ({ ...previous, auth: change(previous.auth) }))
          }}
        />
      )
    case "tests":
      return (
        <ApiTestsEditor
          assertions={request.assertions}
          results={assertionResults}
          onChange={(assertions) => {
            onChange((previous) => ({ ...previous, assertions }))
          }}
        />
      )
    case "settings":
      return (
        <ApiSettingsEditor
          settings={request.settings}
          onChange={(change) => {
            onChange((previous) => ({ ...previous, settings: change(previous.settings) }))
          }}
        />
      )
    case "code":
      return <ApiCodeTab request={request} scope={scope} inherited={inherited} />
  }
}
