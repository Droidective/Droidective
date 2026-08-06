import { useState } from "react"
import {
  FileNotices,
  FileSelectionBar,
  FileToolbar,
  NewFolderRow,
} from "@/components/FileExplorerBars"
import { FileInfoSheet } from "@/components/FileInfoSheet"
import { FileList } from "@/components/FileList"
import { FileRowMenu, type FileMenuTarget } from "@/components/FileRowMenu"
import { useFileActions, type FileActions } from "@/hooks/useFileActions"
import { useFileListing, type FileListing } from "@/hooks/useFileListing"
import { childPath, targetsFor } from "@/lib/files"
import type { Device } from "@/lib/wire"

/**
 * The device's storage — the Mac's File Explorer.
 *
 * The first screen here that *writes* to a device, so Delete is armed twice
 * before it runs, the way the Apps pane's destructive verbs are. Nothing is
 * decided in this file: navigation and the listing are `useFileListing`, the
 * verbs are `useFileActions`, and the rules both lean on are `lib/files.ts`.
 */
export function FileExplorerPane({ device }: { device: Device | null }) {
  const serial = device?.serial ?? null
  const listing = useFileListing(serial)
  const actions = useFileActions({
    serial,
    path: listing.path,
    rootMode: listing.rootMode,
    reload: listing.reload,
  })
  const [creating, setCreating] = useState(false)

  if (!device) {
    return <p className="p-6 text-text-tertiary">Connect a device to browse its storage.</p>
  }

  const busy = actions.busy !== null

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <FileToolbar
        components={listing.components}
        rootMode={listing.rootMode}
        onCrumb={listing.goTo}
        clipboard={actions.clipboard}
        onPaste={actions.paste}
        onClearClipboard={actions.forget}
        allSelected={listing.rows.length > 0 && listing.selection.size === listing.rows.length}
        canSelect={listing.rows.length > 0}
        onSelectAll={listing.selectAll}
        onNewFolder={() => {
          setCreating(true)
        }}
        rooted={listing.rooted}
        onRootMode={listing.setRootMode}
        busy={busy}
        onRefresh={listing.refresh}
      />

      {listing.selected.length === 0 ? null : (
        <FileSelectionBar
          targets={listing.selected}
          busy={busy}
          onCopy={() => {
            actions.remember(listing.selected, false)
          }}
          onCut={() => {
            actions.remember(listing.selected, true)
          }}
          onPull={() => {
            actions.pull(listing.selected)
          }}
          onDelete={() => {
            actions.remove(listing.selected)
          }}
        />
      )}

      {creating ? (
        <NewFolderRow
          onCreate={(name) => {
            setCreating(false)
            actions.createFolder(name)
          }}
          onCancel={() => {
            setCreating(false)
          }}
        />
      ) : null}

      <FileNotices
        busy={actions.busy}
        error={listing.error}
        notice={actions.notice}
        onDismiss={actions.dismissNotice}
      />

      <Contents listing={listing} actions={actions} serial={device.serial} />
    </div>
  )
}

/** The listing and the two things that float over it. */
function Contents({
  listing,
  actions,
  serial,
}: {
  listing: FileListing
  actions: FileActions
  serial: string
}) {
  const [menu, setMenu] = useState<FileMenuTarget | null>(null)
  const [infoPath, setInfoPath] = useState<string | null>(null)

  return (
    <>
      <FileList
        entries={listing.entries}
        selection={listing.selection}
        atRoot={listing.atRoot}
        onUp={listing.up}
        onOpen={listing.open}
        onToggle={listing.toggle}
        onContextMenu={(entry, x, y) => {
          setMenu({ entry, x, y })
        }}
      />

      {menu === null ? null : (
        <FileRowMenu
          at={menu}
          targets={targetsFor(menu.entry, listing.selection, listing.rows)}
          onDismiss={() => {
            setMenu(null)
          }}
          onInfo={(entry) => {
            setInfoPath(childPath(listing.path, entry.name))
          }}
          onCopy={(targets) => {
            actions.remember(targets, false)
          }}
          onCut={(targets) => {
            actions.remember(targets, true)
          }}
          onPull={actions.pull}
          onDelete={actions.remove}
        />
      )}

      {infoPath === null ? null : (
        <FileInfoSheet
          serial={serial}
          path={infoPath}
          asRoot={listing.rootMode}
          onDismiss={() => {
            setInfoPath(null)
          }}
        />
      )}
    </>
  )
}
