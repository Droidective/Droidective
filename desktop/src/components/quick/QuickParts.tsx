import { Search } from "lucide-react"
import { iconForFeature } from "@/lib/icons"
import { cn } from "@/lib/cn"
import type { Device, FeatureSummary } from "@/lib/wire"

/** The search field and what it is pointed at — the Mac panel's header. */
export function QuickHeader({
  query,
  onQuery,
  device,
  deviceCount,
}: {
  query: string
  onQuery: (query: string) => void
  device: Device | null
  deviceCount: number
}) {
  return (
    <div className="flex items-center gap-2 border-b border-border-subtle px-3 py-2.5">
      <Search size={14} className="shrink-0 text-text-tertiary" />
      <input
        // The panel is summoned to be typed into; anything else would need a
        // click first, which is a click the hotkey exists to avoid.
        // oxlint-disable-next-line jsx-a11y/no-autofocus
        autoFocus
        value={query}
        onChange={(event) => {
          onQuery(event.target.value)
        }}
        placeholder="Search actions…"
        aria-label="Search actions"
        className="min-w-0 flex-1 bg-transparent text-[13px] outline-none placeholder:text-text-tertiary"
      />
      <span className="shrink-0 text-[11.5px] text-text-tertiary">
        {device === null
          ? "No device"
          : deviceCount > 1
            ? `${String(deviceCount)} devices`
            : device.label}
      </span>
    </div>
  )
}

/** The root grid. Five across, as on the Mac. */
export function QuickGrid({
  features,
  highlight,
  armed,
  running,
  columns,
  onActivate,
  onHighlight,
}: {
  features: readonly FeatureSummary[]
  highlight: number
  armed: string | null
  running: boolean
  columns: number
  onActivate: (feature: FeatureSummary) => void
  onHighlight: (index: number) => void
}) {
  if (features.length === 0) return null
  return (
    <div
      className="grid gap-1.5"
      style={{ gridTemplateColumns: `repeat(${String(columns)}, minmax(0, 1fr))` }}
    >
      {features.map((feature, index) => {
        const Icon = iconForFeature(feature.id, feature.category)
        const isArmed = armed === feature.id
        return (
          <button
            key={feature.id}
            type="button"
            disabled={running}
            onMouseEnter={() => {
              onHighlight(index)
            }}
            onClick={() => {
              onActivate(feature)
            }}
            className={cn(
              "flex h-[74px] flex-col items-center justify-center gap-1.5 rounded-lg border px-1.5 text-center",
              index === highlight
                ? "border-accent/60 bg-accent/15"
                : "border-transparent bg-bg-surface",
              isArmed && "border-danger/60 bg-danger/15",
            )}
          >
            <Icon size={17} className={isArmed ? "text-danger" : "text-accent"} />
            <span className="line-clamp-2 text-[11.5px] leading-tight">
              {isArmed ? "Press again" : feature.title}
            </span>
          </button>
        )
      })}
    </div>
  )
}

/** A titled list of plain rows — commands, screens, and the device picker. */
export function QuickList({
  title,
  rows,
  footnote,
  onPick,
  onPickAll,
}: {
  title?: string
  rows: readonly { id: string; title: string }[]
  footnote?: string | undefined
  onPick: (id: string) => void
  onPickAll?: (() => void) | undefined
}) {
  return (
    <section className="mt-3 flex flex-col gap-1">
      {title === undefined ? null : (
        <h2 className="px-1 text-[11px] uppercase tracking-[0.06em] text-text-tertiary">{title}</h2>
      )}
      {rows.map((row) => (
        <button
          key={row.id}
          type="button"
          onClick={() => {
            onPick(row.id)
          }}
          className="rounded-md px-2 py-1.5 text-left hover:bg-white/[0.06]"
        >
          {row.title}
        </button>
      ))}
      {onPickAll === undefined ? null : (
        <button
          type="button"
          onClick={onPickAll}
          className="rounded-md px-2 py-1.5 text-left text-accent hover:bg-white/[0.06]"
        >
          All devices
        </button>
      )}
      {footnote === undefined ? null : (
        <p className="px-2 pt-1 text-[11.5px] text-text-tertiary">{footnote}</p>
      )}
    </section>
  )
}

/** What the last run said — the panel's equivalent of the in-app toast. */
export function QuickFooter({
  outcome,
  armed,
}: {
  outcome: { message: string; ok: boolean } | null
  armed: boolean
}) {
  return (
    <div className="flex min-h-[34px] items-center gap-2 border-t border-border-subtle px-3 py-1.5 text-[11.5px]">
      {armed ? (
        <span className="text-danger">Press Enter again to confirm.</span>
      ) : outcome === null ? (
        <span className="text-text-tertiary">Enter runs · Esc closes</span>
      ) : (
        <span className={outcome.ok ? "text-text-secondary" : "text-danger"}>{outcome.message}</span>
      )}
    </div>
  )
}
