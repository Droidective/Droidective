import { useCallback, useEffect, useMemo, useState } from "react"
import { Clipboard, Download, RefreshCw, Search } from "lucide-react"
import { NoDevice } from "@/components/NoDevice"
import { Banner, Button } from "@/components/Controls"
import { asDaemonError, copyText, deviceProps, exportText } from "@/lib/daemon"
import {
  countRows,
  propertiesText,
  propertyGroups,
  summary,
  type PropertyGroup,
} from "@/lib/deviceinfo"
import type { DaemonError, Device } from "@/lib/wire"

/**
 * Every property the device answers, searchable — the Mac's Device Info screen.
 *
 * One `getprop` on open rather than a poll: a device answers over a thousand
 * properties and almost none of them change while you are reading them.
 */
export function DeviceInfoPane({ device }: { device: Device | null }) {
  const [properties, setProperties] = useState<Record<string, string>>({})
  const [query, setQuery] = useState("")
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<DaemonError | null>(null)
  const [notice, setNotice] = useState<string | null>(null)

  const serial = device?.serial ?? null
  const load = useCallback(async () => {
    if (serial === null) return
    setLoading(true)
    setError(null)
    try {
      setProperties((await deviceProps(serial)).properties)
    } catch (thrown) {
      setError(asDaemonError(thrown))
    } finally {
      setLoading(false)
    }
  }, [serial])

  useEffect(() => {
    setProperties({})
    void load()
  }, [load])

  const groups = useMemo(() => propertyGroups(properties, query), [properties, query])
  const total = Object.keys(properties).length
  const shown = countRows(groups)

  const act = (run: () => Promise<string>) => () => {
    setError(null)
    run().then(setNotice, (thrown: unknown) => {
      setError(asDaemonError(thrown))
    })
  }

  if (!device) {
    return <NoDevice feature="device-info" title="Device Info" />
  }

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <Toolbar
        query={query}
        onQuery={setQuery}
        total={total}
        loading={loading}
        onCopy={act(async () => {
          await copyText(propertiesText(properties))
          return "Copied every property to the clipboard."
        })}
        onExport={act(
          async () =>
            `Saved to ${await exportText(`getprop_${device.serial}.txt`, propertiesText(properties))}`,
        )}
        onRefresh={() => void load()}
      />

      {error ? (
        <div className="px-3 pt-3">
          <Banner tone="error">
            {error.message}
            {error.detail ? <div className="mt-1 opacity-70">{error.detail}</div> : null}
          </Banner>
        </div>
      ) : null}
      {notice === null ? null : (
        <div className="px-3 pt-3">
          <Banner tone="ok">{notice}</Banner>
        </div>
      )}

      <div className="min-h-0 flex-1 overflow-y-auto p-4" data-selectable>
        {loading && total === 0 ? (
          <p className="py-8 text-center text-text-tertiary">Reading the device…</p>
        ) : total === 0 ? (
          <p className="py-8 text-center text-text-tertiary">No properties came back.</p>
        ) : (
          <>
            <Summary properties={properties} />
            {shown === 0 ? (
              <p className="py-8 text-center text-text-tertiary">Nothing matches “{query}”.</p>
            ) : (
              groups.map((group) => <Group key={group.prefix} group={group} />)
            )}
          </>
        )}
      </div>
    </div>
  )
}

function Toolbar({
  query,
  onQuery,
  total,
  loading,
  onCopy,
  onExport,
  onRefresh,
}: {
  query: string
  onQuery: (value: string) => void
  total: number
  loading: boolean
  onCopy: () => void
  onExport: () => void
  onRefresh: () => void
}) {
  return (
    <div className="flex shrink-0 items-center gap-2 border-b border-border-subtle bg-bg-chrome px-3 py-2">
      <div className="flex min-w-0 flex-1 items-center gap-2 rounded-md border border-border-subtle bg-bg-raised px-2.5 py-1 focus-within:border-accent">
        <Search size={13} className="shrink-0 text-text-tertiary" />
        <input
          value={query}
          aria-label="Filter properties"
          placeholder={total === 0 ? "Filter properties…" : `Filter ${total} properties…`}
          onChange={(event) => {
            onQuery(event.target.value)
          }}
          onKeyDown={(event) => {
            if (event.key === "Escape") onQuery("")
          }}
          className="min-w-0 flex-1 bg-transparent text-[13px] text-text-primary outline-none placeholder:text-text-tertiary"
        />
      </div>
      <Button onClick={onCopy} title="Copy every property">
        <Clipboard size={13} />
      </Button>
      <Button onClick={onExport} title="Export to ~/Downloads/Droidective">
        <Download size={13} />
      </Button>
      <Button onClick={onRefresh} disabled={loading} title="Read the device again">
        <RefreshCw size={13} className={loading ? "animate-spin" : undefined} />
      </Button>
    </div>
  )
}

/** The handful worth reading first, before the thousand that follow. */
function Summary({ properties }: { properties: Record<string, string> }) {
  const rows = summary(properties)
  if (rows.length === 0) return null
  return (
    <div className="mb-5 grid grid-cols-[repeat(auto-fill,minmax(190px,1fr))] gap-2">
      {rows.map((row) => (
        <div
          key={row.label}
          className="rounded-lg border border-border-subtle bg-bg-surface px-3 py-2"
        >
          <div className="text-[10.5px] uppercase tracking-[0.06em] text-text-tertiary">
            {row.label}
          </div>
          <div className="truncate text-[13px] text-text-primary" title={row.value}>
            {row.value}
          </div>
        </div>
      ))}
    </div>
  )
}

function Group({ group }: { group: PropertyGroup }) {
  return (
    <section className="mb-4">
      <h3 className="mb-1 text-[10.5px] font-medium uppercase tracking-[0.06em] text-text-tertiary">
        {group.prefix}
      </h3>
      <div className="overflow-hidden rounded-lg border border-border-subtle">
        {group.rows.map((row, index) => (
          <div
            key={row.key}
            className={
              index % 2 === 0
                ? "flex gap-4 px-3 py-1 font-mono text-[11.5px]"
                : "flex gap-4 bg-white/[0.02] px-3 py-1 font-mono text-[11.5px]"
            }
          >
            <span className="w-[46%] shrink-0 truncate text-text-secondary" title={row.key}>
              {row.key}
            </span>
            <span className="min-w-0 flex-1 break-all text-text-primary">{row.value}</span>
          </div>
        ))}
      </div>
    </section>
  )
}
