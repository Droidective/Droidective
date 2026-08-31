import { useState } from "react"
import { ChevronDown, ChevronRight, Folder, FolderOpen, ShieldCheck } from "lucide-react"

import { ApiContextMenu, type MenuEntry } from "@/components/api/ApiMenu"
import { MethodBadge } from "@/components/api/ApiKit"
import { itemId, type ApiCollection, type ApiItem, type SavedRequest } from "@/lib/api/model"
import { folderChoices, requestCount, rows } from "@/lib/api/tree"
import { cn } from "@/lib/cn"

/** What a row's menu can ask for. Raised by the pane, as the Mac's sheets are. */
export interface TreeActions {
  onOpen: (request: SavedRequest, collectionId: string) => void
  onNewFolderInside: (collectionId: string, parentId: string) => void
  onRenameFolder: (collectionId: string, folderId: string) => void
  onDuplicate: (collectionId: string, id: string) => void
  onMove: (collectionId: string, id: string, folderId: string | null) => void
  onDeleteRequest: (collectionId: string, request: SavedRequest) => void
  onDeleteFolder: (collectionId: string, folderId: string, name: string, count: number) => void
}

/**
 * One collection's rows — the Mac's `ApiItemRow`, flattened.
 *
 * Every item is its own row, folders included, so all of them share one set of
 * insets. Nesting a folder's children inside its own row gave them different
 * spacing from the requests above, which reads as an uneven gap rather than as
 * structure.
 */
export function ApiTree({
  collection,
  expanded,
  onToggleFolder,
  actions,
}: {
  collection: ApiCollection
  expanded: ReadonlySet<string>
  onToggleFolder: (id: string) => void
  actions: TreeActions
}) {
  const [menu, setMenu] = useState<{ item: ApiItem; x: number; y: number } | null>(null)

  return (
    <>
      {rows(collection.items, expanded).map((row) => (
        <TreeRow
          key={itemId(row.item)}
          item={row.item}
          depth={row.depth}
          open={row.item.kind === "folder" && expanded.has(row.item.folder.id)}
          onActivate={() => {
            if (row.item.kind === "request") actions.onOpen(row.item.request, collection.id)
            else onToggleFolder(row.item.folder.id)
          }}
          onMenu={(x, y) => {
            setMenu({ item: row.item, x, y })
          }}
        />
      ))}
      {menu === null ? null : (
        <ApiContextMenu
          at={{ x: menu.x, y: menu.y }}
          entries={entriesFor(menu.item, collection, actions)}
          onDismiss={() => {
            setMenu(null)
          }}
        />
      )}
    </>
  )
}

/**
 * The disclosure column is reserved on every row, so a request's method badge
 * lines up with the folder names above it instead of hanging a few points off.
 */
function TreeRow({
  item,
  depth,
  open,
  onActivate,
  onMenu,
}: {
  item: ApiItem
  depth: number
  open: boolean
  onActivate: () => void
  onMenu: (x: number, y: number) => void
}) {
  return (
    <button
      type="button"
      onClick={onActivate}
      onContextMenu={(event) => {
        event.preventDefault()
        onMenu(event.clientX, event.clientY)
      }}
      style={{ paddingLeft: 8 + depth * 12 }}
      className={cn(
        "flex h-6 w-full items-center gap-1.5 pr-2 text-left",
        "text-[12px] text-text-primary hover:bg-bg-raised",
      )}
    >
      {item.kind === "folder" ? (
        <>
          <span className="w-3 shrink-0 text-text-tertiary">
            {open ? <ChevronDown size={11} /> : <ChevronRight size={11} />}
          </span>
          <span className="text-text-tertiary">
            {open ? <FolderOpen size={11} /> : <Folder size={11} />}
          </span>
          <span className="truncate font-medium">{item.folder.name}</span>
          <span className="ml-auto text-[10px] text-text-tertiary">
            {requestCount(item.folder.items)}
          </span>
        </>
      ) : (
        <>
          <span className="w-3 shrink-0" />
          <MethodBadge method={item.request.method} />
          <span className="truncate">{item.request.name}</span>
          {item.request.assertions.length > 0 ? (
            <span
              className="ml-auto text-text-tertiary"
              title={`${item.request.assertions.length} test(s)`}
            >
              <ShieldCheck size={11} />
            </span>
          ) : null}
        </>
      )}
    </button>
  )
}

/**
 * A row's menu, matching the Mac's item by item.
 *
 * The moving item's own subtree is not offered as a destination — the tree
 * refuses those moves, so listing them would be listing choices that do
 * nothing.
 */
function entriesFor(
  item: ApiItem,
  collection: ApiCollection,
  actions: TreeActions,
): MenuEntry[] {
  const id = itemId(item)
  const entries: MenuEntry[] = []

  if (item.kind === "folder") {
    entries.push(
      {
        label: "New Folder Inside…",
        onSelect: () => {
          actions.onNewFolderInside(collection.id, item.folder.id)
        },
      },
      {
        label: "Rename…",
        onSelect: () => {
          actions.onRenameFolder(collection.id, item.folder.id)
        },
      },
    )
  }

  entries.push(
    {
      label: "Duplicate",
      separatorBefore: item.kind === "folder",
      onSelect: () => {
        actions.onDuplicate(collection.id, id)
      },
    },
    { label: "Move to", heading: true },
    {
      label: "Top level",
      onSelect: () => {
        actions.onMove(collection.id, id, null)
      },
    },
    ...folderChoices(collection.items, id).map((choice) => ({
      label: choice.name,
      onSelect: () => {
        actions.onMove(collection.id, id, choice.id)
      },
    })),
    item.kind === "request"
      ? {
          label: "Delete Request…",
          danger: true,
          separatorBefore: true,
          onSelect: () => {
            actions.onDeleteRequest(collection.id, item.request)
          },
        }
      : {
          label: "Delete Folder…",
          danger: true,
          separatorBefore: true,
          onSelect: () => {
            actions.onDeleteFolder(
              collection.id,
              item.folder.id,
              item.folder.name,
              requestCount(item.folder.items),
            )
          },
        },
  )
  return entries
}
