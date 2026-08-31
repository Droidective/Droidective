import { Bug, Info, Keyboard, Palette, Plug, Settings2, Wrench } from "lucide-react"
import type { LucideIcon } from "lucide-react"

/**
 * The Settings tabs — the Mac's seven, in its order.
 *
 * Every one is listed, including the tabs whose subsystem is not ported yet.
 * A tab that simply vanished would be a silent difference between the two
 * apps; one that says what it is waiting on is a visible, checkable one, and
 * it matches what `docs/desktop-parity.md` records.
 */

export type SettingsTab =
  | "general"
  | "appearance"
  | "privacy"
  | "doctor"
  | "tools"
  | "hotkeys"
  | "mcp"

export interface SettingsTabDef {
  id: SettingsTab
  label: string
  icon: LucideIcon
  /** Why the tab is empty, for the ones that are. */
  blockedBy?: string
}

export const SETTINGS_TABS: readonly SettingsTabDef[] = [
  { id: "general", label: "General", icon: Settings2 },
  { id: "appearance", label: "Appearance", icon: Palette },
  { id: "privacy", label: "Privacy", icon: Info },
  { id: "doctor", label: "Doctor", icon: Bug },
  { id: "tools", label: "Tools", icon: Wrench },
  { id: "hotkeys", label: "Hotkeys", icon: Keyboard },
  {
    id: "mcp",
    label: "MCP",
    icon: Plug,
    blockedBy:
      "Reactotron itself has landed; the MCP server has not. Its package is gated to Apple end to end and reads ADBKit's Network.framework relay, so serving it here means feeding the MCP command store from the daemon's NIO relay instead.",
  },
]
