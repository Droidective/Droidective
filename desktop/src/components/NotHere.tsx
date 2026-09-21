/**
 * The "Coming Soon" pane, for a feature this app does not have a screen for.
 *
 * Its own file because `FeaturePane` is at oxlint's line ceiling, and the
 * router is the part that should have the room to grow.
 */

import { Construction } from "lucide-react"

export function NotHere({ title, subtitle }: { title: string; subtitle?: string | null }) {
  return (
    <div className="flex h-full flex-col items-center justify-center gap-2 p-8 text-center">
      <Construction size={22} className="text-text-tertiary" />
      <h2 className="text-[15px] text-text-primary">{title}</h2>
      {subtitle ? <p className="text-text-secondary">{subtitle}</p> : null}
      <p className="max-w-sm text-text-tertiary">
        This screen has not been built for Windows and Linux yet. `docs/desktop-parity.md` tracks
        what it needs.
      </p>
    </div>
  )
}
