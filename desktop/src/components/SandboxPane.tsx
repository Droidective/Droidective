import { useCallback, useEffect, useState } from "react"
import { CornerLeftUp, Download, File, Folder, Lock } from "lucide-react"
import { Banner } from "@/components/Controls"
import { IconButton } from "@/components/Hub"
import { NoBundle } from "@/components/NoBundle"
import { NoDevice } from "@/components/screen"
import { useNotifications } from "@/hooks/useNotifications"
import { asDaemonError, sandboxList, sandboxPull } from "@/lib/daemon"
import { formatBytes, sandboxRoot } from "@/lib/appinfo"
import type { DaemonError, Device, FileEntry } from "@/lib/wire"

/**
 * Browse and pull an app's private files — the Mac's `SandboxBrowserView`.
 *
 * `run-as` only works against a debug build, so a release one gets an explicit
 * "App not debuggable" state rather than an error: it is the normal answer for
 * most apps on most devices, and reading it as a failure sends people looking
 * for a problem that is not there.
 *
 * Navigation is a component list rather than a raw path so the breadcrumb and
 * the listing can never disagree about where they are.
 */
export function SandboxPane({
  device,
  packageId,
}: {
  device: Device | null
  packageId: string | null
}) {
  const { show } = useNotifications()
  const [components, setComponents] = useState<string[]>([])
  const [entries, setEntries] = useState<FileEntry[] | null>(null)
  const [debuggable, setDebuggable] = useState(true)
  const [error, setError] = useState<DaemonError | null>(null)

  const serial = device?.serial ?? null
  const root = packageId === null ? "" : sandboxRoot(packageId)
  const path = components.length === 0 ? root : `${root}/${components.join("/")}`

  useEffect(() => {
    setComponents([])
  }, [packageId, serial])

  const load = useCallback(async () => {
    if (serial === null || packageId === null) return
    setEntries(null)
    setError(null)
    try {
      const listing = await sandboxList({ serial, packageId, path })
      setDebuggable(listing.debuggable)
      setEntries(listing.entries)
    } catch (thrown) {
      // Not `setEntries([])`: that renders "Empty directory", which beside the
      // error banner claims the listing succeeded and found nothing.
      setError(asDaemonError(thrown))
    }
  }, [packageId, path, serial])

  useEffect(() => {
    void load()
  }, [load])

  if (!device) return <NoDevice feature="sandbox-browser" title="Sandbox Browser" />
  if (packageId === null) return <NoBundle what="browse its sandbox" />
  if (!debuggable) return <NotDebuggable />

  const pull = (entry: FileEntry) => {
    if (serial === null) return
    void (async () => {
      try {
        const result = await sandboxPull({ serial, packageId, path: `${path}/${entry.name}` })
        const landed = result.paths.at(0)
        show({
          ok: true,
          message: `Pulled ${entry.name}`,
          ...(landed === undefined ? {} : { revealPath: landed }),
        })
      } catch (thrown) {
        show({ ok: false, message: asDaemonError(thrown).message })
      }
    })()
  }

  return (
    <div className="flex h-full flex-col">
      <Breadcrumb components={components} onNavigate={setComponents} />

      {error === null ? null : (
        <div className="p-3">
          <Banner tone="error">{error.message}</Banner>
        </div>
      )}

      {error === null ? (
        <Listing
          entries={entries}
          atRoot={components.length === 0}
          onUp={() => {
            setComponents((current) => current.slice(0, -1))
          }}
          onOpen={(name) => {
            setComponents((current) => [...current, name])
          }}
          onPull={pull}
        />
      ) : null}
    </div>
  )
}

/** The rows, with the ".." escape once there is somewhere to go back to. */
function Listing({
  entries,
  atRoot,
  onUp,
  onOpen,
  onPull,
}: {
  entries: FileEntry[] | null
  atRoot: boolean
  onUp: () => void
  onOpen: (name: string) => void
  onPull: (entry: FileEntry) => void
}) {
  if (entries === null) return <p className="p-5 text-text-tertiary">Reading files…</p>
  if (entries.length === 0 && atRoot) {
    return (
      <p className="flex min-h-0 flex-1 items-center justify-center text-text-tertiary">
        Empty directory
      </p>
    )
  }
  return (
    <div className="min-h-0 flex-1 overflow-y-auto">
      {atRoot ? null : (
        <button
          type="button"
          onClick={onUp}
          className="flex w-full items-center gap-2 px-3 py-1.5 text-left hover:bg-white/[0.04]"
        >
          <CornerLeftUp size={13} className="text-text-tertiary" />
          <span className="text-text-secondary">..</span>
        </button>
      )}
      {entries.map((entry) => (
        <Row
          key={entry.name}
          entry={entry}
          onOpen={() => {
            onOpen(entry.name)
          }}
          onPull={() => {
            onPull(entry)
          }}
        />
      ))}
    </div>
  )
}

/** Home / dir / dir — each segment jumps back to its own level. */
function Breadcrumb({
  components,
  onNavigate,
}: {
  components: string[]
  onNavigate: (components: string[]) => void
}) {
  return (
    <nav className="flex shrink-0 items-center gap-1 overflow-x-auto border-b border-border-subtle px-2 py-2">
      <Crumb
        label="Home"
        onClick={() => {
          onNavigate([])
        }}
      />
      {components.map((component, index) => (
        <span key={`${component}-${String(index)}`} className="flex items-center gap-1">
          <span className="text-text-tertiary">/</span>
          <Crumb
            label={component}
            onClick={() => {
              onNavigate(components.slice(0, index + 1))
            }}
          />
        </span>
      ))}
    </nav>
  )
}

function Crumb({ label, onClick }: { label: string; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="shrink-0 rounded px-1 text-accent hover:underline"
    >
      {label}
    </button>
  )
}

function Row({
  entry,
  onOpen,
  onPull,
}: {
  entry: FileEntry
  onOpen: () => void
  onPull: () => void
}) {
  return (
    <div className="flex items-center gap-2 px-3 py-1.5 hover:bg-white/[0.04]">
      {entry.isDir ? (
        <Folder size={13} className="shrink-0 text-text-secondary" />
      ) : (
        <File size={13} className="shrink-0 text-text-tertiary" />
      )}
      {entry.isDir ? (
        <button type="button" onClick={onOpen} className="min-w-0 flex-1 truncate text-left text-text-primary">
          {entry.name}
        </button>
      ) : (
        <span className="min-w-0 flex-1 truncate text-text-primary">{entry.name}</span>
      )}
      {entry.isDir ? null : (
        <>
          <span className="shrink-0 text-[11.5px] tabular-nums text-text-tertiary">
            {formatBytes(entry.size)}
          </span>
          <IconButton
            icon={<Download size={13} />}
            label="Pull to Downloads"
            onClick={onPull}
          />
        </>
      )}
    </div>
  )
}

function NotDebuggable() {
  return (
    <div className="flex h-full flex-col items-center justify-center gap-2 p-8 text-center">
      <Lock size={26} className="text-text-tertiary" />
      <h2 className="text-[15px] font-medium text-text-primary">App not debuggable</h2>
      <p className="max-w-sm text-text-secondary">
        run-as only works on debug builds. Install a debug build to browse its sandbox.
      </p>
    </div>
  )
}
