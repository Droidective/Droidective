import type { LucideIcon } from "lucide-react"
import type { ReactNode } from "react"

/**
 * One section of the State screen — the Mac's `StateCard`.
 *
 * Icon, title, a line saying what the card is for, an optional count chip and
 * an optional action on the right. Four cards share it, which is why it is a
 * component rather than four near-identical headers.
 */
export function StateCard({
  icon: Icon,
  title,
  subtitle,
  chip,
  actions,
  children,
}: {
  icon: LucideIcon
  title: string
  subtitle: string
  /** A count, when there is something to count. */
  chip?: string | null
  actions?: ReactNode
  children: ReactNode
}) {
  return (
    <section className="rounded-lg border border-border-subtle bg-bg-chrome">
      <header className="flex items-center gap-2.5 border-b border-border-subtle px-3 py-2">
        <Icon size={14} className="shrink-0 text-accent" />
        <div className="min-w-0 flex-1">
          <h3 className="text-[13px] font-semibold text-text-primary">{title}</h3>
          <p className="truncate text-[11.5px] text-text-tertiary">{subtitle}</p>
        </div>
        {chip === null || chip === undefined ? null : (
          <span className="shrink-0 rounded-full bg-bg-raised px-2 py-0.5 text-[11px] tabular-nums text-text-secondary">
            {chip}
          </span>
        )}
        {actions}
      </header>
      <div className="flex flex-col gap-2 p-3">{children}</div>
    </section>
  )
}
