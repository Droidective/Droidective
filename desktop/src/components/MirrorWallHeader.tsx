import { useRef, useState } from "react"
import { Check, ChevronDown, Columns3 } from "lucide-react"

import { useDismissOnOutside } from "@/hooks/useDismissOnOutside"
import type { MirrorWallState } from "@/hooks/useMirrorWall"
import { cn } from "@/lib/cn"
import { MAXIMUM_DEVICES } from "@/lib/mirror-wall"

/** The wall's own controls: which devices are on it, and how they are laid out. */
export function MirrorWallHeader({ wall }: { wall: MirrorWallState }) {
  return (
    <div className="flex items-center gap-2 border-b border-border-subtle bg-bg-surface px-3 py-2">
      <DeviceMenu wall={wall} />
      <ColumnMenu wall={wall} />
      <span className="ml-auto text-xs text-text-tertiary">
        {wall.selection.length === 0
          ? ""
          : `${wall.selection.length} of ${MAXIMUM_DEVICES} · ${wall.quality.maxSize}px${
              wall.quality.maxFps > 0 ? ` · ${wall.quality.maxFps}fps` : ""
            }`}
      </span>
    </div>
  )
}

function DeviceMenu({ wall }: { wall: MirrorWallState }) {
  const [open, setOpen] = useState(false)
  const anchor = useRef<HTMLDivElement | null>(null)
  useDismissOnOutside(anchor, () => setOpen(false))

  return (
    <div ref={anchor} className="relative">
      <MenuButton onClick={() => setOpen((current) => !current)}>
        Devices
        <ChevronDown size={13} />
      </MenuButton>
      {open && (
        <div className="absolute left-0 top-full z-20 mt-1 min-w-56 rounded border border-border-subtle bg-bg-surface py-1 shadow-lg">
          {wall.devices.length === 0 && (
            <p className="px-3 py-1.5 text-xs text-text-tertiary">Nothing connected.</p>
          )}
          {wall.devices.map((device) => {
            const on = wall.selection.includes(device.serial)
            // The checkbox that would exceed the cap is disabled rather than
            // evicting someone else's tile.
            const blocked = !on && !wall.canAddMore
            return (
              <button
                key={device.serial}
                type="button"
                disabled={blocked}
                onClick={() => wall.toggle(device.serial)}
                className={cn(
                  "flex w-full items-center gap-2 px-3 py-1.5 text-left text-xs",
                  blocked
                    ? "cursor-not-allowed text-text-tertiary"
                    : "text-text-primary hover:bg-bg-hover",
                )}
                title={blocked ? `A wall shows at most ${MAXIMUM_DEVICES} devices.` : device.serial}
              >
                <Check size={12} className={cn("shrink-0", on ? "opacity-100" : "opacity-0")} />
                <span className="truncate">{device.label}</span>
              </button>
            )
          })}
        </div>
      )}
    </div>
  )
}

function ColumnMenu({ wall }: { wall: MirrorWallState }) {
  const [open, setOpen] = useState(false)
  const anchor = useRef<HTMLDivElement | null>(null)
  useDismissOnOutside(anchor, () => setOpen(false))

  const options: { label: string; mode: "auto" | number }[] = [
    { label: "Automatic", mode: "auto" },
    { label: "1 column", mode: 1 },
    { label: "2 columns", mode: 2 },
    { label: "3 columns", mode: 3 },
  ]

  return (
    <div ref={anchor} className="relative">
      <MenuButton onClick={() => setOpen((current) => !current)}>
        <Columns3 size={13} />
        {wall.columnMode === "auto" ? "Automatic" : `${wall.columnMode} col`}
      </MenuButton>
      {open && (
        <div className="absolute left-0 top-full z-20 mt-1 min-w-40 rounded border border-border-subtle bg-bg-surface py-1 shadow-lg">
          {options.map((option) => (
            <button
              key={option.label}
              type="button"
              onClick={() => {
                wall.setColumnMode(option.mode)
                setOpen(false)
              }}
              className="flex w-full items-center gap-2 px-3 py-1.5 text-left text-xs text-text-primary hover:bg-bg-hover"
            >
              <Check
                size={12}
                className={cn(
                  "shrink-0",
                  wall.columnMode === option.mode ? "opacity-100" : "opacity-0",
                )}
              />
              {option.label}
            </button>
          ))}
        </div>
      )}
    </div>
  )
}

function MenuButton({
  onClick,
  children,
}: {
  onClick: () => void
  children: React.ReactNode
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="flex items-center gap-1.5 rounded border border-border-subtle px-2 py-1 text-xs text-text-primary hover:bg-bg-hover"
    >
      {children}
    </button>
  )
}
