import { Circle, CircleDot, Globe, MoreHorizontal, Plus, TriangleAlert } from "lucide-react"

import { EmptyNote, IconButton, MethodBadge, SectionHeader } from "@/components/api/ApiKit"
import { ApiMenuButton } from "@/components/api/ApiMenu"
import type { SidebarActions } from "@/components/api/ApiSidebar"
import { statusColor } from "@/lib/api/labels"
import type { ApiClientData, ApiEnvironment } from "@/lib/api/model"
import { cn } from "@/lib/cn"

/**
 * The sidebar's other two sections.
 *
 * Split from `ApiSidebar` only for its line budget — they are the same view's
 * History and Environments lists, and the Mac keeps all three in one file.
 */

export function ApiHistory({ data, actions }: { data: ApiClientData; actions: SidebarActions }) {
  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <SectionHeader title="History">
        {data.history.length === 0 ? null : (
          <button
            type="button"
            onClick={actions.onClearHistory}
            className="text-[12px] text-text-secondary hover:text-text-primary"
          >
            Clear
          </button>
        )}
      </SectionHeader>
      {data.history.length === 0 ? (
        <EmptyNote title="No requests yet" detail="Sent requests land here." />
      ) : (
        <div className="min-h-0 flex-1 overflow-auto pb-2">
          {data.history.map((entry) => (
            <button
              key={entry.id}
              type="button"
              title="Credentials aren't kept in history — re-enter them after loading."
              onClick={() => {
                actions.onOpenHistory(entry.request)
              }}
              className="block w-full px-3 py-1 text-left hover:bg-bg-raised"
            >
              <span className="flex items-center gap-1.5">
                <MethodBadge method={entry.method} />
                {typeof entry.statusCode === "number" ? (
                  <span className={cn("font-mono text-[10px]", statusColor(entry.statusCode))}>
                    {entry.statusCode}
                  </span>
                ) : entry.errorText === null || entry.errorText === undefined ? null : (
                  <span className="text-danger">
                    <TriangleAlert size={10} />
                  </span>
                )}
                {typeof entry.elapsedMs === "number" ? (
                  <span className="ml-auto font-mono text-[10px] text-text-tertiary">
                    {Math.round(entry.elapsedMs)} ms
                  </span>
                ) : null}
              </span>
              <span className="block truncate font-mono text-[11px] text-text-tertiary">
                {entry.url}
              </span>
            </button>
          ))}
        </div>
      )}
    </div>
  )
}

export function ApiEnvironments({ data, actions }: { data: ApiClientData; actions: SidebarActions }) {
  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <SectionHeader title="Environments">
        <IconButton label="New environment" onClick={actions.onNewEnvironment}>
          <Plus size={13} />
        </IconButton>
      </SectionHeader>
      <button
        type="button"
        onClick={actions.onEditGlobals}
        className="flex items-center gap-2 px-3 pb-2 text-[12px] text-text-primary hover:text-accent"
      >
        <Globe size={12} />
        Global variables
        <span className="ml-auto text-text-tertiary">{data.globals.length}</span>
      </button>
      {data.environments.length === 0 ? (
        <EmptyNote title="No environments" detail="Group per-stage values like {{baseUrl}}." />
      ) : (
        <div className="min-h-0 flex-1 overflow-auto pb-2">
          {data.environments.map((environment) => (
            <EnvironmentRow
              key={environment.id}
              environment={environment}
              active={data.activeEnvironmentId === environment.id}
              actions={actions}
            />
          ))}
        </div>
      )}
    </div>
  )
}

function EnvironmentRow({
  environment,
  active,
  actions,
}: {
  environment: ApiEnvironment
  active: boolean
  actions: SidebarActions
}) {
  return (
    <div className="flex items-center gap-1 px-3 py-1 hover:bg-bg-raised">
      <button
        type="button"
        onClick={() => {
          actions.onActivateEnvironment(environment.id)
        }}
        className="flex min-w-0 flex-1 items-center gap-2 text-left"
      >
        <span className={active ? "text-accent" : "text-text-tertiary"}>
          {active ? <CircleDot size={11} /> : <Circle size={11} />}
        </span>
        <span className="min-w-0">
          <span className="block truncate text-[12px] text-text-primary">{environment.name}</span>
          <span className="block text-[10px] text-text-tertiary">
            {environment.variables.length} variables
          </span>
        </span>
      </button>
      <ApiMenuButton
        label={`${environment.name} actions`}
        entries={[
          {
            label: "Edit…",
            onSelect: () => {
              actions.onEditEnvironment(environment.id)
            },
          },
          {
            label: "Export…",
            onSelect: () => {
              actions.onExportEnvironment(environment)
            },
          },
          {
            label: "Delete…",
            danger: true,
            separatorBefore: true,
            onSelect: () => {
              actions.onDeleteEnvironment(environment)
            },
          },
        ]}
      >
        <MoreHorizontal size={13} />
      </ApiMenuButton>
    </div>
  )
}
