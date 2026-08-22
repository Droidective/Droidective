import { useCallback, useEffect, useState } from "react"
import { ShieldCheck } from "lucide-react"
import { Banner, Switch, TextInput } from "@/components/Controls"
import { NoBundle } from "@/components/NoBundle"
import { NoDevice } from "@/components/screen"
import { useNotifications } from "@/hooks/useNotifications"
import { asDaemonError, permissions as readPermissions, setPermission } from "@/lib/daemon"
import { permissionMatches } from "@/lib/appinfo"
import { cn } from "@/lib/cn"
import type { DaemonError, Device, Permission } from "@/lib/wire"

/**
 * Grant and revoke runtime permissions — the Mac's `PermissionsView`.
 *
 * One row per permission: the short name over the full one, a switch trailing.
 * While a change is in flight the whole list is disabled and the other rows dim,
 * exactly as the Mac does — a `pm grant` takes long enough that a second click
 * elsewhere would otherwise race the reload.
 */
export function PermissionsPane({
  device,
  packageId,
}: {
  device: Device | null
  packageId: string | null
}) {
  const { show } = useNotifications()
  const [entries, setEntries] = useState<Permission[] | null>(null)
  const [error, setError] = useState<DaemonError | null>(null)
  const [mutating, setMutating] = useState<string | null>(null)
  const [query, setQuery] = useState("")

  const serial = device?.serial ?? null
  const load = useCallback(async () => {
    if (serial === null || packageId === null) return
    setError(null)
    try {
      setEntries((await readPermissions(serial, packageId)).permissions)
    } catch (thrown) {
      setError(asDaemonError(thrown))
    }
  }, [packageId, serial])

  useEffect(() => {
    setEntries(null)
    void load()
  }, [load])

  if (!device) return <NoDevice feature="permissions" title="Permissions" />
  if (packageId === null) return <NoBundle what="inspect its permissions" />

  if (error !== null) {
    return (
      <div className="p-5">
        <Banner tone="error">{error.message}</Banner>
      </div>
    )
  }
  if (entries === null) return <p className="p-5 text-text-tertiary">Reading permissions…</p>
  if (entries.length === 0) return <NoRuntimePermissions />

  const change = (entry: Permission, granted: boolean) => {
    if (serial === null) return
    setMutating(entry.name)
    void (async () => {
      try {
        const result = await setPermission({
          serial,
          packageId,
          permission: entry.name,
          grant: granted,
        })
        show({ ok: result.ok, message: result.message })
      } catch (thrown) {
        show({ ok: false, message: asDaemonError(thrown).message })
      } finally {
        // Always re-read: `pm grant` refuses an install-time permission with a
        // message, and the switch must go back to what the device says.
        await load()
        setMutating(null)
      }
    })()
  }

  const shown = entries.filter((entry) => permissionMatches(entry, query))

  return (
    <div className="flex h-full flex-col">
      <div className="shrink-0 border-b border-border-subtle bg-bg-chrome px-3 py-2">
        <TextInput
          value={query}
          onChange={setQuery}
          placeholder="Filter permissions…"
          ariaLabel="Filter permissions"
        />
      </div>
      <div className="min-h-0 flex-1 overflow-y-auto">
        {shown.map((entry) => (
          <Row
            key={entry.name}
            entry={entry}
            // The Mac dims the other rows and locks the list while one grant is
            // in flight: `pm grant` takes long enough that a second click would
            // otherwise race this one's reload.
            dimmed={mutating !== null && mutating !== entry.name}
            locked={mutating !== null}
            onChange={(granted) => {
              change(entry, granted)
            }}
          />
        ))}
        {shown.length === 0 ? (
          <p className="p-5 text-text-tertiary">No permission matches “{query}”.</p>
        ) : null}
      </div>
    </div>
  )
}

function Row({
  entry,
  dimmed,
  locked,
  onChange,
}: {
  entry: Permission
  dimmed: boolean
  locked: boolean
  onChange: (granted: boolean) => void
}) {
  return (
    <div
      className={cn(
        "flex items-center gap-3 border-b border-border-subtle/50 px-3 py-2 transition-opacity",
        dimmed && "opacity-50",
      )}
    >
      <div className="min-w-0 flex-1">
        <p className="text-text-primary">{entry.shortName}</p>
        <p className="truncate text-[11.5px] text-text-tertiary" data-selectable>
          {entry.name}
        </p>
      </div>
      <Switch
        checked={entry.granted}
        onChange={(granted) => {
          if (!locked) onChange(granted)
        }}
        ariaLabel={entry.shortName}
      />
    </div>
  )
}

function NoRuntimePermissions() {
  return (
    <div className="flex h-full flex-col items-center justify-center gap-2 p-8 text-center">
      <ShieldCheck size={26} className="text-text-tertiary" />
      <h2 className="text-[15px] font-medium text-text-primary">No runtime permissions</h2>
      <p className="max-w-sm text-text-secondary">
        This app declares no runtime permissions, or it isn&rsquo;t installed.
      </p>
    </div>
  )
}
