import {
  Activity,
  Atom,
  Boxes,
  Cast,
  Folder,
  LayoutGrid,
  ScrollText,
  SlidersHorizontal,
  Sparkles,
  Wifi,
  type LucideIcon,
} from "lucide-react"

export const GITHUB_URL = "https://github.com/Droidective/Droidective"
export const LINKEDIN_URL = "https://www.linkedin.com/in/rohindh"
export const RELEASES_URL = `${GITHUB_URL}/releases`
// GitHub's permanent latest-release asset URL: every release uploads a
// stable-named Droidective.dmg (see ci.yml), so this always serves the
// newest version — no appcast fetch, nothing cached to go stale.
export const DOWNLOAD_URL = `${GITHUB_URL}/releases/latest/download/Droidective.dmg`
export const APP_VERSION = "v3.8.2"

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

/** A major workflow category for the "Built for how you debug" explorer.
 *  `visual` is either a real asset or a CSS mock (no screenshot exists for
 *  APK Studio or the MCP flow, and an unrelated shot would mislead). */
export interface Workflow {
  id: string
  num: string
  tab: string
  icon: LucideIcon
  title: string
  blurb: string
  features: string[]
  image?: string
  video?: string
  mock?: "apk" | "mcp"
  alt?: string
}

export const workflows: Workflow[] = [
  {
    id: "react-native",
    num: "01",
    tab: "React Native",
    icon: Atom,
    title: "Understand what your app does while it runs",
    blurb:
      "Reactotron is built in — no desktop app to install. Point your client at Droidective and a live timeline of logs, actions, state, and network requests streams in beside a Hermes JS console.",
    features: ["Reactotron timeline", "Hermes JS console", "Redux & state browser", "Network inspector", "Reload JS & dev menu", "Metro port forwarding"],
    image: "/assets/screenshot-react.webp",
    alt: "Droidective's React Native hub with quick-action cards for reload JS, dev menu and process death, plus a Metro bundler section",
  },
  {
    id: "device",
    num: "02",
    tab: "Device",
    icon: Cast,
    title: "Drive the device without touching a terminal",
    blurb:
      "Mirror and control the screen, browse the filesystem, manage every installed app, and pair over Wi-Fi — in tabs that keep running while you work elsewhere, or split side by side.",
    features: ["Screen mirror & control", "Screen recording", "File explorer", "App management", "Wireless ADB pairing", "Tabs & split panes"],
    video: "/assets/tour-tabs.mp4",
    image: "/assets/poster-tabs.webp",
    alt: "Droidective opening features in tabs and dragging a tab across the divider to split the window into two panes",
  },
  {
    id: "performance",
    num: "03",
    tab: "Performance",
    icon: Activity,
    title: "Watch the numbers move in real time",
    blurb:
      "Per-core CPU, system RAM, app FPS and jank, and network throughput — charted as they happen with a hover crosshair. Record a session and export it to JSON or CSV.",
    features: ["Per-core CPU", "System & per-process RAM", "FPS & jank", "Network throughput", "Session recording", "JSON & CSV export"],
    image: "/assets/screenshot-performance.webp",
    alt: "Droidective performance monitor charting per-core CPU, system RAM and network throughput live during a recording",
  },
  {
    id: "apk",
    num: "04",
    tab: "APK",
    icon: Boxes,
    title: "Open an APK and see everything inside it",
    blurb:
      "One workspace over a single loaded APK — inspect the manifest and signing certs, decompile with jadx or apktool, recompile, and re-sign. AAB bundles convert to installable APKs too.",
    features: ["Manifest & cert inspection", "jadx + apktool decompile", "Recompile & re-sign", "AAB → APK conversion", "Keystore creation", "Frida server setup"],
    mock: "apk",
  },
  {
    id: "ai",
    num: "05",
    tab: "AI / MCP",
    icon: Sparkles,
    title: "Let your AI agent read the running app",
    blurb:
      "An opt-in MCP server exposes Reactotron's timeline, state, and network data to Claude Code, Cursor, and any MCP client — 10 tools and 8 resources over loopback HTTP, redacted by default.",
    features: ["10 MCP tools", "8 MCP resources", "Live timeline access", "State & network context", "Redaction on by default", "127.0.0.1 only"],
    mock: "mcp",
  },
  {
    id: "report",
    num: "06",
    tab: "Logs & QA",
    icon: ScrollText,
    title: "Capture exactly what went wrong",
    blurb:
      "A columnar logcat with level, tag, and per-app filters that holds the tail while you read. The crash catcher splits Java, native, RN, and ANR crashes into a filterable, copy-ready list.",
    features: ["Columnar logcat", "Level & tag filters", "Crash catcher", "Annotated screenshots", "Full bug reports", "State simulation"],
    image: "/assets/screenshot-logcat.webp",
    alt: "Droidective live logcat streaming color-coded log lines with level, app, tag and text filters",
  },
]

