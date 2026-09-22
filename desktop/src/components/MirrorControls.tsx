import {
  Camera,
  ChevronLeft,
  Circle,
  MoreHorizontal,
  PictureInPicture2,
  Square,
  Volume1,
  Volume2,
  VolumeX,
} from "lucide-react"
import { useEffect, useRef, useState } from "react"

import { KEYCODE, backOrScreenOn, tapKey } from "@/lib/scrcpy-control"

/**
 * The mirror's button row: back, home, recents, then the three volume keys,
 * then the ⋯ menu the Mac keeps its session options behind.
 *
 * The same set and the same order as the Mac's `ScreenMirrorView` bar, because
 * someone moving between the two should not have to look for them.
 */
export function MirrorControls({
  send,
  dropped,
  onCapture,
  onPopOut,
  options,
}: {
  send: (bytes: Uint8Array) => void
  /** Frames the daemon discarded, surfaced rather than swallowed. */
  dropped: number
  /**
   * Take a still and open it in the editor. Absent while nothing is
   * streaming — there is no frame to grab, and a button that did nothing
   * would read as a broken camera.
   */
  onCapture?: (() => void) | undefined
  /**
   * Open this device's mirror in a window of its own.
   *
   * Absent when there is no device to pin the window to — a pop-out that
   * followed the selection would be a second copy of this pane rather than
   * the Mac's per-device window.
   */
  onPopOut?: (() => void) | undefined
  /** The ⋯ menu's contents. Absent with no device to write the setting to. */
  options?: { showTouches: boolean; setShowTouches: (on: boolean) => void } | undefined
}) {
  const key = (keycode: number) => () => {
    for (const message of tapKey(keycode)) send(message)
  }

  return (
    <div className="flex items-center justify-center gap-1 border-t border-border-subtle bg-bg-surface px-3 py-2">
      {onCapture === undefined ? null : (
        <NavButton label="Screenshot — edit in place" onClick={onCapture}>
          <Camera size={15} />
        </NavButton>
      )}
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
      {onPopOut === undefined ? null : (
        <>
          <span className="mx-2 h-4 w-px bg-border-subtle" />
          <NavButton label="Open in a separate window" onClick={onPopOut}>
            <PictureInPicture2 size={15} />
          </NavButton>
        </>
      )}
      {options === undefined ? null : <OptionsMenu options={options} />}
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

/**
 * The ⋯ menu — session options, not per-tap controls.
 *
 * The Mac's reasoning for the menu, kept: neither of these earns an
 * always-visible bar slot. Show touches is a live write on the device rather
 * than a scrcpy option, so flipping it on mid-recording works, which is the
 * point of having it here at all.
 */
function OptionsMenu({
  options,
}: {
  options: { showTouches: boolean; setShowTouches: (on: boolean) => void }
}) {
  const [open, setOpen] = useState(false)
  const box = useRef<HTMLDivElement | null>(null)

  useEffect(() => {
    if (!open) return
    const onDown = (event: MouseEvent) => {
      if (!(event.target instanceof Node) || box.current?.contains(event.target) !== true) {
        setOpen(false)
      }
    }
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") setOpen(false)
    }
    globalThis.addEventListener("mousedown", onDown)
    globalThis.addEventListener("keydown", onKeyDown)
    return () => {
      globalThis.removeEventListener("mousedown", onDown)
      globalThis.removeEventListener("keydown", onKeyDown)
    }
  }, [open])

  return (
    <div ref={box} className="relative">
      <NavButton
        label="Audio and touch options"
        onClick={() => {
          setOpen((was) => !was)
        }}
      >
        <MoreHorizontal size={16} />
      </NavButton>
      {open && (
        <div className="absolute bottom-full right-0 z-20 mb-1 w-[200px] rounded-lg border border-border-subtle bg-bg-raised p-1 shadow-xl">
          <label className="flex cursor-pointer items-center gap-2 rounded px-2 py-1.5 text-[11.5px] text-text-primary hover:bg-bg-hover">
            <input
              type="checkbox"
              checked={options.showTouches}
              onChange={(event) => {
                options.setShowTouches(event.target.checked)
              }}
              className="accent-accent"
            />
            Show touches
          </label>
        </div>
      )}
    </div>
  )
}
