import { useEffect, useState } from "react"
import { Button, Switch } from "@/components/Controls"
import { Row, Section } from "@/components/settings/SettingsKit"
import { backgroundAvailable } from "@/lib/daemon"
import { panelEligibleActions } from "@/lib/quick-actions"
import { sidebarSections, visibleFeatures } from "@/lib/sidebar"
import type { FeatureSummary } from "@/lib/wire"

export interface GeneralTabProps {
  features: FeatureSummary[]
  keepRunningInBackground: boolean
  onKeepRunningInBackground: (on: boolean) => void
  /** The features explicitly chosen for the tray; empty means "not chosen". */
  trayItems: readonly string[]
  onTrayItem: (id: string, listed: boolean) => void
  /** Actions removed from the Quick Actions panel. */
  quickPanelHiddenIds: readonly string[]
  onQuickPanelAction: (id: string, shown: boolean) => void
  quickPanelCloseAfterRun: boolean
  onQuickPanelCloseAfterRun: (on: boolean) => void
  sidebarOrder: readonly string[]
  categoryOrder: readonly string[]
  favorites: readonly string[]
  disabledFeatures: readonly string[]
  /** The role in effect, or null for "everything". */
  selectedRole: string | null
  /** Re-opens the picker — the Mac's "Change role…". */
  onChangeRole: () => void
}

/**
 * Settings ▸ General.
 *
 * The Mac's General holds the role picker, Open at login, background mode, the
 * Quick Actions preferences, the updater and the menu-bar switch. All but the
 * last two are here; those still name what they wait on rather than showing a
 * control that does nothing.
 */
export function GeneralTab(props: GeneralTabProps) {
  return (
    <div className="flex flex-col gap-5">
      <RoleSection {...props} />
      <BackgroundSection {...props} />
      <QuickActionsSection {...props} />
      <TraySection {...props} />
      <Section title="Not ported yet">
        <Row
          label="Open at login"
          detail="Needs tauri-plugin-autostart. Backlog item 8."
        >
          <Waiting />
        </Row>
        <Row
          label="Updates"
          detail="Sparkle is macOS-only. tauri-plugin-updater needs a signing keypair whose private half lives in a repository secret, which is the maintainer's to create — so this is blocked on a decision rather than on work."
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
/**
 * The role in effect, and the way back to the picker.
 *
 * It names the role rather than only offering the button, because a curated
 * sidebar with no visible cause is the thing people come to Settings to
 * understand — "where did half my features go?" is answered here.
 */
function RoleSection({ selectedRole, onChangeRole }: GeneralTabProps) {
  return (
    <Section title="Role">
      <Row
        label={selectedRole === null ? "Showing everything" : ROLE_LABELS[selectedRole] ?? selectedRole}
        detail="A role curates which features the sidebar lists. Everything else stays one search away."
      >
        <Button onClick={onChangeRole}>Change role…</Button>
      </Row>
    </Section>
  )
}

/**
 * The role names, for the one place a role has to be named without the
 * catalogue at hand.
 *
 * A second copy of six strings, and the only one in this app — the *lists*
 * that would really drift are served. Falling back to the raw id means a role
 * added to the registry later reads as its id here rather than not at all.
 */
const ROLE_LABELS: Record<string, string> = {
  "android-dev": "Android Developer",
  "rn-dev": "React Native Developer",
  "ios-dev": "iOS Developer",
  qa: "QA / Tester",
  support: "Support / Triage",
  security: "Security / Pentest",
}

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
 * The Mac's Quick Actions section, less its resume picker.
 *
 * "Resume where I left off" is not here: the Mac's panel keeps a session in
 * memory because the app is resident behind it, and this panel is a window that
 * is created on first use and hidden after. It would be a preference over
 * behaviour that does not exist yet, which is worse than an absent one.
 */
function QuickActionsSection({
  features,
  disabledFeatures,
  quickPanelHiddenIds,
  onQuickPanelAction,
  quickPanelCloseAfterRun,
  onQuickPanelCloseAfterRun,
}: GeneralTabProps) {
  const eligible = panelEligibleActions(features, disabledFeatures)
  return (
    <Section title="Quick Actions">
      <Row
        label="Close the panel after running an action"
        detail="A successful action dismisses the panel right after its result shows; a failed one keeps it open so you can read the error."
      >
        <Switch
          checked={quickPanelCloseAfterRun}
          onChange={onQuickPanelCloseAfterRun}
          ariaLabel="Close the panel after running an action"
        />
      </Row>
      <p className="pt-1 text-[11.5px] text-text-tertiary">
        Switched-off actions leave the panel’s action grid. Custom commands are managed on the
        Custom Commands screen.
      </p>
      {eligible.map((feature) => (
        <Row key={feature.id} label={feature.title}>
          <Switch
            checked={!quickPanelHiddenIds.includes(feature.id)}
            onChange={(shown) => {
              onQuickPanelAction(feature.id, shown)
            }}
            ariaLabel={feature.title}
          />
        </Row>
      ))}
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
