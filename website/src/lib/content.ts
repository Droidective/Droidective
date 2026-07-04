import {
  Activity,
  Atom,
  Bug,
  Cast,
  Folder,
  LayoutGrid,
  ScrollText,
  Search,
  SlidersHorizontal,
  Wifi,
  type LucideIcon,
} from "lucide-react"

export const GITHUB_URL = "https://github.com/Droidective/Droidective"
export const LINKEDIN_URL = "https://www.linkedin.com/in/rohindh"
export const RELEASES_URL = `${GITHUB_URL}/releases`
export const LATEST_RELEASE_URL = `${GITHUB_URL}/releases/latest`
export const APP_VERSION = "v2.8.2"

export interface PaletteCommand {
  icon: LucideIcon
  name: string
  category: string
  shell: string
  keys: string
}

export const paletteCommands: PaletteCommand[] = [
  { icon: ScrollText, name: "Live Logcat", category: "Logs & Diagnostics", shell: "adb logcat -v color", keys: "logcat log logs crash" },
  { icon: Cast, name: "Mirror Screen", category: "Screen & Capture", shell: "scrcpy --max-size 1920", keys: "scrcpy mirror screen cast control" },
  { icon: SlidersHorizontal, name: "Fake Battery", category: "Device State", shell: "dumpsys battery set level 15", keys: "battery fake state simulate level" },
  { icon: Folder, name: "File Explorer", category: "Device State", shell: "adb shell ls /sdcard", keys: "file files explorer storage browse pull push" },
  { icon: Activity, name: "Performance Monitor", category: "Logs & Diagnostics", shell: "dumpsys gfxinfo", keys: "fps performance cpu ram jank monitor profile" },
  { icon: Atom, name: "Reload React Native", category: "React Native", shell: 'adb shell input text "RR"', keys: "react native reload metro dev menu rn" },
  { icon: Wifi, name: "Wireless ADB", category: "Connection", shell: "adb tcpip 5555", keys: "wifi wireless connect tcpip pair network" },
  { icon: LayoutGrid, name: "Apps Explorer", category: "App Management", shell: "pm list packages", keys: "apps app manage install uninstall permissions package" },
]

export const paletteQueries = ["logcat", "scrcpy", "battery", "fps", "wifi", "react"]

export interface Feature {
  icon: LucideIcon
  title: string
  body: string
  shell: string
}

export const features: Feature[] = [
  { icon: Search, title: "Command palette", body: "Fuzzy-search every tool and run it instantly. Pin favorites, bind global hotkeys, and stop looking up adb flags.", shell: "⌘K → run anything" },
  { icon: Cast, title: "Screen mirror & record", body: "A friendly GUI for scrcpy — mirror and control the device, tune bitrate, FPS and crop, record to file or GIF.", shell: "scrcpy --max-size 1920" },
  { icon: ScrollText, title: "Logcat & crash catcher", body: "Stream logs with level, tag and per-app filters, follow an app across restarts, grab the last crash for Slack or Jira.", shell: "adb logcat -v color" },
  { icon: Folder, title: "Device file explorer", body: "Browse shared storage — or the whole filesystem on rooted devices — copy, move, delete, and push/pull to your Mac.", shell: "adb pull /sdcard/..." },
  { icon: LayoutGrid, title: "App management", body: "Drag in an APK to install on every device, uninstall, force-stop, clear data, toggle runtime permissions, pull APKs, and browse a debug app's sandbox.", shell: "adb install app.apk" },
  { icon: Activity, title: "Performance monitor", body: "Live per-core CPU, RAM, FPS & jank, and network throughput — charted, recordable, exportable to JSON & CSV.", shell: "dumpsys gfxinfo" },
  { icon: Atom, title: "React Native tools", body: "Open the dev menu, reload the JS bundle, reverse the Metro port, and point the app at any dev server.", shell: "adb reverse tcp:8081" },
  { icon: Bug, title: "Reactotron, built in", body: "A full Reactotron debugger with no desktop app — Droidective runs the server itself. Live timeline of logs & API calls, a store browser, custom commands, and a REPL.", shell: "no Reactotron install" },
  { icon: Wifi, title: "Wireless ADB & connection", body: "Connect over Wi-Fi (with Android 11 pairing), manage Wi-Fi and private DNS, check root status, fan out to every device.", shell: "adb tcpip 5555" },
  { icon: SlidersHorizontal, title: "State simulation", body: "Fake the battery, force dark mode, change locale, scale fonts and density, set a proxy — every override is reset-tracked.", shell: "cmd uimode night yes" },
]

