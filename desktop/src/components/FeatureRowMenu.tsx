import { useEffect } from "react"
import { HotkeyRecorder } from "@/components/HotkeyRecorder"
import { cn } from "@/lib/cn"
import { formatHotkey, hotkeyEffect, type Hotkey } from "@/lib/hotkeys"
import { IS_MAC } from "@/lib/platform"
import type { FeatureSummary } from "@/lib/wire"

/** Where a sidebar row was right-clicked, and which feature it was. */
export interface FeatureMenuTarget {
  id: string
  x: number
  y: number
}

/**
 * A sidebar row's right-click menu — the Mac's row `contextMenu`: Pin/Unpin,
 * Disable/Enable, and Set Hotkey…
 *
 * Hand-rolled for the reason `TabMenu` is: a webview has no menu of its own,
 * and reaching for the OS menu would be another plugin and another permission
 * for three items.
 */
export function FeatureRowMenu({
  target,
  feature,
  pinned,
  enabled,
  hotkey,
  recording,
  onTogglePinned,
  onSetEnabled,
  onStartRecording,
  onStopRecording,
  onSetHotkey,
  onDismiss,
}: {
  target: FeatureMenuTarget
  feature: FeatureSummary
  pinned: boolean
  enabled: boolean
  hotkey: Hotkey | null
  /** The recorder is open on this row, which is what turns the menu into it. */
  recording: boolean
  onTogglePinned: () => void
  onSetEnabled: (enabled: boolean) => void
  onStartRecording: () => void
  onStopRecording: () => void
  onSetHotkey: (hotkey: Hotkey | null) => void
  onDismiss: () => void
}) {
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      // While recording, the recorder owns Esc — it cancels the capture rather
      // than closing the popover out from under it.
      if (event.key === "Escape" && !recording) onDismiss()
    }
    globalThis.addEventListener("keydown", onKeyDown)
    return () => {
      globalThis.removeEventListener("keydown", onKeyDown)
    }
  }, [onDismiss, recording])

  return (
    <>
      <div
        className="fixed inset-0 z-40"
        onPointerDown={onDismiss}
        onContextMenu={(event) => {
          event.preventDefault()
          onDismiss()
        }}
      />
      <div
        role="menu"
        style={{ left: target.x, top: target.y }}
        className={cn(
          "fixed z-50 rounded-lg border border-border-subtle bg-bg-raised shadow-xl",
          recording ? "w-[280px] p-3" : "min-w-[200px] py-1",
        )}
      >
        {recording ? (
          <HotkeyPopover
            feature={feature}
            hotkey={hotkey}
            onStop={onStopRecording}
            onChange={(next) => {
              onSetHotkey(next)
            }}
          />
        ) : (
          <>
            <Item
              onSelect={() => {
                onTogglePinned()
                onDismiss()
              }}
            >
              {pinned ? "Unpin" : "Pin"}
            </Item>
            <Item
              onSelect={() => {
                onSetEnabled(!enabled)
                onDismiss()
              }}
            >
              {enabled ? "Disable" : "Enable"}
            </Item>
            <div className="my-1 h-px bg-border-subtle" />
            <Item onSelect={onStartRecording}>
              {hotkey === null ? "Set Hotkey…" : `Hotkey · ${formatHotkey(hotkey, IS_MAC)}`}
            </Item>
          </>
        )}
      </div>
    </>
  )
}

/**
 * The inline recorder the menu turns into — the Mac's `HotkeyPopover`, wording
 * included, minus the promise it cannot keep: these fire while the window has
 * focus, not from anywhere.
 */
function HotkeyPopover({
  feature,
  hotkey,
  onStop,
  onChange,
}: {
  feature: FeatureSummary
  hotkey: Hotkey | null
  onStop: () => void
  onChange: (hotkey: Hotkey | null) => void
}) {
  return (
    <div className="flex flex-col gap-2">
      <p className="text-[13px] font-medium text-text-primary">Hotkey · {feature.title}</p>
      <p className="text-[11px] text-text-tertiary">
        Press your shortcut — e.g. {IS_MAC ? "⌘⌃Y" : "Ctrl+Alt+Y"}. Esc cancels, Backspace clears.
      </p>
      {/* Recording from the moment it appears — the popover only exists while
          it is, which is what the Mac's `autoFocus` recorder achieves. */}
      <HotkeyRecorder
        hotkey={hotkey}
        recording
        label={feature.title}
        onStart={onStop}
        onStop={onStop}
        onChange={onChange}
      />
      <p className="text-[11px] text-text-tertiary">
        {hotkeyEffect(feature.kind) === "run" ? "Runs it" : "Opens it"} while a Droidective window
        has focus.
      </p>
    </div>
  )
}

function Item({ onSelect, children }: { onSelect: () => void; children: string }) {
  return (
    <button
      type="button"
      role="menuitem"
      onClick={onSelect}
      className="block w-full px-3 py-1 text-left text-[13px] text-text-primary hover:bg-accent/20"
    >
      {children}
    </button>
  )
}
