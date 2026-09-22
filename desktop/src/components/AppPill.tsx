import { Crosshair, Package, PlusSquare } from "lucide-react"
import { useRef, useState } from "react"

import { InstalledAppsPicker } from "@/components/InstalledAppsPicker"
import { useDismissOnOutside } from "@/hooks/useDismissOnOutside"
import { useNotifications } from "@/hooks/useNotifications"
import { asDaemonError, foregroundApp } from "@/lib/daemon"

/**
 * Which app the app-scoped screens act on — the Mac's bundle pill.
 *
 * Until now the only way to change it was the Apps screen, so every per-app
 * feature (App Info, Permissions, Memory, Sandbox, a `needsBundle` action)
 * meant leaving the screen you were on to pick, and coming back. The Mac puts
 * the choice in the bar for exactly that reason.
 *
 * **One difference from the Mac, and it is a subsystem rather than a decision.**
 * Its menu lists *saved bundles* — nicknamed packages from a store this app
 * does not keep — so what is offered here is the two ways to answer the
 * question without one: pick from what is installed, or take whatever is on the
 * device screen. `Add manually / manage…` has nothing to manage and is absent,
 * as it is in Logcat's own app bar.
 */
export function AppPill({
  serial,
  packageId,
  onSelect,
}: {
  serial: string | null
  packageId: string | null
  onSelect: (packageId: string | null) => void
}) {
  const { show } = useNotifications()
  const [open, setOpen] = useState(false)
  const [picking, setPicking] = useState(false)
  const anchor = useRef<HTMLDivElement | null>(null)
  useDismissOnOutside(anchor, () => setOpen(false))

  const adoptForeground = () => {
    if (serial === null) return
    foregroundApp(serial).then(
      (answer) => {
        // Null is a real answer — the launcher is in front more often than not
        // — so it is said rather than reported as a failure.
        const front = answer.packageId ?? null
        if (front === null) show({ message: "Nothing in front to pick.", ok: false })
        else onSelect(front)
      },
      (thrown: unknown) => {
        show({ message: asDaemonError(thrown).message, ok: false })
      },
    )
  }

  return (
    <div ref={anchor} className="relative flex items-center gap-2">
      <Package size={13} className={packageId === null ? "text-text-tertiary" : "text-accent"} />
      <button
        type="button"
        title="Choose the target app"
        // Named rather than left to its content: the label is the *package*,
        // so without this the button's accessible name changes every time the
        // choice does, and a screen reader announces a different control.
        aria-label="Choose the target app"
        aria-expanded={open}
        onClick={() => {
          setOpen((was) => !was)
        }}
        className="max-w-[240px] truncate rounded-md bg-bg-raised px-2 py-1 text-[11.5px] text-text-primary hover:bg-border-subtle"
      >
        {packageId ?? <span className="text-text-tertiary">Choose app…</span>}
      </button>

      {open && (
        <AppMenu
          hasDevice={serial !== null}
          hasChoice={packageId !== null}
          onPick={() => {
            setOpen(false)
            setPicking(true)
          }}
          onForeground={() => {
            setOpen(false)
            adoptForeground()
          }}
          onClear={() => {
            setOpen(false)
            onSelect(null)
          }}
        />
      )}

      {picking && serial !== null && (
        <InstalledAppsPicker
          serial={serial}
          onPick={(chosen) => {
            setPicking(false)
            onSelect(chosen)
          }}
          onCancel={() => {
            setPicking(false)
          }}
        />
      )}
    </div>
  )
}

/** The pill's menu: the two ways to answer, and undoing the answer. */
function AppMenu({
  hasDevice,
  hasChoice,
  onPick,
  onForeground,
  onClear,
}: {
  hasDevice: boolean
  hasChoice: boolean
  onPick: () => void
  onForeground: () => void
  onClear: () => void
}) {
  return (
        <div className="absolute left-0 top-full z-30 mt-1 w-[260px] rounded-lg border border-border-subtle bg-bg-raised p-1 shadow-xl">
          <MenuItem
            disabled={!hasDevice}
            onClick={onPick}
          >
            <PlusSquare size={12} />
            Add from installed apps
          </MenuItem>
          <MenuItem
            disabled={!hasDevice}
            onClick={onForeground}
          >
            <Crosshair size={12} />
            Use app on device screen
          </MenuItem>
          {hasChoice ? (
            <>
              <div className="my-1 h-px bg-border-subtle" />
              <MenuItem onClick={onClear}>Clear the choice</MenuItem>
            </>
          ) : null}
        </div>
  )
}

function MenuItem({
  disabled = false,
  onClick,
  children,
}: {
  disabled?: boolean
  onClick: () => void
  children: React.ReactNode
}) {
  return (
    <button
      type="button"
      disabled={disabled}
      onClick={onClick}
      className="flex w-full items-center gap-1.5 rounded px-2 py-1 text-left text-[11.5px] text-text-primary hover:bg-bg-hover disabled:cursor-not-allowed disabled:opacity-40"
    >
      {children}
    </button>
  )
}
