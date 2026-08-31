import {
  Braces,
  CirclePlus,
  CircleHelp,
  MoreHorizontal,
  PanelLeft,
  Save,
} from "lucide-react"

import { IconButton } from "@/components/api/ApiKit"
import { ApiMenuButton, type MenuEntry } from "@/components/api/ApiMenu"
import { Button, TextInput } from "@/components/Controls"
import { HTTP_METHODS, type ApiClientData, type HttpMethod } from "@/lib/api/model"
import { cn } from "@/lib/cn"

/** What the bar's buttons ask the pane to do. */
export interface RequestBarActions {
  onToggleSidebar: () => void
  onSend: () => void
  onCancel: () => void
  onImportCurl: () => void
  onSave: () => void
  onNewRequest: () => void
  onImportFile: () => void
  onExportCollection: (collectionId: string, includeSecrets: boolean) => void
  onRunCollection: (collectionId: string) => void
  onExportWorkspace: () => void
  onEditGlobals: () => void
  onEditActiveEnvironment: () => void
  onSetEnvironment: (id: string | null) => void
}

/**
 * The method, the URL and everything the Mac puts beside them.
 *
 * The URL field absorbs a pasted cURL command, because that is how most
 * requests start life — typed text is left alone.
 */
export function ApiRequestBar({
  data,
  method,
  url,
  sending,
  canSend,
  sidebarShown,
  unresolved,
  compact,
  onMethod,
  onUrl,
  actions,
}: {
  data: ApiClientData
  method: HttpMethod
  url: string
  sending: boolean
  canSend: boolean
  sidebarShown: boolean
  unresolved: string[]
  compact: boolean
  onMethod: (method: HttpMethod) => void
  onUrl: (url: string) => void
  actions: RequestBarActions
}) {
  return (
    <div className="flex flex-col gap-2 bg-bg-surface p-2.5">
      <div className="flex items-center gap-2">
        <IconButton
          label={sidebarShown ? "Hide sidebar" : "Show sidebar"}
          onClick={actions.onToggleSidebar}
        >
          <PanelLeft size={14} className={sidebarShown ? "text-accent" : undefined} />
        </IconButton>

        <select
          aria-label="HTTP method"
          value={method}
          onChange={(event) => {
            onMethod(event.target.value as HttpMethod)
          }}
          className={cn(
            "shrink-0 rounded-md border border-border-subtle bg-bg-root px-2 py-1.5",
            "text-[13px] text-text-primary",
            compact ? "w-[84px]" : "w-[104px]",
          )}
        >
          {HTTP_METHODS.map((one) => (
            <option key={one} value={one}>
              {one}
            </option>
          ))}
        </select>

        <div className="min-w-0 flex-1 font-mono">
          <TextInput
            value={url}
            placeholder="Enter a URL or paste a cURL command"
            ariaLabel="Request URL"
            onChange={onUrl}
            onKeyDown={(event) => {
              if (event.key === "Enter") actions.onSend()
            }}
          />
        </div>

        <Button tone="primary" onClick={actions.onSend} disabled={!canSend} title="Send (⌘⏎)">
          {sending ? "Sending…" : "Send"}
        </Button>
        {sending ? <Button onClick={actions.onCancel}>Cancel</Button> : null}

        {compact ? null : <Toolbar data={data} actions={actions} />}
      </div>

      {compact ? (
        <div className="flex items-center gap-2">
          <Toolbar data={data} actions={actions} />
        </div>
      ) : null}

      {unresolved.length === 0 ? null : (
        <div className="flex items-center gap-1.5">
          <CircleHelp size={12} className="text-warn" />
          <span className="text-[12px] text-text-secondary">
            No value for {unresolved.map((name) => `{{${name}}}`).join(", ")}
          </span>
          <button
            type="button"
            onClick={actions.onEditActiveEnvironment}
            className="text-[12px] text-accent hover:underline"
          >
            Edit Environment
          </button>
        </div>
      )}
    </div>
  )
}

function Toolbar({ data, actions }: { data: ApiClientData; actions: RequestBarActions }) {
  return (
    <>
      <IconButton label="Import a cURL command" onClick={actions.onImportCurl}>
        <Braces size={14} />
      </IconButton>
      <IconButton label="Save this request (⌘S)" onClick={actions.onSave}>
        <Save size={14} />
      </IconButton>
      <IconButton label="New request" onClick={actions.onNewRequest}>
        <CirclePlus size={14} />
      </IconButton>

      <select
        aria-label="Active environment"
        value={data.activeEnvironmentId ?? ""}
        onChange={(event) => {
          actions.onSetEnvironment(event.target.value === "" ? null : event.target.value)
        }}
        className="max-w-[160px] rounded-md border border-border-subtle bg-bg-root px-2 py-1.5 text-[13px] text-text-primary"
      >
        <option value="">No environment</option>
        {data.environments.map((environment) => (
          <option key={environment.id} value={environment.id}>
            {environment.name}
          </option>
        ))}
      </select>

      <ApiMenuButton label="Import, export, and run" entries={menuEntries(data, actions)}>
        <MoreHorizontal size={14} />
      </ApiMenuButton>
    </>
  )
}

/**
 * Every collection is reachable here, not only the one the open request
 * happens to belong to — with nothing open these were simply absent.
 */
function menuEntries(data: ApiClientData, actions: RequestBarActions): MenuEntry[] {
  const entries: MenuEntry[] = [
    { label: "Import Postman Collection or Environment…", onSelect: actions.onImportFile },
  ]

  if (data.collections.length > 0) {
    entries.push({ label: "Export collection", heading: true, separatorBefore: true })
    for (const collection of data.collections) {
      entries.push({
        label: collection.name,
        onSelect: () => {
          actions.onExportCollection(collection.id, false)
        },
      })
    }
    entries.push({ label: "Export with secrets", heading: true })
    for (const collection of data.collections) {
      entries.push({
        label: collection.name,
        onSelect: () => {
          actions.onExportCollection(collection.id, true)
        },
      })
    }
    entries.push({ label: "Run collection", heading: true })
    for (const collection of data.collections) {
      entries.push({
        label: collection.name,
        onSelect: () => {
          actions.onRunCollection(collection.id)
        },
      })
    }
  }

  entries.push(
    { label: "Export Everything…", separatorBefore: true, onSelect: actions.onExportWorkspace },
    { label: "Edit Global Variables…", onSelect: actions.onEditGlobals },
  )
  return entries
}
