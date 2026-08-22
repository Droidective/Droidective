import { useEffect, useRef, useState } from "react"
import { X } from "lucide-react"
import { cn } from "@/lib/cn"
import {
  formatHotkey,
  hotkeyFromEvent,
  isModifierCode,
  modifierPreview,
  modifiersOf,
  reservedCommand,
  type Hotkey,
  type Modifiers,
} from "@/lib/hotkeys"
import { IS_MAC } from "@/lib/platform"

const NOTHING_HELD: Modifiers = { ctrl: false, alt: false, shift: false, meta: false }

/** What a keypress amounted to while recording. */
type Capture =
  | { kind: "captured"; hotkey: Hotkey }
  | { kind: "cleared" }
  | { kind: "cancelled" }
  /** Nothing decided — a modifier is down and no real key has landed. */
  | { kind: "pending" }
  /** A combination the shell already owns, named so the refusal can say why. */
  | { kind: "reserved"; message: string }

/**
 * Reads the keyboard while a recorder is open.
 *
 * In capture, so a recording beats the window listeners that own ⌘W and ⌘K —
 * the combination being *taken* must not also fire the command it is taken
 * from. Every key is swallowed for the same reason.
 */
function useHotkeyCapture(active: boolean, onCapture: (capture: Capture) => void): Modifiers {
  const [held, setHeld] = useState<Modifiers>(NOTHING_HELD)
  // Through a ref, so the listeners are installed once per recording rather
  // than torn down and rebuilt on every render of the caller.
  const handler = useRef(onCapture)
  handler.current = onCapture

  useEffect(() => {
    if (!active) {
      setHeld(NOTHING_HELD)
      return
    }
    const onKeyDown = (event: KeyboardEvent) => {
      event.preventDefault()
      event.stopPropagation()
      setHeld(modifiersOf(event))
      handler.current(read(event))
    }
    const onKeyUp = (event: KeyboardEvent) => {
      event.preventDefault()
      setHeld(modifiersOf(event))
    }
    globalThis.addEventListener("keydown", onKeyDown, true)
    globalThis.addEventListener("keyup", onKeyUp, true)
    return () => {
      globalThis.removeEventListener("keydown", onKeyDown, true)
      globalThis.removeEventListener("keyup", onKeyUp, true)
    }
  }, [active])

  return held
}

/** One keydown, as the Mac's recorder reads it: Esc cancels, Backspace clears. */
function read(event: KeyboardEvent): Capture {
  if (event.code === "Escape") return { kind: "cancelled" }
  if (event.code === "Backspace" || event.code === "Delete") return { kind: "cleared" }
  if (isModifierCode(event.code)) return { kind: "pending" }
  const captured = hotkeyFromEvent({ ...modifiersOf(event), code: event.code })
  // A bare key, or Shift alone: not something a shortcut may be.
  if (captured === null) return { kind: "pending" }
  const owner = reservedCommand(captured, IS_MAC)
  if (owner !== null) {
    return {
      kind: "reserved",
      message: `${formatHotkey(captured, IS_MAC)} is ${owner}. Try another key.`,
    }
  }
  return { kind: "captured", hotkey: captured }
}

/**
 * A shortcut recorder with live feedback — the Mac's `HotkeyRecorderField`.
 *
 * It shows the modifiers as they are held (⌃⌘…) and captures the whole
 * combination on the first real key.
 *
 * Which field is recording is the caller's state, not this component's. The Mac
 * needs a process-wide `HotkeyRecording.shared` for it because its recorders
 * install their own event monitors; here the Hotkeys tab renders one of these
 * per feature, and a single owner is what stops two recording at once.
 */
export function HotkeyRecorder({
  hotkey,
  recording,
  onStart,
  onStop,
  onChange,
  label,
}: {
  hotkey: Hotkey | null
  recording: boolean
  onStart: () => void
  onStop: () => void
  /** Null clears the binding. */
  onChange: (hotkey: Hotkey | null) => void
  /** Names the feature for a screen reader, since the button's text is a combo. */
  label: string
}) {
  const [refused, setRefused] = useState("")

  const held = useHotkeyCapture(recording, (capture) => {
    // A held modifier decides nothing, and must not wipe a refusal the user has
    // not read yet.
    if (capture.kind === "pending") return
    if (capture.kind === "reserved") {
      setRefused(capture.message)
      return
    }
    setRefused("")
    if (capture.kind === "captured") onChange(capture.hotkey)
    if (capture.kind === "cleared") onChange(null)
    onStop()
  })

  return (
    <div className="flex flex-col items-end gap-1">
      <div className="flex items-center gap-1.5">
        <button
          type="button"
          aria-label={`Shortcut for ${label}`}
          onClick={() => {
            setRefused("")
            if (recording) onStop()
            else onStart()
          }}
          className={cn(
            "min-w-[124px] rounded-md bg-bg-raised px-2.5 py-1 text-left text-[13px]",
            recording ? "ring-2 ring-accent" : "hover:bg-border-subtle",
            recording || hotkey ? "text-text-primary" : "text-text-tertiary",
          )}
        >
          {caption(recording, held, hotkey)}
        </button>
        {hotkey && !recording ? (
          <button
            type="button"
            aria-label={`Clear the shortcut for ${label}`}
            title="Clear shortcut"
            onClick={() => {
              onChange(null)
            }}
            className="text-text-tertiary hover:text-text-primary"
          >
            <X size={13} />
          </button>
        ) : (
          // Reserved either way, so the recorder does not jump sideways as a
          // combination lands on it.
          <span className="w-[13px]" />
        )}
      </div>
      {refused === "" ? null : (
        <p className="max-w-[220px] text-right text-[11px] text-warn">{refused}</p>
      )}
    </div>
  )
}

function caption(recording: boolean, held: Modifiers, hotkey: Hotkey | null): string {
  if (recording) {
    const preview = modifierPreview(held, IS_MAC)
    return preview === "" ? "Press your shortcut…" : preview
  }
  return hotkey === null ? "Click to record" : formatHotkey(hotkey, IS_MAC)
}
