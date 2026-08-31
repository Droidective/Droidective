import {
  AppWindow,
  ArrowLeftRight,
  Atom,
  BadgeCheck,
  BatteryLow,
  BellRing,
  Boxes,
  Braces,
  Camera,
  ChartLine,
  CodeXml,
  Crosshair,
  Dices,
  FastForward,
  FileArchive,
  FileSearch,
  Film,
  FolderOpen,
  Gauge,
  Globe,
  Grid2x2,
  Hammer,
  HardDrive,
  Info,
  Keyboard,
  Languages,
  LifeBuoy,
  Layers,
  LayoutGrid,
  Link,
  LockKeyhole,
  LockOpen,
  MemoryStick,
  Monitor,
  MonitorPlay,
  MonitorSmartphone,
  Moon,
  Network,
  OctagonX,
  Package,
  PackageOpen,
  PackagePlus,
  Radio,
  RadioTower,
  RefreshCw,
  Ruler,
  ScrollText,
  Send,
  Server,
  Settings2,
  Shield,
  ShieldCheck,
  Signal,
  Signature,
  SlidersHorizontal,
  Smartphone,
  SquareMenu,
  SquareTerminal,
  Syringe,
  Terminal,
  TriangleAlert,
  Video,
  WandSparkles,
  Waypoints,
  Wifi,
  Wrench,
  type LucideIcon,
} from "lucide-react"

/**
 * A glyph per feature.
 *
 * The daemon deliberately drops `FeatureDef.icon` — those are SF Symbol names,
 * which mean nothing off Apple — so the pairing is made here instead, one
 * lucide icon per registry id, chosen to read as the same thing the Mac's
 * symbol does. Held client-side for the same reason as the category order:
 * it is a rendering choice, and shipping SF Symbol names to a web UI would
 * only invite it to depend on something it cannot draw.
 *
 * `icons.test.ts` fails if the daemon serves a feature this table has no entry
 * for, so a new feature shows up as a failing test rather than as a row
 * wearing its neighbour's icon.
 */
const BY_FEATURE: Record<string, LucideIcon> = {
  // Input & Clipboard
  "send-text": Keyboard,

  // Connection
  "get-ip": Globe,
  connection: Network,
  "reverse-port": ArrowLeftRight,
  "wireless-adb": RadioTower,
  emulators: MonitorPlay,
  "network-speed": Gauge,
  wifi: Wifi,
  "private-dns": LockKeyhole,

  // React Native
  "react-native": Atom,
  "open-dev-menu": SquareMenu,
  "reload-js": RefreshCw,
  "deep-link": Link,
  "process-death": OctagonX,
  "rn-dev-host": Server,
  reactotron: Radio,
  "js-console": CodeXml,

  // Screen & Capture
  scrcpy: Monitor,
  // The Mac's `square.grid.2x2` — several screens at once, not one.
  "mirror-wall": Grid2x2,
  screenshot: Camera,
  "screen-record": Video,
  "video-editor": Film,
  "demo-mode": WandSparkles,

  // Device State
  "file-explorer": HardDrive,
  "device-info": Info,
  "root-status": Shield,
  "system-restrictions": LockOpen,
  "dev-settings": Settings2,
  simulate: SlidersHorizontal,
  "fake-battery": BatteryLow,
  "dark-mode": Moon,
  "push-notification": BellRing,
  "layout-overrides": Ruler,
  "animation-scale": FastForward,
  locale: Languages,
  "network-toggles": Signal,
  "http-proxy": Waypoints,

  // App Management
  apps: LayoutGrid,
  "install-app": PackagePlus,
  "apk-studio": Wrench,
  "apk-inspector": FileSearch,
  "apk-sign": Signature,
  "apk-decompile": Braces,
  "aab-convert": PackageOpen,
  "frida-console": Syringe,
  "app-management": AppWindow,
  permissions: ShieldCheck,
  "app-info": Package,
  "current-activity": Layers,
  "foreground-package": Crosshair,
  meminfo: MemoryStick,
  "sandbox-browser": FolderOpen,
  monkey: Dices,

  // Logs & Diagnostics
  logcat: ScrollText,
  "ios-logs": Smartphone,
  "crash-catcher": TriangleAlert,
  "bug-report": FileArchive,
  performance: ChartLine,

  // Tool UX
  "api-client": Send,
  terminal: SquareTerminal,
  "custom-commands": Terminal,
}

/**
 * The fallback when a feature has no glyph of its own — a category still says
 * roughly what a thing is, which beats a generic square. The pairings mirror
 * `FeatureCategory.icon` in ADBKit.
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

/** The glyph for a feature, falling back to its category and then to a tool. */
/**
 * A role's glyph, standing in for the SF Symbol the Mac's `UserRole.icon`
 * names.
 *
 * The symbol names never cross the wire — they mean nothing off Apple — so the
 * mapping is here, chosen to say the same thing: a hammer for the Android
 * developer, an atom for React Native, a seal for QA, a life ring for support,
 * a shield for security.
 */
const BY_ROLE: Record<string, LucideIcon> = {
  "android-dev": Hammer,
  "rn-dev": Atom,
  "ios-dev": Smartphone,
  qa: BadgeCheck,
  support: LifeBuoy,
  security: ShieldCheck,
}

/** A role's glyph; a plain wrench for a role this build has not heard of. */
export function iconForRole(id: string): LucideIcon {
  return BY_ROLE[id] ?? Wrench
}

export function iconForFeature(id: string, category: string): LucideIcon {
  return BY_FEATURE[id] ?? BY_CATEGORY[category] ?? Wrench
}

/** Every registry id this build has a glyph for. */
export function featuresWithIcons(): string[] {
  return Object.keys(BY_FEATURE)
}
