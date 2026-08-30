import { useEffect, useState } from "react"
import { Switch } from "@/components/Controls"
import { Row, Section } from "@/components/settings/SettingsKit"
import { backgroundAvailable } from "@/lib/daemon"
import { sidebarSections, visibleFeatures } from "@/lib/sidebar"
import type { FeatureSummary } from "@/lib/wire"

export interface GeneralTabProps {
  features: FeatureSummary[]
  keepRunningInBackground: boolean
  onKeepRunningInBackground: (on: boolean) => void
  /** The features explicitly chosen for the tray; empty means "not chosen". */
  trayItems: readonly string[]
  onTrayItem: (id: string, listed: boolean) => void
  sidebarOrder: readonly string[]
  categoryOrder: readonly string[]
  favorites: readonly string[]
  disabledFeatures: readonly string[]
}

/**
 * Settings ▸ General.
 *
 * The Mac's General holds the role picker, Open at login, background mode, the
 * Quick Actions preferences, the updater and the menu-bar switch. Background
 * and the tray are here; the rest still name what they wait on rather than
 * showing switches that control nothing.
 */
export function GeneralTab(props: GeneralTabProps) {
  return (
    <div className="flex flex-col gap-5">
      <BackgroundSection {...props} />
      <TraySection {...props} />
      <Section title="Not ported yet">
        <Row
          label="Role"
          detail="The role picker curates which features the sidebar lists. Backlog item 9."
        >
          <Waiting />
        </Row>
        <Row
          label="Open at login"
          detail="Needs tauri-plugin-autostart. Backlog item 8."
        >
          <Waiting />
        </Row>
        <Row
          label="Quick Actions"
          detail="The global-hotkey mini app is backlog item 19; its preferences arrive with it."
        >
          <Waiting />
        </Row>
        <Row
          label="Updates"
          detail="Sparkle is macOS-only; tauri-plugin-updater is backlog item 23."
        >
          <Waiting />
        </Row>
      </Section>
    </div>
  )
}

/**
 * The Mac's Background section, with one condition it does not need.
 *
 * macOS always has a menu bar. Here the tray is the only way back to a hidden
 * window, and a desktop can decline to give the app one — a Linux session with
 * no indicator host, most often. So the switch is offered only when a tray
 * icon actually exists, and says why when it does not, rather than hiding the
 * window somewhere nobody can reach.
 */
function BackgroundSection({
  keepRunningInBackground,
  onKeepRunningInBackground,
}: GeneralTabProps) {
  const available = useTrayPresent()
  return (
    <Section title="Background">
      <Row
        label="Keep running in the background"
        detail={
          available === false
            ? "Unavailable: this desktop gave Droidective no tray icon, so a hidden window would have nothing to bring it back. Closing the window quits."
            : "Closing the window stops running feature work — including terminal shells — and leaves Droidective in the tray. Quit it from there."
        }
      >
        <Switch
          checked={keepRunningInBackground && available !== false}
          disabled={available === false}
          onChange={onKeepRunningInBackground}
          ariaLabel="Keep running in the background"
        />
      </Row>
    </Section>
  )
}

/**
 * The Mac's Menu bar section — its item chooser, and not its on/off switch.
 *
 * The Mac can hide its menu-bar icon because macOS will still reopen the app
 * from the Dock or Finder. Nothing guarantees that here: with the tray gone and
 * the window hidden, the app would be running with no way in. The switch is
 * therefore absent rather than present and dangerous, which is the same kind of
 * forced divergence as the three moved accelerators.
 */
function TraySection({
  features,
  trayItems,
  onTrayItem,
  sidebarOrder,
  categoryOrder,
  favorites,
  disabledFeatures,
}: GeneralTabProps) {
  const listed = visibleFeatures(
    sidebarSections(features, {
      query: "",
      sidebarOrder,
      categoryOrder,
      collapsedCategories: [],
      favorites,
      disabledFeatures,
    }),
  )
  return (
    <Section title="Tray">
      <p className="text-[11.5px] text-text-tertiary">
        When none are selected, your pinned features (or enabled instant actions) are shown.
        Screenshot and Mirror Screen always appear.
      </p>
      {listed.map((feature) => (
        <Row key={feature.id} label={feature.title}>
          <Switch
            checked={trayItems.includes(feature.id)}
            onChange={(on) => {
              onTrayItem(feature.id, on)
            }}
            ariaLabel={feature.title}
          />
        </Row>
      ))}
    </Section>
  )
}

/** Null until Rust has answered — the switch renders normally meanwhile. */
function useTrayPresent(): boolean | null {
  const [present, setPresent] = useState<boolean | null>(null)
  useEffect(() => {
    let live = true
    void backgroundAvailable().then(
      (answer) => {
        if (live) setPresent(answer)
      },
      () => {
        // Outside a Tauri webview. Leaving it unknown shows the switch, which
        // is the right default for a question that could not be asked.
      },
    )
    return () => {
      live = false
    }
  }, [])
  return present
}

function Waiting() {
  return <span className="text-[11.5px] text-text-tertiary">Not yet</span>
}
