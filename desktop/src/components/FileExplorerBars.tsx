import { useState } from "react"
import { ChevronRight, FolderPlus, RefreshCw, X } from "lucide-react"
import { Banner, Button, TextInput } from "@/components/Controls"
import type { FileNotice } from "@/hooks/useFileActions"
import { asDaemonError, revealPath } from "@/lib/daemon"
import { breadcrumbs, pasteLabel, type FileClipboard } from "@/lib/files"
import type { DaemonError, FileEntry } from "@/lib/wire"

/** The path, the clipboard, and everything that acts on the whole folder. */
export function FileToolbar({
  components,
  rootMode,
  onCrumb,
  clipboard,
  onPaste,
  onClearClipboard,
  allSelected,
  canSelect,
  onSelectAll,
  onNewFolder,
  rooted,
  onRootMode,
  busy,
  onRefresh,
}: {
  components: string[]
  rootMode: boolean
  onCrumb: (depth: number) => void
  clipboard: FileClipboard | null
  onPaste: () => void
  onClearClipboard: () => void
  allSelected: boolean
  canSelect: boolean
  onSelectAll: () => void
  onNewFolder: () => void
  rooted: boolean
  onRootMode: (on: boolean) => void
  busy: boolean
  onRefresh: () => void
}) {
  return (
    <div className="flex shrink-0 flex-wrap items-center gap-2 border-b border-border-subtle bg-bg-chrome px-3 py-2">
      <nav className="flex min-w-0 flex-1 items-center overflow-x-auto" aria-label="Path">
        {breadcrumbs(components, rootMode).map((crumb, index) => (
          <span key={`${crumb.label}-${String(crumb.depth)}`} className="flex items-center">
            {index === 0 ? null : <ChevronRight size={12} className="shrink-0 text-text-tertiary" />}
            <button
              type="button"
              onClick={() => {
                onCrumb(crumb.depth)
              }}
              className="whitespace-nowrap rounded px-1.5 py-0.5 text-[13px] text-text-secondary hover:bg-white/[0.06] hover:text-text-primary"
            >
              {crumb.label}
            </button>
          </span>
        ))}
      </nav>

      {clipboard === null ? null : (
        <span className="flex items-center gap-1">
          <Button onClick={onPaste} disabled={busy}>
            {pasteLabel(clipboard)}
          </Button>
          <button
            type="button"
            onClick={onClearClipboard}
            title="Clear clipboard"
            aria-label="Clear clipboard"
            className="rounded p-1 text-text-tertiary hover:bg-white/[0.06] hover:text-text-primary"
          >
            <X size={13} />
          </button>
        </span>
      )}

      <Button onClick={onSelectAll} disabled={!canSelect}>
        {allSelected ? "Deselect All" : "Select All"}
      </Button>
      <Button onClick={onNewFolder} disabled={busy}>
        <span className="flex items-center gap-1.5">
          <FolderPlus size={13} />
          New Folder
        </span>
      </Button>

      {/* A button-style toggle, which is what `Toggle(...).toggleStyle(.button)`
          draws on the Mac — not a switch. */}
      {rooted ? (
        <Button
          tone={rootMode ? "primary" : "default"}
          onClick={() => {
            onRootMode(!rootMode)
          }}
          title="Browse the whole filesystem as root"
        >
          Root
        </Button>
      ) : null}

      <Button onClick={onRefresh} disabled={busy} title="Refresh">
        <RefreshCw size={13} className={busy ? "animate-spin" : undefined} />
      </Button>
    </div>
  )
}