export interface Guide {
  icon: LucideIcon
  title: string
  body: string
  cta: string
  href: string
}

export const guides: Guide[] = [
  { icon: Atom, title: "React Native debugging", body: "Built-in Reactotron, the dev menu, JS reload, and Metro port forwarding — one RN hub, no terminal.", cta: "Open the RN guide →", href: "/react-native-debugger.html" },
  { icon: Search, title: "Android developers", body: "Tail logcat, watch performance, browse device files, and drive apps — every adb command behind ⌘K.", cta: "For Android developers →", href: "/for-android-developers.html" },
  { icon: Bug, title: "QA & testers", body: "Reproduce, capture, and report bugs in minutes — fake state, mark up a screenshot, pull a full bug report.", cta: "For QA & testers →", href: "/for-qa-and-testers.html" },
  { icon: Activity, title: "Support teams", body: "See the device, pull the diagnostics, close the ticket — mirror the screen and grab logs, no adb needed.", cta: "For support teams →", href: "/for-support-teams.html" },
  { icon: Cast, title: "scrcpy GUI for Mac", body: "A native GUI for scrcpy — mirror, control, and record your Android screen, with ffmpeg bundled in.", cta: "scrcpy GUI for Mac →", href: "/scrcpy-gui-mac.html" },
]

export interface Showcase {
  eyebrow: string
  title: string
  body: string
  ticks: { lead: string; rest: string }[]
  image: string
  alt: string
  flip: boolean
}

export const showcases: Showcase[] = [
  {
    eyebrow: "the palette",
    title: "One keystroke to everything",
    body: "Hit ⌘K from any screen and fuzzy-search all 56 tools. The device bar follows you, so every command targets the device you mean.",
    ticks: [
      { lead: "Pin favorites", rest: " and bind global hotkeys" },
      { lead: "Target one device", rest: " or fan out to all of them" },
      { lead: "Every run is logged", rest: " with the exact adb command" },
    ],
    image: "/assets/screenshot-palette.webp",
    alt: "Droidective ⌘K command palette filtering features for the query 'screen' — Screenshot, Screen Record, Mirror Screen and more",
    flip: false,
  },
  {
    eyebrow: "tabs & split panes",
    title: "A workspace, not a single screen",
    body: "Open features in tabs and keep them running while hidden, then split the window in two — tail logcat beside a live screen mirror, or watch performance next to the app it's profiling.",
    ticks: [
      { lead: "Open everything in tabs", rest: " — ⌘T opens, ⌃1–9 jump between them" },
      { lead: "Split into two panes", rest: " and drag a tab across the divide" },
      { lead: "Tabs keep running", rest: " in the background while you work elsewhere" },
    ],
    image: "/assets/screenshot-split.webp",
    alt: "Droidective split into two panes — a streaming logcat on the left and a live scrcpy screen mirror of the device on the right, with a multi-tab strip across the top",
    flip: true,
  },
  {
    eyebrow: "logs & diagnostics",
    title: "Tail logs, not terminal tabs",
    body: "A live logcat with the filters you actually reach for — and a crash catcher that formats the last crash for Slack or Jira.",
    ticks: [
      { lead: "Filter", rest: " by level, app, tag, or text" },
      { lead: "Follow an app", rest: " across restarts" },
      { lead: "Export", rest: " the buffer to a file" },
    ],
    image: "/assets/screenshot-logcat.webp",
    alt: "Droidective live logcat streaming color-coded log lines with level, app, tag and text filters",
    flip: false,
  },
  {
    eyebrow: "performance",
    title: "Watch performance live",
    body: "Per-core CPU, system RAM, app FPS & jank, and network throughput — charted as they happen, with a hover crosshair.",
    ticks: [
      { lead: "Record a session", rest: ", export to JSON & CSV" },
      { lead: "Per-process", rest: " CPU and memory" },
      { lead: "Dynamic axes", rest: " that track the live range" },
    ],
    image: "/assets/screenshot-performance.webp",
    alt: "Droidective performance monitor charting per-core CPU, system RAM and network throughput live during a recording",
    flip: true,
  },
  {
    eyebrow: "react native",
    title: "Made for React Native",
    body: "The RN essentials in one hub — no more remembering adb incantations to reload a bundle or reach Metro.",
    ticks: [
      { lead: "Reload JS", rest: ", open the dev menu, force process death" },
      { lead: "Reverse the Metro port", rest: " in a click" },
      { lead: "Set the dev-server host", rest: "; save deep links per app" },
    ],
    image: "/assets/screenshot-react.webp",
    alt: "Droidective React Native hub — reload JS, open the dev menu, force process death, forward Metro, and set the dev-server host",
    flip: false,
  },
]

