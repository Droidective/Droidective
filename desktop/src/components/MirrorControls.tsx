import { ChevronLeft, Circle, Square, Volume1, Volume2, VolumeX } from "lucide-react"

import { KEYCODE, backOrScreenOn, tapKey } from "@/lib/scrcpy-control"

/**
 * The mirror's button row: back, home, recents, then the three volume keys.
 *
 * The same set and the same order as the Mac's `ScreenMirrorView` bar, because
 * someone moving between the two should not have to look for them.
 */
export function MirrorControls({
  send,
  dropped,
}: {
  send: (bytes: Uint8Array) => void
  /** Frames the daemon discarded, surfaced rather than swallowed. */
  dropped: number
}) {
  const key = (keycode: number) => () => {
    for (const message of tapKey(keycode)) send(message)
  }

  return (
    <div className="flex items-center justify-center gap-1 border-t border-border-subtle bg-bg-surface px-3 py-2">
      <NavButton
        label="Back"
        onClick={() => {
          // backOrScreenOn, not KEYCODE_BACK: this also wakes a sleeping
          // device, which is what scrcpy's own Back does. A plain back on a
          // dark screen looks like a mirror that ignores the button.
          send(backOrScreenOn("down"))
          send(backOrScreenOn("up"))
        }}
      >
        <ChevronLeft size={16} />
      </NavButton>
      <NavButton label="Home" onClick={key(KEYCODE.home)}>
        <Circle size={13} />
      </NavButton>
      <NavButton label="Recents" onClick={key(KEYCODE.appSwitch)}>
        <Square size={12} />
      </NavButton>
      <span className="mx-2 h-4 w-px bg-border-subtle" />
      <NavButton label="Volume down" onClick={key(KEYCODE.volumeDown)}>
        <Volume1 size={16} />
      </NavButton>
      <NavButton label="Volume up" onClick={key(KEYCODE.volumeUp)}>
        <Volume2 size={16} />
      </NavButton>
      <NavButton label="Mute" onClick={key(KEYCODE.volumeMute)}>
        <VolumeX size={16} />
      </NavButton>
      {dropped > 0 && (
        <span className="ml-auto text-xs text-text-tertiary">
          {dropped} frame{dropped === 1 ? "" : "s"} dropped
        </span>
      )}
    </div>
  )
}

function NavButton({
  label,
  onClick,
  children,
}: {
  label: string
  onClick: () => void
  children: React.ReactNode
}) {
  return (
    <button
      type="button"
      title={label}
      aria-label={label}
      onClick={onClick}
      className="flex h-7 w-9 items-center justify-center rounded text-text-secondary hover:bg-bg-hover hover:text-text-primary"
    >
      {children}
    </button>
  )
}
