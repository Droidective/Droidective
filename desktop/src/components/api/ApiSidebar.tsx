import { useState } from "react"
import { Lock, MoreHorizontal, Plus } from "lucide-react"

import { EmptyNote, IconButton, MethodBadge, SectionHeader } from "@/components/api/ApiKit"
import { ApiEnvironments, ApiHistory } from "@/components/api/ApiSidebarLists"
import { ApiMenuButton, type MenuEntry } from "@/components/api/ApiMenu"
import { ApiTree, type TreeActions } from "@/components/api/ApiTree"
import { TextInput } from "@/components/Controls"
import type {
  ApiClientData,
  ApiCollection,
  ApiEnvironment,
  SavedRequest,
} from "@/lib/api/model"
import { requestCount, search } from "@/lib/api/tree"
import { cn } from "@/lib/cn"

export type SidebarSection = "collections" | "history" | "environments"

const SECTIONS: { id: SidebarSection; label: string }[] = [
  { id: "collections", label: "Collections" },
  { id: "history", label: "History" },
  { id: "environments", label: "Environments" },
]

export interface SidebarActions extends TreeActions {
  onNewCollection: () => void
  onNewFolder: (collectionId: string) => void
  onRenameCollection: (collectionId: string) => void
  onCollectionAuth: (collectionId: string) => void
  onCollectionVariables: (collectionId: string) => void
  onExportCollection: (collection: ApiCollection) => void
  onRunCollection: (collectionId: string) => void
  onDeleteCollection: (collection: ApiCollection) => void

  onOpenHistory: (request: SavedRequest) => void
  onClearHistory: () => void

  onNewEnvironment: () => void
  onEditEnvironment: (id: string) => void
  onExportEnvironment: (environment: ApiEnvironment) => void
  onDeleteEnvironment: (environment: ApiEnvironment) => void
  onActivateEnvironment: (id: string) => void
  onEditGlobals: () => void
}

/** The Mac's `ApiClientSidebar`: three sections behind one picker. */
export function ApiSidebar({
  data,
  section,
  onSection,
  actions,
}: {
  data: ApiClientData
  section: SidebarSection
  onSection: (section: SidebarSection) => void
  actions: SidebarActions
}) {
  return (
    <div className="flex h-full min-h-0 flex-col border-r border-border-subtle bg-bg-surface">
      <div className="flex gap-1 p-2">
        {SECTIONS.map((one) => (
          <button
            key={one.id}
            type="button"
            onClick={() => {
              onSection(one.id)
            }}
            className={cn(
              "flex-1 rounded-md px-2 py-1 text-[12px] transition",
              section === one.id
                ? "bg-bg-raised text-text-primary"
                : "text-text-secondary hover:text-text-primary",
            )}
          >
            {one.label}
          </button>
        ))}
      </div>
      <div className="h-px bg-border-subtle" />
      {section === "collections" ? <Collections data={data} actions={actions} /> : null}
      {section === "history" ? <ApiHistory data={data} actions={actions} /> : null}
      {section === "environments" ? <ApiEnvironments data={data} actions={actions} /> : null}
    </div>
  )
}

function Collections({ data, actions }: { data: ApiClientData; actions: SidebarActions }) {
  const [query, setQuery] = useState("")
  const hits =
    query.trim() === ""
      ? []
      : data.collections.flatMap((collection) =>
          search(query, collection.items).map((hit) => ({ collection, hit })),
        )
  const [expanded, setExpanded] = useState<ReadonlySet<string>>(new Set())

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <SectionHeader title="Collections">
        <IconButton label="New collection" onClick={actions.onNewCollection}>
          <Plus size={13} />
        </IconButton>
      </SectionHeader>
      <div className="px-3 pb-2">
        <TextInput value={query} onChange={setQuery} placeholder="Search requests" />
      </div>

      {data.collections.length === 0 ? (
        <EmptyNote
          title="No collections yet"
          detail="Create one, or import a Postman collection."
        />
      ) : query.trim() === "" ? (
        <div className="min-h-0 flex-1 overflow-auto pb-2">
          {data.collections.map((collection) => (
            <div key={collection.id}>
              <CollectionHeader collection={collection} actions={actions} />
              <ApiTree
                collection={collection}
                expanded={expanded}
                onToggleFolder={(id) => {
                  setExpanded((was) => {
                    const next = new Set(was)
                    if (next.has(id)) next.delete(id)
                    else next.add(id)
                    return next
                  })
                }}
                actions={actions}
              />
            </div>
          ))}
        </div>
      ) : hits.length === 0 ? (
        <EmptyNote title="No matches" />
      ) : (
        <div className="min-h-0 flex-1 overflow-auto pb-2">
          {hits.map(({ collection, hit }) => (
            <button
              key={hit.request.id}
              type="button"
              onClick={() => {
                actions.onOpen(hit.request, collection.id)
              }}
              className="block w-full px-3 py-1 text-left hover:bg-bg-raised"
            >
              <span className="flex items-center gap-1.5">
                <MethodBadge method={hit.request.method} />
                <span className="truncate text-[12px] text-text-primary">{hit.request.name}</span>
              </span>
              <span className="block truncate text-[10px] text-text-tertiary">
                {[collection.name, ...hit.path].join(" / ")}
              </span>
            </button>
          ))}
        </div>
      )}
    </div>
  )
}

function CollectionHeader({
  collection,
  actions,
}: {
  collection: ApiCollection
  actions: SidebarActions
}) {
  const entries: MenuEntry[] = [
    {
      label: "New Folder…",
      onSelect: () => {
        actions.onNewFolder(collection.id)
      },
    },
    {
      label: "Rename…",
      onSelect: () => {
        actions.onRenameCollection(collection.id)
      },
    },
    {
      label: "Collection Auth…",
      onSelect: () => {
        actions.onCollectionAuth(collection.id)
      },
    },
    {
      label: "Collection Variables…",
      onSelect: () => {
        actions.onCollectionVariables(collection.id)
      },
    },
    {
      label: "Export…",
      onSelect: () => {
        actions.onExportCollection(collection)
      },
    },
    {
      label: "Run Collection…",
      separatorBefore: true,
      onSelect: () => {
        actions.onRunCollection(collection.id)
      },
    },
    {
      label: "Delete Collection…",
      danger: true,
      separatorBefore: true,
      onSelect: () => {
        actions.onDeleteCollection(collection)
      },
    },
  ]

  return (
    <div className="flex items-center gap-1 px-3 pt-2">
      <span className="truncate text-[12px] font-bold text-text-primary">{collection.name}</span>
      {collection.auth.type === "none" ? null : (
        <span className="text-text-tertiary" title="This collection sets auth for its requests">
          <Lock size={10} />
        </span>
      )}
      <span className="ml-auto text-[10px] text-text-tertiary">
        {requestCount(collection.items)}
      </span>
      <ApiMenuButton label={`${collection.name} actions`} entries={entries}>
        <MoreHorizontal size={13} />
      </ApiMenuButton>
    </div>
  )
}