export const galleryShots = [
  { image: "/assets/screenshot-apps.webp", alt: "Droidective apps explorer listing all installed and system apps with a selected app's info, permissions, and controls", title: "Apps explorer", caption: "Every installed & system app — info, permissions, force-stop, pull APK." },
  { image: "/assets/screenshot-files.webp", alt: "Droidective file explorer browsing the device's /sdcard directory", title: "File explorer", caption: "Browse, push & pull device files with a real progress bar." },
  { image: "/assets/screenshot-device.webp", alt: "Droidective device info showing RAM, storage, battery health and CPU for the connected device", title: "Device info", caption: "RAM, storage, battery health, CPU, and every getprop — searchable." },
  { image: "/assets/screenshot-hotkeys.webp", alt: "Droidective hotkeys settings — record a global shortcut to show the app, and a per-feature shortcut for any tool", title: "Global hotkeys", caption: "Bind a global shortcut to summon the app, and one per feature." },
  { image: "/assets/screenshot-tabs.webp", alt: "Droidective home screen with a multi-tab strip across the top — Home, Logcat, File Explorer, Device Info, React Native, Apps, Connection", title: "Tabbed home", caption: "Your most-used tools front and center, each a tab away." },
  { image: "/assets/screenshot-catalog.webp", alt: "Droidective feature catalog listing all 56 tools with on/off toggles", title: "Feature catalog", caption: "Toggle, reorder, and pin any of the 56 tools." },
]

export const releases: { version: string; date: string; latest?: boolean; html: string }[] = [
  { version: "v2.8.2", date: "Jul 2026", latest: true, html: "<b>JS Console reconnect fix</b> — a race killed each fresh Metro connection and leaked the old socket, so the console reconnected in a loop and spammed the dev server; connections are now generation-guarded with a bounded handshake, so it connects once and stays connected. Plus <b>anonymous performance self-monitoring</b> — sustained high CPU or memory in the app is reported with the features open at the time (opt-out in Settings → Privacy)." },
  { version: "v2.8.1", date: "Jul 2026", html: "<b>Built-in Terminal</b> — multi-tab PTY login shells with the selected device exported as ANDROID_SERIAL — plus <b>shell custom commands</b> through zsh, a <b>Security / Pentest role</b> with reworked per-role sidebars, a <b>Device Info</b> rework, and a round of performance fixes (launch hang, Reactotron memory, JS console search)." },
  { version: "v2.8.0", date: "Jul 2026", html: "<b>Tabbed workspace with split panes</b> — open features in tabs, keep them running while hidden, and split the window in two — plus a <b>React Native JS Console</b> over the Hermes CDP, a curated <b>Run on all devices</b> toggle, and a round of <b>light-mode fixes</b>." },
  { version: "v2.7.1", date: "Jun 2026", html: "<b>Screen mirroring on emulators</b> — scrcpy aborted the whole mirror (video included) when a device couldn't capture audio, which is most emulators; the in-app mirror now detects that and reconnects video-only, so it keeps working." },
  { version: "v2.7.0", date: "Jun 2026", html: "<b>APK Studio</b> — inspect, decompile (jadx/apktool with an in-app source viewer &amp; search), recompile, and sign an APK — plus <b>Frida setup</b>, a <b>custom accent color</b>, and <b>launching emulators from the device bar</b>." },
  { version: "v2.6.2", date: "Jun 2026", html: "<b>Security &amp; stability hardening</b> — shell-quoted device commands, bounded screen-mirror decoders, and cancelled actions that stop their adb child — plus a <b>leave guard</b> that confirms before discarding an active recording or unsaved edit, and <b>opening an APK from Finder</b> now previews its name, version &amp; SDK before installing." },
  { version: "v2.6.1", date: "Jun 2026", html: "<b>Custom command presets</b> — a library of common adb commands to add and run — plus a round of polish: Reactotron copy-as-cURL, per-pane export, and a search affordance; plain-English <b>install errors</b>; a dismissable toast; and <b>mirroring that survives device rotation</b>." },
  { version: "v2.6.0", date: "Jun 2026", html: "<b>Reactotron</b> built in — no desktop app, with a live timeline, store browser, custom commands, and a REPL — plus an <b>Install App</b> screen (drag in an APK), and <b>dark mode by default</b>." },
  { version: "v2.5.0", date: "Jun 2026", html: "<b>Role-based start</b> with a curated Home, a rebuilt Spotlight-style <b>⌘K palette</b> (pin, enable, multi-word search), and a <b>reorderable sidebar</b>." },
  { version: "v2.4.0", date: "Jun 2026", html: "<b>In-app screen mirror</b> and a <b>video editor</b>, with scrcpy &amp; ffmpeg bundled inside the app — and builds now <b>signed with a Developer ID and notarized by Apple</b>." },
  { version: "v2.3.0", date: "Jun 2026", html: "<b>Screenshot editor</b> overhaul — move, resize, and rotate annotations after drawing, adjustable blur/opacity, editable text, and a rotatable crop." },
  { version: "v2.2.0", date: "Jun 2026", html: "<b>Screenshot annotation editor</b> (pen, shapes, text, blur/solid redaction, crop, undo/redo), <b>feature hubs</b> that keep the sidebar short, a <b>live memory graph</b>, and every feature on by default." },
  { version: "v2.1.0", date: "Jun 2026", html: "<b>Device control suite</b> — Wi-Fi, private DNS, root status, system restrictions — plus in-app feedback and <b>automatic updates</b> via Sparkle." },
  { version: "v2.0.0", date: "Jun 2026", html: "<b>Performance monitor</b> and <b>network speed</b> graphs, a home screen and welcome tour, and a per-feature command bar with an embedded terminal." },
  { version: "v1.0.0", date: "Jun 2026", html: "First public release — 37 one-click adb actions behind <code>⌘K</code>, built on a fully tested ADBKit engine." },
]

