import { Row, Section } from "@/components/settings/SettingsKit"

/**
 * Settings ▸ General.
 *
 * The Mac's General holds the role picker, Open at login, background mode,
 * the Quick Actions preferences, the updater and the menu-bar switch. Every
 * one of those drives a subsystem this app does not have yet, so rather than
 * showing switches that control nothing, this says which ones are coming and
 * from where — the same list `docs/desktop-parity.md` keeps.
 */
export function GeneralTab() {
  return (
    <div className="flex flex-col gap-5">
      <Section title="Not ported yet">
        <Row
          label="Role"
          detail="The role picker curates which features the sidebar lists. Backlog item 9."
        >
          <Waiting />
        </Row>
        <Row
          label="Open at login"
          detail="Needs tauri-plugin-autostart, which arrives with background mode."
        >
          <Waiting />
        </Row>
        <Row
          label="Keep running in the background"
          detail="Background mode and the tray icon are backlog item 20."
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

function Waiting() {
  return <span className="text-[11.5px] text-text-tertiary">Not yet</span>
}