/** The "old workflow vs Droidective" comparison. Category-level, never a
 *  claim that a named competitor is worse. */
export const comparisonRows: { workflow: string; old: string; nu: string }[] = [
  { workflow: "Device management", old: "adb one-liners you re-look-up", nu: "A device bar and a searchable UI" },
  { workflow: "Screen mirroring", old: "scrcpy in its own window", nu: "Mirrored in a tab or split pane" },
  { workflow: "Logs", old: "A terminal tail you scroll past", nu: "Columnar logcat with filters" },
  { workflow: "React Native", old: "Reactotron desktop + Metro + CLI", nu: "One built-in RN hub" },
  { workflow: "Performance", old: "dumpsys output you parse by eye", nu: "Live charts you can record" },
  { workflow: "APK work", old: "jadx, apktool, apksigner by hand", nu: "APK Studio over one file" },
  { workflow: "AI context", old: "Paste logs into a chat window", nu: "MCP reads the live app" },
  { workflow: "Price", old: "Varies per tool", nu: "Free · MIT · no tiers" },
]

/** Grouped feature explorer — collapsed by default so the page stays calm. */
export const featureGroups: { name: string; icon: LucideIcon; count: string; items: string[] }[] = [
  {
    name: "React Native",
    icon: Atom,
    count: "6 tools",
    items: ["Reactotron (built in)", "Hermes JS console", "Reactotron MCP server", "Reload JS & dev menu", "Metro port forwarding", "Dev-server host override"],
  },
  {
    name: "Device control",
    icon: Cast,
    count: "12 tools",
    items: ["Screen mirror & control", "Screen recording", "Screenshot editor", "File explorer", "Apps explorer", "Install APK", "Deep links", "Send text", "Wireless ADB & pairing", "Private DNS", "Root status", "Emulator manager"],
  },
  {
    name: "Logs & diagnostics",
    icon: ScrollText,
    count: "7 tools",
    items: ["Live logcat", "iOS unified logs", "Crash catcher", "Bug report", "Device info & getprop", "Terminal (split panes)", "Custom commands"],
  },
  {
    name: "Performance",
    icon: Activity,
    count: "4 tools",
    items: ["Per-core CPU & RAM", "FPS & jank monitor", "Per-process stats", "Network throughput"],
  },
  {
    name: "APK & security",
    icon: Boxes,
    count: "6 tools",
    items: ["APK Studio", "APK inspector", "Decompile (jadx / apktool)", "Sign & zipalign", "AAB → APK converter", "Frida server setup"],
  },
  {
    name: "State simulation",
    icon: SlidersHorizontal,
    count: "10 tools",
    items: ["Fake battery", "Dark mode", "Demo mode", "Locale override", "Font & density scale", "Proxy override", "Developer settings", "Push notifications (iOS)", "Sandbox browser", "System restrictions"],
  },
]

/** Human-framed moments, not feature names. */
export const useCaseMoments: { quote: string; answer: string; href: string }[] = [
  { quote: "“The app is crashing.”", answer: "Open the crash catcher, read the split-out trace, and copy it Slack-ready.", href: "/for-qa-and-testers.html" },
  { quote: "“The app feels slow.”", answer: "Chart CPU, RAM, FPS and jank live, then record the session and export it.", href: "/for-android-developers.html" },
  { quote: "“I need to inspect this APK.”", answer: "Drop it into APK Studio — manifest, certs, decompiled source, re-sign.", href: "/for-security-testers.html" },
  { quote: "“What is my RN app doing?”", answer: "Reactotron streams the timeline; MCP hands the same context to your AI.", href: "/react-native-debugger.html" },
]

