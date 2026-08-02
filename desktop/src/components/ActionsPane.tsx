import { useMemo, useState } from "react"
import { Search } from "lucide-react"
import { ActionForm } from "@/components/ActionForm"
import { cn } from "@/lib/cn"
import { iconForCategory } from "@/lib/icons"
import { categoryLabel, groupByCategory, searchActions } from "@/lib/palette"
import type { Device, FeatureSummary } from "@/lib/wire"

/**
 * The command palette, laid out like the Mac app's sidebar: a search field
 * over category-grouped two-line rows, with the selection's detail beside it.
 */
export function ActionsPane({
  features,
  device,
}: {
  features: FeatureSummary[]
  device: Device | null
}) {
  const [query, setQuery] = useState("")
  const [selectedID, setSelectedID] = useState<string | null>(null)

  const matches = useMemo(() => searchActions(features, query), [features, query])
  const groups = useMemo(() => groupByCategory(matches), [matches])
  // Typing narrows the list; the highlighted row follows it rather than
  // pointing at something no longer shown.
  const selected = matches.find((feature) => feature.id === selectedID) ?? matches[0] ?? null

  return (
    <div className="flex min-h-0 flex-1">
      <aside className="flex w-[340px] shrink-0 flex-col border-r border-border-subtle bg-bg-chrome">
        <div className="px-3 py-2.5">
          <SearchField value={query} onChange={setQuery} count={matches.length} />
        </div>

        <div className="min-h-0 flex-1 overflow-y-auto pb-2">
          {matches.length === 0 ? (
            <p className="px-4 py-8 text-center text-text-tertiary">Nothing matches “{query}”.</p>
          ) : (
            groups.map((group) => (
              <section key={group.category}>
                <h3 className="px-4 pb-1 pt-3.5 text-[10.5px] font-medium uppercase tracking-[0.06em] text-text-tertiary">
                  {categoryLabel(group.category)}
                </h3>
                {group.features.map((feature) => (
                  <FeatureRow
                    key={feature.id}
                    feature={feature}
                    active={feature.id === selected?.id}
                    onSelect={() => {
                      setSelectedID(feature.id)
                    }}
                  />
                ))}
              </section>
            ))
          )}
        </div>
      </aside>

      <div className="min-w-0 flex-1 bg-bg-root">
        {selected ? (
          // Keyed by id so each feature's form starts from its own defaults
          // instead of inheriting the previous one's state.
          <ActionForm key={selected.id} feature={selected} device={device} />
        ) : (
          <p className="p-6 text-text-tertiary">Pick an action.</p>
        )}
      </div>
    </div>
  )
}

function SearchField({
  value,
  onChange,
  count,
}: {
  value: string
  onChange: (value: string) => void
  count: number
}) {
  return (
    <div className="flex items-center gap-2 rounded-lg bg-bg-raised px-2.5 py-1.5 focus-within:ring-1 focus-within:ring-accent/60">
      <Search size={13} className="shrink-0 text-text-tertiary" />
      <input
        value={value}
        placeholder={`Search ${String(count)} actions…`}
        // oxlint-disable-next-line jsx-a11y/no-autofocus
        autoFocus
        aria-label="Search actions"
        onChange={(event) => {
          onChange(event.target.value)
        }}
        onKeyDown={(event) => {
          if (event.key === "Escape") onChange("")
        }}
        className="min-w-0 flex-1 bg-transparent text-[13px] text-text-primary outline-none placeholder:text-text-tertiary"
      />
    </div>
  )
}

function FeatureRow({
  feature,
  active,
  onSelect,
}: {
  feature: FeatureSummary
  active: boolean
  onSelect: () => void
}) {
  const Icon = iconForCategory(feature.category)
  return (
    <button
      type="button"
      onClick={onSelect}
      className={cn(
        "flex w-full items-start gap-2.5 px-4 py-1.5 text-left transition-colors",
        active ? "bg-accent/12" : "hover:bg-white/[0.04]",
      )}
    >
      <Icon size={17} className="mt-[3px] shrink-0 text-accent" />
      <span className="min-w-0">
        <span className="block truncate text-[13.5px] text-text-primary">{feature.title}</span>
        {feature.subtitle ? (
          <span className="block truncate text-[11.5px] text-text-secondary">
            {feature.subtitle}
          </span>
        ) : null}
      </span>
    </button>
  )
}