/** Bulk verbs for whatever is checked. */
export function FileSelectionBar({
  targets,
  busy,
  onCopy,
  onCut,
  onPull,
  onDelete,
}: {
  targets: FileEntry[]
  busy: boolean
  onCopy: () => void
  onCut: () => void
  onPull: () => void
  /** Opens the confirmation; the pane owns it, as the Mac's view does. */
  onDelete: () => void
}) {
  return (
    <div className="flex shrink-0 items-center gap-2 border-b border-border-subtle bg-bg-surface px-3 py-1.5">
      <span className="text-text-secondary">{targets.length} selected</span>
      <span className="flex-1" />
      <Button onClick={onCopy} disabled={busy}>
        Copy
      </Button>
      <Button onClick={onCut} disabled={busy}>
        Cut
      </Button>
      <Button onClick={onPull} disabled={busy}>
        Pull to this computer
      </Button>
      <Button tone="danger" disabled={busy} onClick={onDelete}>
        Delete
      </Button>
    </div>
  )
}

/**
 * The Mac's `.alert("New Folder")` — a titled sheet with one field, Create and
 * Cancel — rather than an inline row.
 */
export function NewFolderDialog({
  onCreate,
  onCancel,
}: {
  onCreate: (name: string) => void
  onCancel: () => void
}) {
  const [name, setName] = useState("")
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-8">
      <button
        type="button"
        aria-label="Cancel"
        onClick={onCancel}
        className="absolute inset-0 cursor-default"
      />
      <dialog
        open
        aria-label="New Folder"
        className="relative w-[380px] max-w-full rounded-xl border border-border-subtle bg-bg-raised p-5 text-text-primary shadow-2xl"
      >
        <h2 className="mb-3 text-[14px] font-medium text-text-primary">New Folder</h2>
        <TextInput
          value={name}
          onChange={setName}
          placeholder="Folder name"
          // The sheet opened because someone asked for it; landing anywhere
          // else would cost a click every time, and the Mac's alert focuses
          // its field too.
          // oxlint-disable-next-line jsx-a11y/no-autofocus
          autoFocus
          onKeyDown={(event) => {
            if (event.key === "Enter") onCreate(name)
            if (event.key === "Escape") onCancel()
          }}
        />
        <div className="mt-4 flex justify-end gap-2">
          <Button onClick={onCancel}>Cancel</Button>
          <Button
            tone="primary"
            onClick={() => {
              onCreate(name)
            }}
          >
            Create
          </Button>
        </div>
      </dialog>
    </div>
  )
}

/** What is running, what failed, and what an operation left behind. */
export function FileNotices({
  busy,
  error,
  notice,
  onDismiss,
}: {
  busy: string | null
  error: DaemonError | null
  notice: FileNotice | null
  onDismiss: () => void
}) {
  const [failure, setFailure] = useState<string | null>(null)
  if (busy === null && error === null && notice === null) return null
  const landed = notice?.path
  return (
    <div className="flex shrink-0 flex-col gap-2 px-3 pt-3">
      {busy === null ? null : <Banner tone="warn">{busy}…</Banner>}
      {error === null ? null : (
        <Banner tone="error">
          {error.message}
          {error.detail === null ? null : <div className="mt-1 opacity-70">{error.detail}</div>}
        </Banner>
      )}
      {notice === null ? null : (
        <Banner tone={notice.ok ? "ok" : "error"}>
          <span className="flex flex-wrap items-center gap-2">
            {notice.message}
            {notice.detail === undefined ? null : (
              <span className="opacity-70">{notice.detail}</span>
            )}
            {landed === undefined ? null : (
              <button
                type="button"
                onClick={() => {
                  revealPath(landed).catch((thrown: unknown) => {
                    setFailure(asDaemonError(thrown).message)
                  })
                }}
                className="rounded-md bg-white/[0.06] px-2 py-0.5 text-[12px] hover:bg-white/[0.12]"
              >
                Show in folder
              </button>
            )}
            <button
              type="button"
              onClick={onDismiss}
              aria-label="Dismiss"
              className="text-text-tertiary hover:text-text-primary"
            >
              <X size={12} />
            </button>
            {failure === null ? null : <span className="text-danger">{failure}</span>}
          </span>
        </Banner>
      )}
    </div>
  )
}
