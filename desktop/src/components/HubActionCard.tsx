import { ChevronRight, RefreshCw, type LucideIcon } from "lucide-react"
import { cn } from "@/lib/cn"

/**
 * A quick-action tile — the Mac's `RNActionCard`.
 *
 * An accent icon chip, a title, a wrapping subtitle and an accent hover border.
 * `prominent` fills the chip for a screen's primary action, and `running`
 * spins in place of the icon: per card rather than per screen, because one
 * action being in flight must not grey out the others.
 */
export function HubActionCard({
  title,
  detail,
  icon: Icon,
  prominent = false,
  help,
  disabled,
  running,
  onClick,
}: {
  title: string
  detail: string
  icon: LucideIcon
  prominent?: boolean
  help: string
  disabled: boolean
  running: boolean
  onClick: () => void
}) {
  return (
    <button
      type="button"
      title={help}
      disabled={disabled}
      onClick={onClick}
      className={cn(
        "flex min-h-[68px] items-start gap-3 rounded-[10px] border p-3 text-left transition",
        "border-border-subtle bg-bg-root/60 hover:border-accent",
        "disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:border-border-subtle",
      )}
    >
      <span
        className={cn(
          "flex h-[30px] w-[30px] shrink-0 items-center justify-center rounded-[7px]",
          prominent ? "bg-accent text-accent-fg" : "bg-accent/10 text-accent",
        )}
      >
        {running ? (
          <RefreshCw size={15} className="animate-spin" />
        ) : (
          <Icon size={15} strokeWidth={2.2} />
        )}
      </span>
      <span className="flex min-w-0 flex-col gap-0.5">
        <span className="text-[13px] font-semibold text-text-primary">{title}</span>
        <span className="text-[11.5px] text-text-tertiary">{detail}</span>
      </span>
    </button>
  )
}

/**
 * A row that opens another screen — the Mac's `relatedRow`.
 *
 * A chevron rather than a button label, because it navigates rather than does
 * something: the hub gathers the tools, it does not absorb them.
 */
export function HubLinkRow({
  id,
  title,
  detail,
  icon: Icon,
  first = false,
  onOpen,
}: {
  id: string
  title: string
  detail: string
  icon: LucideIcon
  first?: boolean
  onOpen: (id: string) => void
}) {
  return (
    <button
      type="button"
      onClick={() => {
        onOpen(id)
      }}
      className={cn(
        "flex items-center gap-3 py-[7px] text-left",
        !first && "border-t border-border-subtle",
      )}
    >
      <Icon size={15} className="w-[22px] shrink-0 text-text-tertiary" />
      <span className="flex min-w-0 flex-col">
        <span className="text-text-primary">{title}</span>
        <span className="text-[11.5px] text-text-tertiary">{detail}</span>
      </span>
      <ChevronRight size={13} className="ml-auto shrink-0 text-text-tertiary" />
    </button>
  )
}
