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
  {
    id: "tools",
    label: "Tools",
    icon: Wrench,
    blockedBy:
      "The managed-tool store — jadx, apktool, frida, a bundled JRE — is not ported yet. It arrives with the APK features.",
  },
  { id: "hotkeys", label: "Hotkeys", icon: Keyboard },
  {
    id: "mcp",
    label: "MCP",
    icon: Plug,
    blockedBy:
      "The Reactotron MCP server follows the Reactotron relay, which needs its Network.framework listener ported to NIO.",
  },
]
