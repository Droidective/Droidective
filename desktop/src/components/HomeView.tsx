import { iconForCategory } from "@/lib/icons"
import { categoryLabel, sidebarSections } from "@/lib/sidebar"
import type { FeatureSummary } from "@/lib/wire"

/**
 * The permanent first tab: everything openable, as a grid.
 *
 * It mirrors the sidebar's order rather than ranking on its own, which is what
 * the Mac's launchpad does — two surfaces disagreeing about where a feature
 * sits is worse than either order being wrong.
 */
export function HomeView({
  features,
  sidebarOrder,
  categoryOrder,
  onOpen,
}: {
  features: FeatureSummary[]
  sidebarOrder: string[]
  categoryOrder: string[]
  onOpen: (id: string) => void
}) {
  const sections = sidebarSections(features, {
    query: "",
    sidebarOrder,
    categoryOrder,
    // Collapsing is a sidebar-space affordance, not a preference against the
    // feature, so Home shows a collapsed group's contents anyway.
    collapsedCategories: [],
  })
  const total = sections.reduce((count, section) => count + section.features.length, 0)

  return (
    <div className="h-full overflow-y-auto p-6">
      <header className="mb-5">
        <h1 className="text-[19px] font-semibold text-text-primary">Droidective</h1>
        <p className="mt-1 text-text-secondary">
          {total} features. Pick one here or from the sidebar — each opens in its own tab.
        </p>
      </header>

      {sections.map((section) => (
        <section key={section.category} className="mb-5">
          <h2 className="mb-2 text-[10.5px] font-medium uppercase tracking-[0.06em] text-text-tertiary">
            {categoryLabel(section.category)}
          </h2>
          <div className="grid grid-cols-[repeat(auto-fill,minmax(190px,1fr))] gap-2">
            {section.features.map((feature) => (
              <Tile
                key={feature.id}
                feature={feature}
                onOpen={() => {
                  onOpen(feature.id)
                }}
              />
            ))}
          </div>
        </section>
      ))}
    </div>
  )
}

function Tile({ feature, onOpen }: { feature: FeatureSummary; onOpen: () => void }) {
  const Icon = iconForCategory(feature.category)
  return (
    <button
      type="button"
      onClick={onOpen}
      title={feature.subtitle ?? feature.title}
      className="flex items-start gap-2.5 rounded-lg border border-border-subtle bg-bg-surface p-2.5 text-left transition-colors hover:border-accent/40 hover:bg-bg-raised"
    >
      <Icon size={17} className="mt-0.5 shrink-0 text-accent" />
      <span className="min-w-0">
        <span className="block truncate text-[13px] text-text-primary">{feature.title}</span>
        {feature.subtitle ? (
          <span className="line-clamp-2 text-[11px] text-text-secondary">{feature.subtitle}</span>
        ) : null}
      </span>
    </button>
  )
}
