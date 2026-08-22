import type { ReactNode } from "react"

/**
 * The Settings pane's building blocks — a titled group, and a label/control
 * row inside it.
 *
 * The Mac's Settings is a `Form` with `Section`s; this is the same rhythm
 * without the material, so a tab written here lines up with its macOS twin
 * without each tab re-deciding its own spacing.
 */

export function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="flex flex-col gap-2.5">
      <h2 className="text-[11px] uppercase tracking-[0.06em] text-text-tertiary">{title}</h2>
      <div className="flex flex-col gap-2.5 rounded-lg border border-border-subtle bg-bg-surface p-3.5">
        {children}
      </div>
    </section>
  )
}

/** A label on the leading edge, its control trailing. */
export function Row({
  label,
  detail,
  children,
}: {
  label: string
  detail?: string
  children: ReactNode
}) {
  return (
    <div className="flex items-center gap-4">
      <div className="min-w-0 flex-1">
        <p className="text-text-primary">{label}</p>
        {detail === undefined ? null : (
          <p className="mt-px text-[11.5px] text-text-tertiary">{detail}</p>
        )}
      </div>
      <div className="shrink-0">{children}</div>
    </div>
  )
}
