import {
  Atom,
  Boxes,
  Keyboard,
  MonitorSmartphone,
  ScrollText,
  SlidersHorizontal,
  Wrench,
  Wifi,
  type LucideIcon,
} from "lucide-react"

/**
 * A glyph per category, standing in for the Mac app's per-feature icons.
 *
 * The daemon deliberately drops `FeatureDef.icon` — those are SF Symbol names,
 * which mean nothing off Apple. Category icons keep the sidebar's visual
 * rhythm without inventing a second icon registry to drift from the first.
 * The pairings mirror `FeatureCategory.icon` in ADBKit.
 */
const BY_CATEGORY: Record<string, LucideIcon> = {
  input: Keyboard,
  connection: Wifi,
  reactNative: Atom,
  screen: MonitorSmartphone,
  deviceState: SlidersHorizontal,
  appManagement: Boxes,
  logs: ScrollText,
  toolUX: Wrench,
}

export function iconForCategory(category: string): LucideIcon {
  return BY_CATEGORY[category] ?? Wrench
}
