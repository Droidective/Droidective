import { useState } from "react"
import { Atom, Grid3x3 } from "lucide-react"

import { RoleCard } from "@/components/RoleCard"
import { Switch } from "@/components/Controls"
import { canDisable } from "@/lib/catalog"
import { roleFeatureIDs, type Role, type RoleCatalogue } from "@/lib/roles"
import type { FeatureSummary } from "@/lib/wire"

/**
 * The first-launch role picker — the Mac's `RolePickerView`.
 *
 * Same three parts and the same copy: the question, six role cards, and the
 * quiet "show me everything" out. The React Native switch is its own control
 * rather than a seventh card for the reason the Mac's comment gives — role and
 * stack are different axes, and RN people were picking QA and concluding
 * Reactotron was not in the app.
 */
export function RolePicker({
  catalogue,
  features,
  onPick,
  onEverything,
  onDismiss,
}: {
  catalogue: RoleCatalogue
  features: readonly FeatureSummary[]
  onPick: (role: Role, includeReactNative: boolean) => void
  onEverything: () => void
  onDismiss: () => void
}) {
  const [includeReactNative, setIncludeReactNative] = useState(false)

  return (
    <div className="fixed inset-0 z-50 overflow-auto bg-bg-root">
      <div className="mx-auto flex max-w-3xl flex-col items-center gap-6 px-6 py-10">
        <Header />
        <ReactNativeSwitch checked={includeReactNative} onChange={setIncludeReactNative} />

        <div className="grid w-full grid-cols-1 gap-3 sm:grid-cols-2">
          {catalogue.roles.map((role) => (
            <RoleCard
              key={role.id}
              role={role}
              features={features}
              curated={roleFeatureIDs(role, catalogue, includeReactNative)}
              stackAdds={includeReactNative}
              onPick={() => {
                onPick(role, includeReactNative)
              }}
            />
          ))}
        </div>

        {/* Deliberately quiet next to the cards — one primary action per
            screen — but with a real hit area and the outcome in the label. */}
        {/* The count is the catalog's own — what "Manage features" would
            offer to turn off — so the two screens never disagree about how
            many tools there are. Hub members are already out: `features` is
            `sidebarFeatures`. */}
        <button
          type="button"
          onClick={onEverything}
          className="flex items-center gap-2 rounded-md px-3 py-1.5 text-text-secondary hover:bg-bg-surface hover:text-text-primary"
        >
          <Grid3x3 size={14} />
          Show me everything — all {features.filter((feature) => canDisable(feature)).length} tools
        </button>
        <button
          type="button"
          onClick={onDismiss}
          className="text-[11.5px] text-text-tertiary hover:text-text-secondary"
        >
          Not now
        </button>
      </div>
    </div>
  )
}

function Header() {
  return (
    <div className="flex flex-col items-center gap-2 text-center">
      <p className="text-[11px] font-semibold uppercase tracking-[0.12em] text-accent">
        Welcome to Droidective
      </p>
      <h1 className="text-[26px] font-bold text-text-primary">What do you do?</h1>
      <p className="max-w-md text-text-secondary">
        Pick a role and we&apos;ll start you with the tools you&apos;ll use most. Everything else
        is one click away — and you can change this anytime.
      </p>
    </div>
  )
}

function ReactNativeSwitch({
  checked,
  onChange,
}: {
  checked: boolean
  onChange: (checked: boolean) => void
}) {
  return (
    <div
      className="flex w-full items-start gap-3 rounded-xl border px-4 py-3"
      style={{
        borderColor: `color-mix(in srgb, var(--color-accent) ${checked ? "45%" : "15%"}, transparent)`,
        background: `color-mix(in srgb, var(--color-accent) ${checked ? "10%" : "4%"}, transparent)`,
      }}
    >
      <Atom size={16} className="mt-0.5 shrink-0 text-accent" />
      <div className="flex min-w-0 flex-1 flex-col gap-0.5">
        <Switch checked={checked} onChange={onChange} label="I work with React Native" />
        <p className="text-text-secondary">
          Adds Reactotron, the JS Console, and the React Native hub to any role you pick.
        </p>
      </div>
    </div>
  )
}