export const releases: { version: string; date: string; latest?: boolean; html: string }[] = [
  { version: "v3.8.2", date: "Aug 2026", latest: true, html: "<b>JS Console fixes for split panes</b> — the feed left blank space that grew every time the pane changed width, because a row measured its height against a baseline that was still moving and a wrapped message drew past the height its row reported. And the console <b>now shrinks to the pane it is given</b>: the connection bar held its target label at full width — <code>com.myapp.features · Pixel 7 - 17 - API 37</code> is most of a split pane — which became the minimum for everything below it, so rows were laid out wider than the pane and cut off at its edge. That also brings back the filter row's level, find, export and clear controls and each row's timestamp at the narrowest split. A <code>console.table</code> no longer sizes the whole feed, and <b>where a log came from is an icon</b> in the row's hover controls beside the copy buttons, with the file, line, function and path in its tooltip." },
  { version: "v3.8.1", date: "Aug 2026", html: "<b>The JS Console reads like Chrome DevTools</b> — a log's arguments sit on one line with their objects inline instead of one object stacked per line, top-level strings print bare (<code>console.log('hi')</code> shows <code>hi</code>), arrays lead with their length, and a nested object shows <code>{…}</code>. <b>Every row says where it came from</b> — <code>StreamScreen.tsx:142</code> at the right edge, resolved through Metro so it names the file you wrote rather than a line in the bundle; clicking it opens the whole stack with framework and <code>node_modules</code> frames dimmed. <b><code>console.group</code> blocks indent and fold</b>, <code>console.groupCollapsed</code> starts folded, and <b><code>console.table</code> draws a table</b>. Collapsed values preview their first few properties instead of a key count, and terminal colour codes in React Native's dev-server notices are rendered rather than printed. Plus fixes: <b>copying a log now takes the object with it</b> as real JSON (a second button copies just the object), <b>clicking inside an expanded object keeps it open</b> instead of folding the whole value back up, and expanding a logged <code>Error</code> shows its stack instead of an empty box." },
  { version: "v3.8.0", date: "Aug 2026", html: "<b>API Testing</b> — the 60th tool is a full HTTP client that needs no device: all seven methods, six body kinds (JSON, form-urlencoded, multipart, raw, GraphQL, binary) and five auth kinds, with <b>Postman collections and environments importing and exporting</b> both ways. Organise requests in searchable nested folders, resolve <code>{{variables}}</code> from environment and global scopes (unresolved ones are flagged before a send, not sent literally), assert on status, timing, body, headers or a JSON path, and run a whole collection in one sheet. Every request exports as cURL, HTTPie, <code>fetch</code>, axios, Python <code>requests</code> or Swift <code>URLSession</code> — and pasting a cURL command parses it back. The response pane shows pretty and raw bodies, an image preview, headers, cookies, a timing breakdown and the redirect chain, with JSON in the server's own key order. <b>Recordings can capture microphone audio</b> — the Mac's mic alongside the device, mixed onto one track, with a level meter in the setup sheet and per-source mute mid-take. <b>The Terminal scrolls full-screen programs</b> — an agent CLI, <code>htop</code>, <code>less --mouse</code> or vim with <code>mouse=a</code> couldn't be scrolled at all, and scrolling one left two frames interleaved on screen; the wheel now reaches the program by the scroll's own distance, the alternate screen's margin is repaired, and <b>scrollback stays put while output streams</b> instead of snapping to the newest line. Plus fixes for four main-thread hangs: a cold font registry at launch, the log tail typesetting its whole buffer, Settings ▸ General's launch-at-login check, and resizing with a heavyweight tab open." },
  { version: "v3.7.1", date: "Jul 2026", html: "<b>Developer Settings</b> — the 59th tool drives Android's Developer Options over adb: show taps, pointer location, layout bounds, GPU overdraw, GPU profile bars, strict-mode flash, don't keep activities, and the three animation scales — read from the device and applied instantly. The <b>mirror gains a Show touches toggle</b> behind a new ⋯ options menu (flips instantly, mid-recording included; the device's own setting is restored when the session ends), <b>emulators wipe and relaunch as separate actions</b> — Wipe Data works in place without booting the AVD, and running emulators get a Relaunch button — the <b>Terminal's collapsed rail shows a clickable badge per open shell</b>, and <b>files dropped on a shell type their paths</b>, quoted only when needed. Plus fixes: a welcome-tour crash on double-activated paging, an update pill that could stick on “Installing update…”, and JS Console hangs on chatty Metro streams." },
  { version: "v3.7.0", date: "Jul 2026", html: "<b>Universal app + Reactotron MCP</b> — the DMG now runs natively on Intel Macs (arm64 + x86_64 slices of both the app and the bundled ffmpeg, with packaging that refuses a DMG missing a slice), and an <b>opt-in MCP server</b> exposes the Reactotron relay's timeline, state, and network data to AI agents like Claude Code and Cursor over localhost HTTP — upstream Reactotron's exact tool contract, redaction on by default, loopback-only with Origin validation. The <b>Terminal resumes your working directories</b> — quit, close the tab, or close the window and the next open starts a shell per remembered directory (tabs you close yourself are forgotten). Both consoles' Restart gains a confirmed <b>Clear data and restart</b>, split Reactotron panes keep <b>independent sort orders</b>, a hidden <b>mirror survives tab flips</b> for a two-minute grace window (re-targeting if you switched devices), and the What's New sheet matches the app's theme." },
  { version: "v3.6.1", date: "Jul 2026", html: "<b>Bug-fix release</b> — resizing a split or the window with Mirror Screen and streaming log tabs open no longer slows to a crawl: the log view re-wrapped its entire buffer on every tick of a drag and now re-wraps once when the drag rests, and log feeds coalesce updates (3 refreshes per second instead of 8), roughly halving idle CPU with a busy logcat tab." },
  { version: "v3.6.0", date: "Jul 2026", html: "<b>Export &amp; find-in-object for the JS Console and Reactotron</b> — save or copy the filtered feed as JSON, and search inside any expanded object with clickable results that expand the tree straight to the match. <b>The console connects itself</b> — discovery runs <code>adb reverse</code> for you, half-dead connections self-heal, and auto-connect waits for a booting app to settle; Restart app gains a <b>Clear cache and restart</b> option. <b>Logcat becomes a columnar log viewer</b> — time, pid-tid, live process names, level chips, colored tags, and severity-tinted messages, with a selection that holds the tail while the stream runs. <b>Emulators go by their AVD names</b> everywhere devices are listed, the device bar gains a one-click <b>Mirror Screen</b> button, and the <b>React Native role spans Android and iOS Simulators</b>. Plus a <b>custom window background &amp; text color</b> that follows the background's luminance, grain at any opacity, a redesigned What's New sheet, and the mirror re-fitting its pane when a split resizes." },
  { version: "v3.5.0", date: "Jul 2026", html: "<b>Translucent window</b> — Opacity, Blur, and Grain sliders in Settings ▸ Appearance turn the whole app to glass over your desktop (down to 10%, every surface obeys, terminal included). <b>Reactotron remembers</b> — per-pane timeline filters, search, and the split persist across relaunches; split panes get their own clear (an accidental right-pane clear is undone by closing and reopening the split), the main pane stays anchored when the split toggles, rows fit the pane with no horizontal scrolling, whole rows click to expand, and <b>⌘-click opens JS Console URLs</b> in the browser. Plus a <b>redesigned Send Text</b> — two hub sections over one snippet list with click-to-append placeholders — and <b>stop for running emulators &amp; simulators</b> in Quick Actions." },
  { version: "v3.4.1", date: "Jul 2026", html: "<b>Bug-fix release</b> — converting an AAB no longer crashes the app on the newest macOS (the notification-permission request that tells you when a background install finishes ran on the wrong thread — allowed and denied both crashed), and the signing <b>keystore chooser now only accepts <code>.keystore</code> / <code>.jks</code> files</b> in the AAB converter and APK Studio's Sign tab." },
  { version: "v3.4.0", date: "Jul 2026", html: "<b>AAB to APK converter</b> — the 58th tool turns an Android App Bundle into an installable universal APK via bundletool (shipped inside the app, works offline), with optional release-keystore signing, and double-clicked <code>.aab</code>/<code>.apk</code> files open right in the app with per-device install rows. <b>Updates install themselves</b> — silent download and a “Relaunch to update” pill, a What's New sheet after updating, and installs that finish even if you just quit. The <b>Crash Catcher becomes a multi-crash browser</b> — Java, native, React Native, and ANR crashes split into a filterable list with trace highlighting, watch mode, and a 16 MB fetch that stops dropping the newest crashes. Plus <b>wireless pairing that auto-connects</b> (mDNS discovers the connect port), a reworked <b>Send Text snippet library</b>, split panes clamped to 30–70% with every feature adapting to narrow widths, and a skippable welcome tour." },
  { version: "v3.3.1", date: "Jul 2026", html: "<b>iOS Logs, rebuilt for the unified log</b> — the stream is scoped to your installed apps by default (the whole-OS firehose is one click away), scrolling up freezes the feed while new lines wait behind a <b>“N new” pill</b>, and entries render Xcode-style: message first, a toggleable metadata line, severity color bars, and tinted error/fault rows with <b>live error &amp; fault counters</b> that flip the feed to errors only. <b>⌘F now always lands where you expect</b> — the find bar in Logcat, iOS Logs, and the JS Console, the timeline search in Reactotron — never the sidebar. Plus a <b>Check for Updates button in Settings</b> and an optional <b>auto-closing Quick Actions panel</b> after a successful run." },
  { version: "v3.3.0", date: "Jul 2026", html: "<b>A JS console that stays connected</b> — a keepalive satisfies React Native's inspector-proxy heartbeat, reconnects survive app relaunches, phone sleep, and Metro restarts, and logs no longer duplicate after each reconnect. The <b>screen mirror's runaway CPU is fixed</b> (leaked background sessions), its latency drops, and device audio becomes opt-in. <b>Logcat splits Filter and Find</b>: the field hides non-matching lines while <kbd>⌘F</kbd> highlights and steps through matches with a counter — and the new <b>iOS Logs</b> feature streams a booted simulator's native logs in the same pane. The device dropdown refreshes itself on open, and sidebar &amp; split-pane resizing is smooth." },
  { version: "v3.2.0", date: "Jul 2026", html: "<b>Pair &amp; connect over Wi-Fi from the device dropdown</b> — the device menu gains a Wireless debugging section opening a guided sheet with three paths: Android 11+ pairing with a code (numbered steps that mirror the phone's pairing dialog, with the connection-vs-pairing port difference explained), a direct <code>ip:port</code> connect for already-paired devices, and a one-click USB→Wi-Fi switch. Address fields take the exact string the phone shows — paste and go — and a successful connection selects the new device automatically." },
  { version: "v3.1.0", date: "Jul 2026", html: "<b>Custom commands, reworked</b> — one box for full command lines exactly as you'd type them in a terminal (multi-line supported), <kbd>adb</kbd> lines detected automatically, and each command can open Droidective's Terminal or your Mac's default terminal. The <b>Quick Actions panel is now yours to curate</b>: pin custom commands with <kbd>⌘P</kbd>, hide actions you don't use, and a <code>{bundleId}</code> command with no app selected asks you to pick one instead of erroring. Updates check twice a day and a dismissed update returns as a notification until installed. Apps gain a one-click <b>Restart</b> everywhere they're managed, launching works on devices with a broken <code>monkey</code>, the app no longer installs tools via Homebrew (it links to the official sources), and the welcome tour ends by pressing your new Quick Actions hotkey — confetti included." },
  { version: "v3.0.1", date: "Jul 2026", html: "<b>Bug-fix release</b> — Uninstall and Monkey Test now confirm before running, Logcat streams as soon as a device authorizes, and the APK tools (Studio, Inspector, Sign, Decompile) and Reactotron open without an Android device selected. Frida and Change Locale give honest status messages, Screen Record and Performance recordings survive a mid-capture disconnect, and anonymous analytics no longer include the device model or OS version. Bundled developer tools now install pinned, known-good versions." },
  { version: "v3.0.0", date: "Jul 2026", html: "<b>Terminal split panes</b> — <kbd>⌘D</kbd> splits the shell side by side, <kbd>⇧⌘D</kbd> stacks it, and new tabs and panes open in the focused shell's working directory — no shell config needed — with the tab list dockable as a left rail or a Chrome-style top strip. The <b>onboarding tour is rebuilt</b> around recordings of the real app, the <b>React Native and Connection hubs are redesigned</b> (described action cards, a Metro port field, your device's live Wi-Fi network and IP), <b>custom commands run in your login shell</b> — aliases work, optionally in a Terminal tab — and the JS Console gains <b>Reload JS and Restart app</b>." },
  { version: "v2.9.3", date: "Jul 2026", html: "<b>Log feeds rebuilt</b> — Logcat, the JS Console, and the Reactotron timeline share one scroll behavior: jump-to-top/bottom buttons, interruption-free reading while logs stream, and no more CPU spikes under event storms. The <b>JS console</b> stops looping “connecting…” on large payloads, both consoles shut down with their tab or window, and <b>Reactotron</b> adds HTTP method/status filters, shows the connected app's name, and explains client disconnects right in the timeline." },
  { version: "v2.9.2", date: "Jul 2026", html: "<b>Mirror in its own window</b> — pop the live mirror out beside your workspace from a button on its control bar; it follows the device-bar selection, which now <b>switches sessions reliably</b>, with a Reconnect button when a stream dies. The <b>video editor</b> gets full-width native controls and trim strip (no more cramped portrait layout), every Reveal button becomes <b>Open in Finder</b>, and the first quick save asks once where captures should go." },
  { version: "v2.9.1", date: "Jul 2026", html: "<b>Home search &amp; a Frequently used strip</b> — find any tool from the Home screen and jump to your most-used ones — plus <b>font and accent-color customization</b> in Settings ▸ Appearance. Fixes: the React Native dev-server host now writes <code>debug_http_host</code> so it works on physical devices, text fields release focus when you click away, <kbd>⌘,</kbd> no longer opens Settings behind the Quick Actions panel, and drop-to-split works again in the Terminal. The command palette moves to <kbd>⌘T</kbd>." },
  { version: "v2.9.0", date: "Jul 2026", html: "<b>Background mode &amp; a global Quick Actions panel</b> — closing the window keeps Droidective running in the menu bar, and a non-activating Raycast-style panel on a global hotkey runs any adb action, manages apps, boots emulators, and installs APKs without the main window — with per-device targeting and Finder APK routing. Plus a <b>terminal tab rail</b> with a find bar and a <b>Dock-style auto-hiding sidebar</b>." },
  { version: "v2.8.3", date: "Jul 2026", html: "<b>iOS Simulator support</b> — booted iOS Simulators sit in the same device bar as Android devices, and features adapt to the selection: screenshot, dark mode, demo mode, fake battery, and deep links run through <code>xcrun simctl</code>, with push notifications as a Simulator-only tool and a new iOS Developer role. Plus a <b>redesigned role picker</b>, <b>per-feature product analytics</b> (anonymous, opt-out), and Reactotron/log readability fixes." },
  { version: "v2.8.2", date: "Jul 2026", html: "<b>JS Console reconnect fix</b> — a race killed each fresh Metro connection and leaked the old socket, so the console reconnected in a loop and spammed the dev server; connections are now generation-guarded with a bounded handshake, so it connects once and stays connected. Plus <b>anonymous performance self-monitoring</b> — sustained high CPU or memory in the app is reported with the features open at the time (opt-out in Settings → Privacy)." },
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
  { label: "Blog", href: "/blog/" },
  { label: "Changelog", href: "/changelog/" },
  { label: "Issues", href: `${GITHUB_URL}/issues` },
  { label: "License", href: `${GITHUB_URL}/blob/main/LICENSE` },
  { label: "Privacy", href: "/privacy.html" },
  { label: "For Android developers", href: "/for-android-developers.html" },
  { label: "For iOS developers", href: "/for-ios-developers.html" },
  { label: "For QA & testers", href: "/for-qa-and-testers.html" },
  { label: "For support teams", href: "/for-support-teams.html" },
  { label: "For security testers", href: "/for-security-testers.html" },
  { label: "React Native debugger", href: "/react-native-debugger.html" },
  { label: "scrcpy GUI for Mac", href: "/scrcpy-gui-mac.html" },
]
