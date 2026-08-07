import { useMemo, useState } from "react"
import { Switch } from "@/components/Controls"
import { canDisable, isEnabled, isGroupEnabled } from "@/lib/catalog"
import { iconForFeature } from "@/lib/icons"
import { rankBy } from "@/lib/ordering"
import { categoryLabel, sidebarFeatures } from "@/lib/sidebar"
import type { FeatureSummary } from "@/lib/wire"

interface Group {
  category: string
  members: FeatureSummary[]
}

/**
 * The feature catalog — the Mac's `CatalogView`.
 *
 * Everything is on by default and this is for turning things *off*; there is no
 * Restore button because there is nothing to restore to. A disabled feature
 * leaves the sidebar but stays searchable, so this is decluttering rather than
 * removal.
 *
 * Rows follow the sidebar's own order, and a whole group toggles from a
 * right-click on its header — both as the Mac does. Reordering and pinning stay
 * on the sidebar rows, which is why neither is offered here.
 */
export function CatalogPane({
  features,
  disabled,
  sidebarOrder,
  categoryOrder,
  onSetEnabled,
  onSetGroupEnabled,
}: {
  features: FeatureSummary[]
  disabled: string[]
  sidebarOrder: string[]
  categoryOrder: string[]
  onSetEnabled: (id: string, enabled: boolean) => void
  onSetGroupEnabled: (members: FeatureSummary[], enabled: boolean) => void
}) {
  const groups = useMemo(
    () => catalogGroups(features, sidebarOrder, categoryOrder),
    [categoryOrder, features, sidebarOrder],
  )

  return (
    <div className="min-h-0 flex-1 overflow-y-auto pb-4">
      {groups.map((group) => (
        <GroupSection
          key={group.category}
          group={group}
          disabled={disabled}
          onSetEnabled={onSetEnabled}
          onSetGroupEnabled={onSetGroupEnabled}
        />
      ))}
    </div>
  )
}

/** The sidebar's own order, grouped by category. */
function catalogGroups(
  features: readonly FeatureSummary[],
  sidebarOrder: readonly string[],
  categoryOrder: readonly string[],
): Group[] {
  const listable = rankBy(sidebarFeatures(features), sidebarOrder, (feature) => feature.id)
  const present = rankBy(
    [...new Set(listable.map((feature) => feature.category))],
    categoryOrder,
    (id) => id,
  )
  return present
    .map((category) => ({
      category,
      members: listable.filter((feature) => feature.category === category),
    }))
    .filter((group) => group.members.length > 0)
}

function GroupSection({
  group,
  disabled,
  onSetEnabled,
  onSetGroupEnabled,
}: {
  group: Group
  disabled: string[]
  onSetEnabled: (id: string, enabled: boolean) => void
  onSetGroupEnabled: (members: FeatureSummary[], enabled: boolean) => void
}) {
  const [menu, setMenu] = useState<{ x: number; y: number } | null>(null)
  const on = isGroupEnabled(group.members, disabled)

  return (
    <section>
      <h2 className="sticky top-0 z-10 bg-bg-root">
        <button
          type="button"
          onContextMenu={(event) => {
            event.preventDefault()
            setMenu({ x: event.clientX, y: event.clientY })
          }}
          className="w-full px-4 pb-1.5 pt-3 text-left text-[13px] text-text-primary"
          title="Right-click to enable or disable the whole group"
        >
          {categoryLabel(group.category)}
        </button>
      </h2>

      {group.members.map((feature) => (
        <Row
          key={feature.id}
          feature={feature}
          enabled={isEnabled(feature.id, disabled)}
          onChange={(next) => {
            onSetEnabled(feature.id, next)
          }}
        />
      ))}

      {menu === null ? null : (
        <GroupMenu
          x={menu.x}
          y={menu.y}
          enabled={on}
          onChoose={() => {
            onSetGroupEnabled(group.members, !on)
            setMenu(null)
          }}
          onDismiss={() => {
            setMenu(null)
          }}
        />
      )}
    </section>
  )
}

function Row({
  feature,
  enabled,
  onChange,
}: {
  feature: FeatureSummary
  enabled: boolean
  onChange: (enabled: boolean) => void
}) {
  const Icon = iconForFeature(feature.id, feature.category)
  return (
    <div className="flex items-center gap-2.5 px-4 py-1">
      <Icon size={16} className="shrink-0 text-text-tertiary" />
      <div className="min-w-0 flex-1">
        <p className="text-text-primary">{feature.title}</p>
        {feature.subtitle === null ? null : (
          <p className="truncate text-[11.5px] text-text-tertiary">{feature.subtitle}</p>
        )}
      </div>
      <Switch
        checked={enabled}
        onChange={onChange}
        ariaLabel={feature.title}
        // The app's own chrome cannot be turned off: there is nothing to
        // declutter, and no way back if one vanished.
        disabled={!canDisable(feature)}
      />
    </div>
  )
}

function GroupMenu({
  x,
  y,
  enabled,
  onChoose,
  onDismiss,
}: {
  x: number
  y: number
  enabled: boolean
  onChoose: () => void
  onDismiss: () => void
}) {
  return (
    <>
      <button
        type="button"
        aria-label="Dismiss menu"
        onClick={onDismiss}
        onContextMenu={(event) => {
          event.preventDefault()
          onDismiss()
        }}
        className="fixed inset-0 z-40 cursor-default"
      />
      <div
        style={{ left: x, top: y }}
        className="fixed z-50 min-w-[150px] rounded-md border border-border-subtle bg-bg-raised py-1 shadow-xl"
      >
        <button
          type="button"
          onClick={onChoose}
          className="w-full px-3 py-1 text-left text-text-primary hover:bg-white/[0.08]"
        >
          {enabled ? "Disable all" : "Enable all"}
        </button>
      </div>
    </>
  )
}
