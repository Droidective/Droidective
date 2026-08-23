import { Link2, Pencil, Play, Trash2 } from "lucide-react"
import { cn } from "@/lib/cn"
import type { DeepLink } from "@/lib/wire"

/**
 * One saved link — the Mac's `linkRow`: the url, then launch, edit, delete.
 *
 * Launch leads because it is what the row is for; the other two are the
 * housekeeping. A link with no label shows only its url rather than an empty
 * line above it.
 */
export function DeepLinkRow({
  link,
  first,
  canLaunch,
  onLaunch,
  onEdit,
  onDelete,
}: {
  link: DeepLink
  first: boolean
  canLaunch: boolean
  onLaunch: () => void
  onEdit: () => void
  onDelete: () => void
}) {
  const name = link.label === "" ? link.url : link.label
  return (
    <div
      className={cn(
        "flex items-center gap-2.5 px-3 py-2",
        first ? "" : "border-t border-border-subtle",
      )}
    >
      <Link2 size={14} className="shrink-0 text-text-tertiary" />
      <div className="min-w-0 flex-1">
        {link.label === "" ? null : <p className="truncate text-text-primary">{link.label}</p>}
        <p className="truncate text-[11.5px] text-text-tertiary" data-selectable>
          {link.url}
        </p>
      </div>
      <Action
        label={canLaunch ? "Launch on device" : "Connect a device to launch"}
        disabled={!canLaunch}
        tone="accent"
        onClick={onLaunch}
      >
        <Play size={13} />
      </Action>
      <Action label={`Edit ${name}`} onClick={onEdit}>
        <Pencil size={13} />
      </Action>
      <Action label={`Delete ${name}`} tone="danger" onClick={onDelete}>
        <Trash2 size={13} />
      </Action>
    </div>
  )
}

function Action({
  label,
  tone = "default",
  disabled = false,
  onClick,
  children,
}: {
  label: string
  tone?: "default" | "accent" | "danger"
  disabled?: boolean
  onClick: () => void
  children: React.ReactNode
}) {
  const tones = {
    default: "text-text-tertiary hover:text-text-primary",
    accent: "text-accent hover:brightness-125",
    danger: "text-danger hover:brightness-125",
  }
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      disabled={disabled}
      onClick={onClick}
      className={cn("shrink-0 rounded p-1 disabled:opacity-40", tones[tone])}
    >
      {children}
    </button>
  )
}
