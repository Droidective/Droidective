import type { ReactNode } from "react"
import { cn } from "@/lib/cn"

/**
 * The Mac's `HubKit` — the containers every multi-section screen is built from.
 *
 * Ported shape-for-shape from `App/Sources/FeatureDetail/HubKit.swift` rather
 * than reinvented, because these are what make the hub screens, the toggle
 * tables and the read-only info panels read as one rhythm on both platforms.
 * The Mac deliberately replaced the grouped `Form` with these cards; a port
 * that reached for a plain list here would look like a different app.
 */

/**
 * A titled card: header (title, optional one-line subtitle, optional trailing
 * accessory) above its controls, on one lifted surface.
 *
 * The surface is `bg-surface` with no extra wash of its own — cards stack on
 * the single root wash, which is the rule the Mac's translucency convention
 * sets and the reason nothing here compounds to solid.
 */
export function HubSection({
  title,
  subtitle,
  accessory,
  children,
}: {
  title: string
  subtitle?: string | undefined
  accessory?: ReactNode
  children: ReactNode
}) {
  return (
    <section className="w-full rounded-xl border border-border-subtle bg-bg-surface p-4">
      <header className="flex items-baseline gap-3">
        <div className="min-w-0 flex-1">
          <h2 className="text-[13px] font-semibold text-text-primary">{title}</h2>
          {subtitle === undefined ? null : (
            <p className="mt-0.5 text-[12px] text-text-tertiary">{subtitle}</p>
          )}
        </div>
        {accessory}
      </header>
      <div className="mt-3 flex flex-col gap-3">{children}</div>
    </section>
  )
}

/** The scrollable column a screen's sections sit in. Fills the pane width. */
export function HubColumn({ children }: { children: ReactNode }) {
  return (
    <div className="min-h-0 flex-1 overflow-y-auto">
      <div className="flex flex-col gap-4 p-5">{children}</div>
    </div>
  )
}

/** A read-only label / value row. The value is selectable, as the Mac's is. */
export function HubRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-baseline gap-4">
      <span className="text-text-primary">{label}</span>
      <span className="ml-auto text-right text-text-tertiary" data-selectable>
        {value}
      </span>
    </div>
  )
}

/** A divider-separated block of `HubRow`s. */
export function HubRowList({ rows }: { rows: { label: string; value: string }[] }) {
  return (
    <div className="flex flex-col">
      {rows.map((row, index) => (
        <div
          key={row.label}
          className={cn("py-[7px]", index > 0 && "border-t border-border-subtle")}
        >
          <HubRow label={row.label} value={row.value} />
        </div>
      ))}
    </div>
  )
}

/**
 * A switch with a title and one muted line under it — the Mac's `SwitchRow`.
 *
 * The caption is what makes a toggle table readable without a manual, so it is
 * part of the row rather than something each screen assembles.
 */
export function SwitchRow({
  title,
  subtitle,
  checked,
  onChange,
  disabled = false,
}: {
  title: string
  subtitle?: string | undefined
  checked: boolean
  onChange: (checked: boolean) => void
  disabled?: boolean
}) {
  return (
    <div className="flex items-center gap-3">
      <div className="min-w-0 flex-1">
        <p className="text-text-primary">{title}</p>
        {subtitle === undefined ? null : (
          <p className="mt-px text-[11.5px] text-text-tertiary">{subtitle}</p>
        )}
      </div>
      <button
        type="button"
        role="switch"
        aria-checked={checked}
        aria-label={title}
        disabled={disabled}
        onClick={() => {
          onChange(!checked)
        }}
        className={cn(
          "relative h-[18px] w-8 shrink-0 rounded-full transition disabled:opacity-40",
          checked ? "bg-accent" : "bg-border-subtle",
        )}
      >
        <span
          className={cn(
            "absolute top-0.5 h-3.5 w-3.5 rounded-full bg-white transition-all",
            checked ? "left-[17px]" : "left-0.5",
          )}
        />
      </button>
    </div>
  )
}

/**
 * A small square icon button for a section header — the Mac's
 * `IconButtonStyle`, which is what Refresh uses on every one of these screens.
 */
export function IconButton({
  icon,
  label,
  onClick,
  disabled = false,
}: {
  icon: ReactNode
  label: string
  onClick: () => void
  disabled?: boolean
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      aria-label={label}
      title={label}
      className={cn(
        "shrink-0 rounded-md p-1.5 text-text-secondary transition",
        "hover:bg-white/[0.06] hover:text-text-primary",
        "disabled:cursor-not-allowed disabled:opacity-40 disabled:hover:bg-transparent",
      )}
    >
      {icon}
    </button>
  )
}
