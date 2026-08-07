import { useState } from "react"
import { ConfirmDialog } from "@/components/ConfirmDialog"
import {
  FileNotices,
  FileSelectionBar,
  FileToolbar,
  NewFolderDialog,
} from "@/components/FileExplorerBars"
import { FileInfoSheet } from "@/components/FileInfoSheet"
import { FileList } from "@/components/FileList"
import { FileRowMenu, type FileMenuTarget } from "@/components/FileRowMenu"
import { useFileActions, type FileActions } from "@/hooks/useFileActions"
import { useFileListing, type FileListing } from "@/hooks/useFileListing"
import { childPath, deletePrompt, targetsFor } from "@/lib/files"
import type { Device, FileEntry } from "@/lib/wire"

/**
 * The device's storage — the Mac's File Explorer.
 *
 * The first screen here that *writes* to a device, so Delete asks first — the
 * same `confirmationDialog` `FileExplorerView` raises, naming what is about to
 * go. Nothing is decided in this file: navigation and the listing are
 * `useFileListing`, the verbs are `useFileActions`, and the rules both lean on
 * are `lib/files.ts`.
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
  const [confirmingDelete, setConfirmingDelete] = useState<FileEntry[] | null>(null)

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
            setConfirmingDelete(listing.selected)
          }}
        />
      )}

      <Dialogs
        creating={creating}
        onCreated={(name) => {
          setCreating(false)
          if (name !== null) actions.createFolder(name)
        }}
        deleting={confirmingDelete}
        onDeleted={(targets) => {
          setConfirmingDelete(null)
          if (targets !== null) actions.remove(targets)
        }}
      />

      <FileNotices
        busy={actions.busy}
        error={listing.error}
        notice={actions.notice}
        onDismiss={actions.dismissNotice}
      />

      <Contents
        listing={listing}
        actions={actions}
        serial={device.serial}
        onConfirmDelete={setConfirmingDelete}
      />
    </div>
  )
}

/**
 * The two sheets. Both are the Mac's: an alert to name a folder, and a
 * `confirmationDialog` naming what a Delete is about to remove.
 */
function Dialogs({
  creating,
  onCreated,
  deleting,
  onDeleted,
}: {
  creating: boolean
  /** null when cancelled. */
  onCreated: (name: string | null) => void
  deleting: FileEntry[] | null
  onDeleted: (targets: FileEntry[] | null) => void
}) {
  return (
    <>
      {creating ? (
        <NewFolderDialog
          onCreate={onCreated}
          onCancel={() => {
            onCreated(null)
          }}
        />
      ) : null}
      {deleting === null ? null : (
        <ConfirmDialog
          title={deletePrompt(deleting)}
          message="Removing a file from the device cannot be undone."
          confirmLabel="Delete"
          onConfirm={() => {
            onDeleted(deleting)
          }}
          onCancel={() => {
            onDeleted(null)
          }}
        />
      )}
    </>
  )
}

/** The listing and the two things that float over it. */
function Contents({
  listing,
  actions,
  serial,
  onConfirmDelete,
}: {
  listing: FileListing
  actions: FileActions
  serial: string
  onConfirmDelete: (targets: FileEntry[]) => void
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
          onDelete={onConfirmDelete}
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
