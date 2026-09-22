import { CircleAlert, XCircle } from "lucide-react"
import { useRef, useState } from "react"

import { useDismissOnOutside } from "@/hooks/useDismissOnOutside"
import type { ActiveOverride } from "@/lib/wire"

/**
 * The amber pill in the device bar — the Mac's `OverridesPillView`.
 *
 * A standing reminder that this device is not in its own state. It exists
 * because an override is invisible: a proxy set an hour ago and forgotten is
 * indistinguishable from a network that has broken, and the pill is what turns
 * the second guess into the first.
 *
 * Shown only when something is overridden, so an untouched device carries no
 * chrome for it. The menu offers each override individually and then all of
 * them, the Mac's order — clearing one is the common case, since the reason you
 * notice the pill is usually one specific thing.
 */
export function OverridesPill({
  overrides,
  busy,
  onReset,
  onResetAll,
}: {
  overrides: ActiveOverride[]
  busy: boolean
  onReset: (kind: string) => void
  onResetAll: () => void
}) {
  const [open, setOpen] = useState(false)
  const anchor = useRef<HTMLDivElement | null>(null)
  useDismissOnOutside(anchor, () => setOpen(false))

  if (overrides.length === 0) return null

  return (
    <div ref={anchor} className="relative">
      <button
        type="button"
        title="Device-state overrides are active"
        aria-expanded={open}
        onClick={() => {
          setOpen((was) => !was)
        }}
        className="flex items-center gap-1.5 rounded-full bg-warn/20 px-2 py-0.5 text-[11.5px] text-warn hover:bg-warn/30"
      >
        <CircleAlert size={12} className="shrink-0" />
        {pillTitle(overrides)}
      </button>

      {open && (
        <div className="absolute right-0 top-full z-30 mt-1 w-[280px] rounded-lg border border-border-subtle bg-bg-raised p-1 shadow-xl">
          {overrides.map((override) => (
            <MenuItem
              key={override.kind}
              busy={busy}
              onClick={() => {
                setOpen(false)
                onReset(override.kind)
              }}
            >
              <XCircle size={12} className="shrink-0" />
              <span className="min-w-0 truncate">
                {override.label}: {override.value} — reset
              </span>
            </MenuItem>
          ))}
          <div className="my-1 h-px bg-border-subtle" />
          <MenuItem
            busy={busy}
            onClick={() => {
              setOpen(false)
              onResetAll()
            }}
          >
            Reset all overrides
          </MenuItem>
        </div>
      )}
    </div>
  )
}

/**
 * What the pill says: the one override's name, or the first plus a count.
 *
 * The Mac's rule. A bare count ("3 overrides") would say less in the same
 * space — the name is what tells you whether the pill is about the thing you
 * are currently confused by.
 */
export function pillTitle(overrides: readonly ActiveOverride[]): string {
  const first = overrides[0]
  if (first === undefined) return ""
  return overrides.length === 1 ? first.label : `${first.label} +${String(overrides.length - 1)}`
}

function MenuItem({
  busy,
  onClick,
  children,
}: {
  busy: boolean
  onClick: () => void
  children: React.ReactNode
}) {
  return (
    <button
      type="button"
      disabled={busy}
      onClick={onClick}
      className="flex w-full items-center gap-1.5 rounded px-2 py-1 text-left text-[11.5px] text-danger hover:bg-bg-hover disabled:cursor-not-allowed disabled:opacity-40"
    >
      {children}
    </button>
  )
}
