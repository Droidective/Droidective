import { Atom } from "lucide-react"

import { iconForFeature, iconForRole } from "@/lib/icons"
import type { Role } from "@/lib/roles"
import type { FeatureSummary } from "@/lib/wire"

/**
 * One role's card — the Mac's `RoleCardView`.
 *
 * The tool count and the preview chips are the point of the card: "QA /
 * Tester" says nothing concrete, and "18 tools · Logcat · Screenshot · +16"
 * says exactly what picking it does. Both follow the React Native switch live,
 * which is how that switch explains itself without a paragraph.
 */
export function RoleCard({
  role,
  features,
  curated,
  stackAdds,
  onPick,
}: {
  role: Role
  features: readonly FeatureSummary[]
  /** The role's ids with the RN stack folded in, if it is wanted. */
  curated: readonly string[]
  stackAdds: boolean
  onPick: () => void
}) {
  const RoleGlyph = iconForRole(role.id)
  const byID = new Map(features.map((feature) => [feature.id, feature]))
  const preview = curated.slice(0, 2).flatMap((id) => {
    const feature = byID.get(id)
    return feature === undefined ? [] : [feature]
  })

  return (
    <button
      type="button"
      onClick={onPick}
      aria-label={`${role.label} — sets up the sidebar with ${String(curated.length)} tools`}
      className="flex min-h-[168px] flex-col items-start gap-2.5 rounded-xl border border-border-subtle bg-bg-surface p-4 text-left transition hover:border-accent hover:shadow-lg"
    >
      <div className="flex w-full items-start justify-between gap-2">
        <span
          className="flex h-9 w-9 items-center justify-center rounded-lg"
          style={{ background: "color-mix(in srgb, var(--color-accent) 12%, transparent)" }}
        >
          <RoleGlyph size={18} className="text-accent" />
        </span>
        <span
          className={`flex shrink-0 items-center gap-1 rounded-full bg-bg-root px-2 py-0.5 text-[11px] ${
            stackAdds ? "text-accent" : "text-text-secondary"
          }`}
        >
          {stackAdds ? <Atom size={9} /> : null}
          {curated.length} tools
        </span>
      </div>

      <p className="text-[15px] font-semibold text-text-primary">{role.label}</p>
      <p className="text-text-secondary">{role.blurb}</p>

      {/* The first curated tools as chips, ending in "+N" — the concrete
          preview of what this card does. */}
      <div className="mt-auto flex flex-wrap items-center gap-1.5 pt-1">
        {preview.map((feature) => (
          <PreviewChip key={feature.id} feature={feature} />
        ))}
        {curated.length > preview.length ? (
          <span className="text-[11px] text-text-secondary">
            +{curated.length - preview.length}
          </span>
        ) : null}
      </div>
    </button>
  )
}

/** One curated tool, named and glyphed as the sidebar would show it. */
function PreviewChip({ feature }: { feature: FeatureSummary }) {
  const Glyph = iconForFeature(feature.id, feature.category)
  return (
    <span className="flex items-center gap-1 rounded-full border border-border-subtle bg-bg-root px-2 py-0.5 text-[11px] text-text-secondary">
      <Glyph size={10} />
      {feature.title}
    </span>
  )
}
