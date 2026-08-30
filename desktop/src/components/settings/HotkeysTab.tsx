import { useState } from "react"
import { HotkeyRecorder } from "@/components/HotkeyRecorder"
import { Row, Section } from "@/components/settings/SettingsKit"
import { type Hotkey, type HotkeyBindings, hotkeyEffect } from "@/lib/hotkeys"
import { sidebarSections, visibleFeatures } from "@/lib/sidebar"
import type { FeatureSummary } from "@/lib/wire"

/** The one row that is not a feature, so it needs an id of its own. */
const PANEL_ROW = "quick-actions-panel"

export interface HotkeysTabProps {
  features: FeatureSummary[]
  bindings: HotkeyBindings
  onChange: (id: string, hotkey: Hotkey | null) => void
  /** The Quick Actions panel's shortcut, which is not a feature's. */
  panelHotkey: Hotkey | null
  onPanelHotkey: (hotkey: Hotkey | null) => void
  /** The sidebar's arrangement, so this lists features in the order it shows them. */
  sidebarOrder: readonly string[]
  categoryOrder: readonly string[]
  favorites: readonly string[]
  disabledFeatures: readonly string[]
}

/**
 * Settings ▸ Hotkeys — the Mac's `HotkeysSettingsView`.
 *
 * Three sections, in its order: the global pair, then every feature the sidebar
 * lists in the order it lists them, then the features turned off in the catalog
 * that still carry a shortcut. That last section is the one worth keeping: a
 * hidden feature's shortcut goes on firing, so leaving it out would make it
 * unbindable.
 */
export function HotkeysTab(props: HotkeysTabProps) {
  // One owner, so starting a second recording cancels the first — what the
  // Mac's process-wide `HotkeyRecording.shared` is for.
  const [recording, setRecording] = useState<string | null>(null)

  const listed = visibleFeatures(
    sidebarSections(props.features, {
      query: "",
      sidebarOrder: props.sidebarOrder,
      categoryOrder: props.categoryOrder,
      collapsedCategories: [],
      favorites: props.favorites,
      disabledFeatures: props.disabledFeatures,
    }),
  )
  const shown = new Set(listed.map((feature) => feature.id))
  const orphans = props.features.filter(
    (feature) => !shown.has(feature.id) && props.bindings[feature.id] !== undefined,
  )

  const recorder = (feature: FeatureSummary) => (
    <HotkeyRecorder
      hotkey={props.bindings[feature.id] ?? null}
      recording={recording === feature.id}
      label={feature.title}
      onStart={() => {
        setRecording(feature.id)
      }}
      onStop={() => {
        setRecording(null)
      }}
      onChange={(hotkey) => {
        props.onChange(feature.id, hotkey)
      }}
    />
  )

  return (
    <div className="flex flex-col gap-5">
      <p className="text-[11.5px] text-text-tertiary">
        Shortcuts are registered with the system, so they fire from whatever app you are in — and
        from a window closed into the tray. A combination another app already holds is refused by
        the platform and keeps working while Droidective has focus. While recording, Esc cancels
        and Backspace clears.
      </p>

      <Section title="Global">
        <Row
          label="Quick Actions panel"
          detail="Summons the panel over whatever you are working in. Ctrl+Shift+Space is a good one."
        >
          <HotkeyRecorder
            hotkey={props.panelHotkey}
            recording={recording === PANEL_ROW}
            label="Quick Actions panel"
            onStart={() => {
              setRecording(PANEL_ROW)
            }}
            onStop={() => {
              setRecording(null)
            }}
            onChange={props.onPanelHotkey}
          />
        </Row>
      </Section>

      <Section title="Features">
        {listed.map((feature) => (
          <Row key={feature.id} label={feature.title} detail={effectDetail(feature)}>
            {recorder(feature)}
          </Row>
        ))}
      </Section>

      {orphans.length === 0 ? null : (
        <Section title="Hidden features with shortcuts">
          {orphans.map((feature) => (
            <Row key={feature.id} label={feature.title} detail={effectDetail(feature)}>
              {recorder(feature)}
            </Row>
          ))}
        </Section>
      )}
    </div>
  )
}

/** What the shortcut will do, since it is not the same for every kind. */
function effectDetail(feature: FeatureSummary): string {
  return hotkeyEffect(feature.kind) === "run" ? "Runs it" : "Opens it"
}