export const faqs: { q: string; html: string }[] = [
  { q: "Is it really free?", html: "Yes. Droidective is MIT-licensed and fully open source — no account, no paywall, no pro tier. Star it, fork it, ship it." },
  { q: "Is it signed and safe to open?", html: "Yes. Release builds are signed with an Apple Developer ID and notarized by Apple, so they open with a normal double-click — no Gatekeeper workaround needed. Everything is open source, and you can build from source if you prefer." },
  { q: "Do I need a rooted device?", html: "No. Everything works on a normal device. A few extras — full-filesystem browsing, saved Wi-Fi passwords, SELinux mode and read-write remount — unlock automatically when root is available." },
  { q: "What do I need installed?", html: "Just Android <code>adb</code>. Droidective finds it via <code>ANDROID_HOME</code>, the default SDK path, or Homebrew, and offers a one-click install if it's missing. <code>scrcpy</code> and <code>ffmpeg</code> ship inside the app, so mirroring, recording, and video export work out of the box — only the Android <code>emulator</code> is optional, for AVD management." },
  { q: "Does it send my data anywhere?", html: 'Anonymous crash reports and usage analytics are on by default (opt-out) — both disclosed on first launch and controlled in Settings → Privacy. Device serials, file paths, and command contents are never sent. See the <a href="/privacy.html">privacy page</a> for details.' },
  { q: "Does it work with React Native?", html: "Yes — there's a dedicated React Native hub: open the dev menu, reload the JS bundle, reverse the Metro port, save deep links per app, and set the dev-server host." },
  { q: "Apple Silicon or Intel?", html: "Both. Droidective runs on any Mac with macOS 14 Sonoma or later." },
]

export const footerLinks = [
  { label: "GitHub", href: GITHUB_URL },
  { label: "Releases", href: RELEASES_URL },
  { label: "Changelog", href: "#changelog" },
  { label: "Issues", href: `${GITHUB_URL}/issues` },
  { label: "License", href: `${GITHUB_URL}/blob/main/LICENSE` },
  { label: "Privacy", href: "/privacy.html" },
  { label: "For Android developers", href: "/for-android-developers.html" },
  { label: "For QA & testers", href: "/for-qa-and-testers.html" },
  { label: "For support teams", href: "/for-support-teams.html" },
  { label: "React Native debugger", href: "/react-native-debugger.html" },
  { label: "scrcpy GUI for Mac", href: "/scrcpy-gui-mac.html" },
]
