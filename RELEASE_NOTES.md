## Droidective v3.0.0

Terminal split panes with working-directory inheritance, an onboarding tour
built from recordings of the real app, redesigned React Native and Connection
hubs, custom commands through your login shell, and JS Console reload/restart.

### New features

- **Terminal split panes** — ⌘D splits the focused shell side by side, ⇧⌘D
  stacks it (File menu, tab context menus, or the terminal's right-click menu).
  Splits nest, ⌘W closes the pane first and then the tab, `exit` folds a pane
  back into its siblings, and the surviving shell takes keyboard focus.
- **New shells open where you are** — new tabs and split panes start in the
  focused shell's live working directory, read from the kernel, so no OSC 7 or
  shell configuration is needed.
- **Terminal tabs on top** — a toggle switches the tab list between the left
  rail and a Chrome-style strip along the top, keeping groups, context menus,
  and drag-reorder in both layouts.
- **Custom commands run in your login shell** — shell commands source your
  interactive rc, so `.zshrc`/`.bashrc` aliases and PATH additions resolve.
  Each command also chooses where it runs: silently with a toast, or typed
  into a fresh in-app Terminal tab with live output.
- **JS Console: Reload JS and Restart app** — reload the running bundle over
  CDP (with a dev-menu fallback) or force-stop and relaunch the target app,
  with a searchable app picker when detection can't find it.
- **React Native hub redesign** — quick actions are cards with visible
  descriptions, and Metro forwarding gets its own section with a port field
  (prefilled 8081) beside USB / Wi-Fi dev-server rows. The device bar shows
  the bundle pill on the hub, so Deep Links and Process Death target a
  visible, changeable bundle.
- **Connection hub shows your device's network** — "This device" replaces the
  blind copy button with the live Wi-Fi network name and IP, a Copy IP
  button, and a refresh accessory.
- **Pinned section on Home** — the launchpad follows the sidebar's order and
  mirrors its pinned features; Home itself becomes a permanent house icon
  leading the tab strip instead of a closable tab.

### Improvements

- **The onboarding tour is rebuilt** around five pages, each led by a looping
  screen recording of the real app — sidebar, tabs and drag-to-split, roles,
  settings and hotkeys, and the Quick Actions panel summoned over a browser.
  Skip from any page jumps to the hotkey ask, and Reduce Motion holds a still
  frame. Reactotron gets a one-time intro demo on first open.
- **Reactotron timeline** — filters move into a Timeline Filter dialog
  matching the Reactotron app's (grouped checkboxes with method/status
  refinements), rows preview object payloads inline with a hover copy button,
  the log text is selectable, and Restart app auto-detects the running app.
  In single-pane mode the timeline sits under two bars instead of three.
- **Steady with huge console payloads** — a multi-megabyte `console.log` no
  longer stalls the JS Console: rows render bounded previews and the buffer
  gets a byte budget on top of its entry cap.
- **Idle toolbars stay out of the way** — Logcat's filter toolbar hides until
  a device connects, and the JS Console's until it's connected or holds
  output.
- **Device-bar pills size to their content** — short labels hug, long device
  names and package ids truncate, and the bar compresses cleanly in narrow
  windows.
- The main window keeps at least 85% of the screen's visible frame, and the
  role picker can be closed with Esc when reopened from Home instead of
  resetting your tabs.

### Fixes

- **Nothing clips at the minimum window width** — on tabs showing the bundle
  pill, the device bar could push the layout past the window, cutting off
  sidebar icons on the left and bar controls on the right.
- **Dropping a tab no longer leaves a stale highlight** — the ending drag
  session could re-light a pane's drop highlight or a reorder guideline right
  after the drop. Tab drags also read better now: the dragged chip fades in
  place while its ghost rides the cursor, and reordered chips slide instead
  of snapping.

Installed copies update in place via Sparkle.

## Droidective v2.9.3

The streaming log feeds — Logcat, JS Console, and the Reactotron timeline —
rebuilt around one scroll behavior, plus JS-console connection fixes and
Reactotron network filters.

### New features

- **Jump to top / bottom in every log feed** — floating buttons overlay Logcat,
  the JS Console, and the Reactotron timeline; each hides while you're at its
  edge, and both hide when there's nothing to scroll. Jumping to the newest
  edge resumes live following.
- **Reactotron network filters** — pick the Network view in a timeline pane and
  filter by HTTP method (the ones your app actually sent) and status class
  (2xx–5xx, plus Failed for requests that never got a response) — per pane, so
  a split view can watch two slices.
- **Reactotron explains disconnects** — when a client drops, an expandable
  DISCONNECTED row lands in the timeline where streaming stopped, naming the
  app and the reason — including the Android case where the app queues events
  faster than the connection drains and its WebSocket hangs up at a 16 MB
  backlog.

### Improvements

- **Interruption-free reading while streaming** — scroll away from the newest
  line and new logs keep rendering without dragging your view; return to the
  edge (or tap the jump button) and following resumes. The reverse-order
  toggles are gone: JS Console and Logcat tail at the bottom, Reactotron keeps
  newest at top.
- **Steady under event storms** — the feeds no longer re-render per scrolled
  pixel or per streamed event, which could peg the CPU and hang the app under
  a fast Reactotron stream.
- The connected app's name shows next to Reactotron's status dot.

### Fixes

- **JS console no longer loops "connecting…"** — apps logging large objects
  tripped a 1 MiB socket cap on the post-connect replay (close code 1009), and
  every reconnect replayed the same burst. The cap is now 64 MiB.
- **Consoles stop with their UI** — closing the JS console or Reactotron tab,
  or the main window (in either background-mode setting), tears the connection
  down instead of leaving it reconnecting in the background; reopening the
  window resumes the JS console's discovery.

Installed copies update in place via Sparkle.

## Droidective v2.9.2

Screen-mirror quality of life — a pop-out mirror window and reliable device
switching — plus video-editor and save-flow fixes.

### New features

- **Mirror in its own window** — a window button on the mirror's control bar
  moves the live mirror into a dedicated "Screen Mirror" window (also in the
  macOS Window menu), so it can sit beside the main workspace or other apps.
  The window follows the device-bar selection, and an in-window recording still
  guards quit and device switches.

### Improvements

- **The mirror follows device switches reliably** — reconnects are serialized,
  so switching devices quickly can't tangle two sessions or leave one streaming
  in the background, and the stopped/failed screens gain a **Reconnect** button.
- **"Open in Finder" everywhere** — every "Reveal" button now says Open in
  Finder, and the first quick save asks once where captures should go
  (changeable anytime in Settings ▸ Privacy).
- Toasts dismiss from a macOS-notification-style close button on the top-left
  corner.
- Anonymous hang reports carry more triage context (opt-out in
  Settings ▸ Privacy).

### Fixes

- **Video editor controls no longer collapse on portrait clips** — the player
  takes the full pane (the video letterboxes inside), so the native playback
  controls and the trim strip get the full width. Trimming long recordings is
  workable again, and cancelling a trim no longer leaves an empty controls pill
  floating over the video.

Installed copies update in place via Sparkle.

## Droidective v2.9.1

Adds Home feature search and a Frequently-used strip, font and accent-color
customization, and a round of fixes.

### New features

- **Home feature search & Frequently-used strip** — an inline search under the
  Home header finds any tool (⏎ opens the top match, Esc clears), and a
  Frequently-used strip surfaces the features you open most, ordered by use
  count.
- **Font customization** — Settings ▸ Appearance gains a font-family picker over
  the installed macOS families and a text-size scale; every UI font follows the
  choice (the terminal and screenshot-annotation canvas keep their own).
- **Accent-color customization** — pick from preset swatches, the color well, or
  a hex field (`#RRGGBB` / `#RGB`), and the accent now reaches the surfaces that
  used to ignore it (device/bundle pills, list selection in Apps and the
  decompile tree, success toasts).

### Improvements

- The command palette shortcut moves to **⌘T** everywhere.
- The **⌘T palette** now runs instant actions in place (e.g. Copy Device IP
  copies and shows a toast) instead of opening a detail tab.
- **Reactotron** gains **Copy as JSON** on the state tree, subscriptions, and
  snapshots.

### Fixes

- **Set Dev Server Host** now works on physical devices: it writes React
  Native's `debug_http_host` preference via `run-as` and relaunches the app,
  falling back to `setprop metro.host` and the dev menu.
- **Text fields release focus when you click away** — clicking outside a field
  no longer leaves it holding the keyboard.
- **⌘,** no longer opens Settings hidden behind the Quick Actions panel.
- **Drop-to-split works again in the Terminal** — a leftover whole-view drop
  target had blocked dropping a tab into a pane.

Installed copies update in place via Sparkle.

### New features

- **Background mode & the Quick Actions panel** — with "Keep running in the
  background" on (Settings ▸ General, the default), closing the main window
  hides Droidective from the Dock and stops its kept-alive sessions (terminal
  shells, Reactotron, the JS-console tunnels) while the menu bar icon, global
  hotkeys, and a new Quick Actions panel stay available; ⌘Q still quits fully,
  and relaunching from Finder reopens the window. The **Quick Actions panel** is
  a non-activating floating mini app on a global hotkey (record one in
  Settings ▸ Hotkeys): a grid of everything runnable in place — saved custom
  commands, every enabled instant, toggle, and form action, plus Manage Apps,
  Emulators, and Install APK — with an "Open in Droidective" list for the
  full-app screens. Form actions run in the panel, destructive app verbs take a
  confirming second press, and with several devices connected each action asks
  which to target (⌘⏎ runs on all). Double-clicking an APK in Finder opens it
  here to install in place or hand to APK Studio. The panel mirrors the app's
  role and catalog curation and resumes where you left off when reopened within
  a configurable window.
- **Terminal tab rail & find bar** — terminal shells group into a collapsible
  rail with drag reordering, and a find bar (⌘F, then ⌘G / ⇧⌘G) searches the
  focused shell. Drag-selection autoscrolls, with a right-click context menu.
- **Auto-hiding sidebar** — a Dock-style mode (Settings ▸ Appearance) where the
  sidebar slides over the content when you push the pointer to the window's
  left edge, freeing horizontal space; ⌘B still shows and hides it.

### Improvements

- **Screen Recorder live preview** — the recorder shows a live preview of the
  device while it captures.
- **Selectable logcat** — logcat is backed by a text view, so lines can be
  selected across line breaks and copied.

### Fixes

- Screen Recorder pause and resume controls no longer wedge mid-recording.
- CPU-overuse diagnostics are waived while screen mirroring — which is expected
  to be CPU-heavy — so it no longer files false performance incidents.

Installed copies update in place via Sparkle.

## Droidective v2.8.3

Adds iOS Simulator support, per-feature product analytics, and a redesigned
role picker, and ships a rebuilt marketing site.

### New features

- **iOS Simulators in the device bar** — booted iOS Simulators now sit alongside
  Android devices, and features adapt to the selected platform. Screenshot, dark
  mode, demo mode, fake battery, and deep links run against a simulator through
  `xcrun simctl`; push notifications are a new Simulator-only tool. The
  Emulators & Simulators screen lists and boots or shuts down simulators, and a
  new iOS Developer role leads with them. A feature that only applies to Android
  shows a platform-mismatch state with a one-click switch to a connected device.
  The registry grows from 55 to 56 tools.

### Improvements

- **Role picker redesign** — each role card carries a tool-count pill and
  feature-preview chips, with hover, press, and keyboard-focus states, a
  staggered entrance, and Reduce Motion respected.
- **Product analytics** — anonymous usage is now attributed per feature (which
  tool was open when an event, hang, or crash occurred), with install-level
  retention and the target-device landscape. It stays on by default with opt-out
  in Settings → Privacy; no serials, paths, package ids, SSIDs, or command text
  are ever sent, and the first-run consent prompt has been removed.
- **Reactotron & logs** — Reactotron subscriptions and snapshots render as
  readable trees, expanded console objects are bounded and searchable in place,
  and log auto-follow is steadier while scrolling.

### Fixes

- Security hardening from an audit pass — device-shell values are consistently
  shell-quoted — plus a JS Console crash fix and React Native console UX
  follow-ups.

Installed copies update in place via Sparkle.

## Droidective v2.8.2

A patch release that fixes the JS Console's reconnect behavior against Metro
and adds anonymous app performance monitoring.

### Fixes

- **JS Console reconnect storm** — a race in the CDP client killed each new
  connection moments after it opened and left the old socket running, so the
  console reconnected every couple of seconds, Metro logged a stream of
  connection-established messages, and leaked debugger connections piled up
  until a JS reload cleared them. Connections are now generation-guarded, every
  close path shuts its socket, and the handshake times out instead of hanging
  on a dead target — the console connects once and stays connected.
- Changing the Metro port can no longer commit a connection that was still in
  flight against the old port.

### Improvements

- **Performance self-monitoring** — the app now watches its own CPU and memory
  use and, when something stays over the limit, reports it to the anonymous
  diagnostics along with which features were open — so resource hogs get found
  and fixed. Sends only feature names and resource numbers; opt-out any time in
  Settings → Privacy.

Installed copies update in place via Sparkle.

## Droidective v2.8.1

A release that adds a built-in Terminal and shell-kind custom commands, a
Security / Pentest role with reworked per-role sidebars, and a round of
performance and stability fixes.

### New features

- **Terminal** — real multi-tab login shells (PTY-backed via SwiftTerm) inside
  the app. The device selected when a shell opens is exported as
  `ANDROID_SERIAL`, so plain adb commands target it without `-s`. Tabs are
  renameable (double-click, right-click, or ⇧⌘R), ⌘N opens a shell from
  anywhere, ⌘W peels one at a time, ⇧⌘[ / ⇧⌘] cycle, and typing `exit` closes
  the tab. Sessions and scrollback survive switching features, and closing the
  feature tab — or quitting — with live shells asks first.
- **Shell custom commands** — a custom command now runs either as adb
  (tokenized arguments, never a shell) or as a Terminal command line through
  `zsh -lc`, so plain command lines and script files behave like in Terminal.
  `{bundleId}` and `{serial}` substitute in both, a file picker inserts a
  script path, and shell runs are recorded on the command log.
- **Security / Pentest role** — a new role with a curated sidebar; the
  per-role feature lists were reworked and sidebar groups follow the role's
  order.

### Improvements

- **Sidebar** — ⌘1–⌘0 jump to the first ten rows (with hints and a Go menu),
  and pinning is discoverable: a hover pin on every row and a pinned marker.
- **Device Info** — identity header, live memory/storage/battery/app gauges,
  curated property groups, and a searchable getprop dump.
- **Device bar** — a single row with the bundle picker next to the device pill.
- The 10-tab workspace cap is gone, and the bottom Recent/Commands bar was
  removed — the how-it-works note toggles from Settings ▸ Appearance and the
  Command Log lives in Settings.
- **Performance** — the launch hang from decoding the dock icon on the main
  thread is fixed, the Reactotron timeline is capped by bytes (big payloads
  released off the main thread), JS console search filters incrementally, and
  the decompile cache is deleted off the quit path.
- Log views share a smart-tailing scroller that follows the bottom until you
  scroll up.

### Fixes

- **Reactotron** — a failed server start (e.g. the port is taken) shows an
  error state with Retry and can actually restart; previously the dead server
  handle stuck.
- **React Native** — Process Death backgrounds the app, kills it, and verifies
  with pidof (with a foreground-app fallback); the dev-server host runner
  reverse-tunnels localhost, sets `metro.host` where the device allows it, and
  rejects `http://` / IPv6 input instead of misreporting success.
- **Tab strip** — the ‹ › arrows derive the first visible tab from measured
  geometry, so the first click after a trackpad scroll works.
- **Frida** — architecture detection works on single-ABI devices.
- **APK Studio** — the decompile source viewer no longer renders blank when an
  editor push is dropped.
- Role changes stop every open tab's background work (also fixing a Reactotron
  server leak), and a closed shell can't be respawned by a SwiftUI teardown
  pass.

Installed copies update in place via Sparkle.

## Droidective v2.8.0

A feature release that adds a tabbed workspace with split panes and a React
Native JS Console, curates the "Run on all devices" toggle, and fixes a round of
light-mode and layout issues.

### New features

- **Tabbed workspace with split panes** — open features in tabs (up to ten)
  instead of one detail pane at a time. Tabs stay mounted while hidden, so a
  screen recording or a live view keeps running in the background. Split the
  window into two panes and drag tabs between them, reorder tabs by dragging, and
  navigate with ⌘T, ⌘W, ⌃Tab, and ⌃1–9. The open tabs and the split layout are
  restored on the next launch.
- **React Native JS Console** — a console over the Hermes runtime via the Chrome
  DevTools Protocol: it connects to a Metro target, streams `console.*` output
  with syntax-highlighted objects, and evaluates expressions against the running
  app.

### Improvements

- **Curated "Run on all devices"** — the toggle now appears only for the features
  where running on every device makes sense (send text, React Native, Simulate,
  install app) and is hidden elsewhere.
- **Live mirror follows the active device** — switching the device while
  mirroring re-targets the mirror instead of staying on the previous one.
- **Command palette opens centered**, the **sidebar search shows all matches** and
  locks the group/reorder controls while a query is active, and the **close button
  on toasts and the notification panel** is a single restyled control.

### Fixes

- **Light-mode colors** — named colors resolve per color scheme, and foreground
  text now picks black or white by the background's luminance, so labels no longer
  render white-on-white on light or bright-accent backgrounds (device pill,
  palette rows, copy buttons, toggle styles).
- **Simulate** shows an empty state when no device is connected; **Home** feature
  cards keep their height with short text; **System Restrictions** cards are
  visible in light mode and no longer reload the whole list on each toggle.
- Fully tappable rows for **Settings** disclosures and **Screen Record** advanced
  options; **form action pickers** fill the available width; the **notification
  panel** slide no longer janks the layout.

Installed copies update in place via Sparkle.

## Droidective v2.7.1

A bug-fix release: screen mirroring no longer stops when a device can't capture
audio.

### Fixes

- **Screen mirror on emulators** — scrcpy aborts the whole session (video
  included) when its audio encoder can't start, which happens on most emulators,
  where the device can't create an `AudioRecord`. The in-app mirror requested
  audio unconditionally, so it stopped right after connecting. It now detects an
  audio-only failure — the session ending before the first video frame — and
  reconnects once, video-only, so mirroring keeps working.

Installed copies update in place via Sparkle.

## Droidective v2.7.0

A feature release that adds a full APK toolchain and Frida setup, a custom accent
color, and emulator launching from the device bar, plus a round of UI and
hotkey-recording improvements.

### New features

- **APK Studio** — one workspace over a loaded APK: **Inspect** (manifest,
  permissions, SDK, signing certificates), **Decompile** (`jadx` for readable
  Java or `apktool` for smali + resources, with an in-app source viewer, code
  search that jumps to the matched line, and "open in jadx-GUI" / reveal for
  external editing), **Recompile** an edited `apktool` tree, and **Sign** with the
  debug key, your keystore, or a brand-new keystore created right there. jadx,
  apktool, and a Java runtime are downloaded from their GitHub releases on first
  use and managed in Settings ▸ Tools.
- **Frida setup** — matches the device architecture and downloads the right
  `frida-server` / `frida-gadget`; on a rooted device it pushes and starts
  frida-server so you can attach with your own frida CLI.
- **Custom accent color** — pick your own accent in Settings ▸ Appearance; it
  recolors buttons, toggles, selection, and active icons across the app.
- **Launch emulators from the device bar** — start an Android Studio AVD, or open
  the Emulators screen, straight from the device menu.

### Improvements

- **Settings** is reorganized into **Appearance** and **Privacy** tabs, in a
  roomier window.
- **Connect-a-device prompts** — features that need a device (Send Text, the
  quick actions, Frida, Private DNS…) now show a tailored "connect a device"
  message instead of silently disabled controls.
- **Hotkey recording** — the sidebar's Set-Hotkey popover starts recording the
  moment it opens, and both it and the Hotkeys settings show the modifiers live
  as you hold them.
- **Tools settings** show each downloaded tool's on-disk size, with reveal and
  delete; the decompiled-source cache is reused while the app is open and cleared
  on quit.

Installed copies update in place via Sparkle.

## Droidective v2.6.2

A bug-fix release with security, correctness, and stability hardening, plus a
safer navigation flow and a clearer APK install.

### New features

- **APK pre-install preview** — opening an `.apk` from Finder (double-click, Open
  With, or drag onto the icon) now stages it in the Install App screen with a card
  showing the app name, package, version, target SDK, and size (read via the SDK's
  `aapt2`), so you can see what you're about to install before clicking Install.
  Falls back to the file name and size when build-tools aren't installed.

### Improvements

- **Leave confirmation** — switching feature or device, or quitting, while an
  active screen/mirror recording, performance/network capture, or unsaved
  screenshot/video edit is in flight now asks before discarding it. Recordings
  offer Stop & Save; editors offer Keep or Discard. Background file pulls and
  installs continue uninterrupted.

### Bug fixes

- **Video editor** — an applied crop no longer clips away the video and its
  playback controls; the crop region is shown as an overlay and still applied on
  export.
- **Screen mirroring** — the video, audio, and control decoders cap how much they
  buffer, so a corrupt or desynced stream can no longer grow memory toward a crash.
- **Network speed** — a `/proc/net/dev` counter that resets on reboot no longer
  reports a one-off throughput spike.
- **Reactotron** — "Take snapshot" times out and reports it instead of waiting
  forever when no store plugin is connected; the built-in server now listens on
  loopback only (off the local network); state-tree nodes whose key contains a
  slash no longer collide; and clearing one connection no longer affects another.
- **Device info** — storage reads correctly on devices with dynamic partitions,
  and the battery level ignores an unrelated "Max charging level" line.
- **File Explorer** — an operation that prints a warning but still succeeds is no
  longer reported as a failure.

### Security

- Proxy and locale values passed to the device shell are quoted, and a cancelled
  action now terminates its underlying `adb` process instead of leaving it running.

Installed copies update in place via Sparkle.

## Droidective v2.6.1

A bug-fix release that polishes the v2.6.0 features — Reactotron, the crash
catcher, app install, notifications, and mirroring — and adds a preset library
to custom commands.

### New features

- **Custom command presets** — start from a curated library of common adb
  commands (force-stop, clear data, launch, list packages, key events, toggle
  animations, battery, clear logcat, reboot, and more) instead of a blank
  editor; add one and run or edit it.

### Improvements

- **Reactotron** — copy-as-cURL no longer turns a GET request into a POST (the
  method is stated explicitly when a body is attached, and empty bodies aren't
  sent); export now writes only the items currently shown in a pane after its
  search and category filters, with the export action moved into each pane; the
  connection stays alive when you switch features, with no "Keep Reactotron
  running?" prompt; and the timeline search reads as search, with a magnifying
  glass and clear button matching the other searches.
- **adb install failures** show a plain-English reason (e.g. "Not enough storage
  on the device.") instead of a raw error code; the full adb output stays on the
  Copy button in the toast and the notifications panel.
- **Notifications** — the flowing toast now has a dismiss (×) button, and the
  panel's bulk action reads "Clear all" and appears only when there's more than
  one notification.
- **Mirroring survives device rotation** — the view refreshes its dimensions and
  re-primes the renderer on the new orientation, so taps stay accurate after a
  rotate.
- **Welcome screen** no longer collapses one letter per line in a narrow detail
  pane; the header is responsive and the window's minimum width grows with the
  side panels.

### Bug fixes

- **Crash Catcher** bounds the fetched crash (caps the logcat dump and keeps the
  diagnostic head plus the most recent lines) so a large log can't freeze the UI
  while rendering.
- The **mirror audio engine** is built off the main thread, fixing an app hang
  on first use.

Installed copies update in place via Sparkle.

## Droidective v2.6.0

### New features

- **Reactotron** — a built-in Reactotron debugger for React Native apps, with no
  desktop app required: Droidective runs the Reactotron server itself on :9090
  and auto-reverses the port. A live timeline of logs, API calls (with cURL
  export), state changes, and images; a store browser with live subscriptions,
  action dispatch, and snapshots; custom commands; and a REPL. Switches between
  multiple connected apps, and can keep the connection alive as you move around
  the app.
- **Install App** — install an APK onto your device(s) by dragging it onto the
  new Install App screen or picking a file (reinstalls keep app data, and it
  installs on every selected device). Double-clicking an `.apk` in Finder opens
  Droidective and asks which device to install onto.

### Improvements

- **Dark by default** — new installs start in dark mode. Light mode is now marked
  **Beta** in Settings → Appearance while a few screens are tuned for it; Auto and
  your own choice still work as before.
- **Emulators in the dev roles** — the Android and React Native roles now include
  the Emulators feature, and existing users on those roles pick it up
  automatically (no need to re-pick your role).

Installed copies update in place via Sparkle.

## Droidective v2.5.0

A big UX release: pick your role on first launch and get a focused Home, a faster
command palette, a sidebar you can rearrange, and refreshed screens throughout.

### New features

- **Role-based start** — on first launch, pick a role (Android, React Native, QA,
  Support, or "everything") and Droidective curates a focused feature set and a
  Home launchpad of your most-used tools, ordered by real usage. Change your role
  anytime in Settings; nothing is ever removed.
- **Bug Report screen** — capturing a bug report now has its own screen instead
  of firing blind.
- **Forward Metro (React Native)** — one click runs `adb reverse tcp:8081` so the
  device reaches Metro on your Mac.

### Improvements

- **Command palette (⌘K)** — rebuilt as a tight, centered Spotlight-style panel.
  Pin features with `⌘P` (pinned items lead the sidebar and palette), enable or
  disable with `⌘E`, and search now matches every word you type — so "copy ip"
  finds "Copy Device IP". Keyboard hints throughout.
- **Reorder the sidebar** — a reorder button drops the sidebar into an edit mode
  (rows jiggle) where you drag to rearrange. Grouped and ungrouped layouts keep
  independent orders, and pinning moved to right-click so rows stay clean.
- **Grouping toggle** — group-by-category is now a button next to the search
  field instead of a Settings option.
- **Refreshed screens** — Connection, Device Info, Simulate, React Native, Deep
  Links, App Info, System Restrictions, and the Apps detail pane share one card
  layout.
- **Emulators** — click a running emulator to bring its window to the front, and
  a freshly launched emulator comes forward on its own.
- **Screenshot editor** — press Delete to remove the selected annotation.
- **Theme** — a neutral charcoal dark palette (no blue cast) and brand-green
  feature icons throughout.
- **Update notes** — the in-app updater shows release notes in its own window
  instead of opening the web page.
- **First-run privacy screen** — appears after a few launches instead of the
  first. Anonymous crash reports and usage analytics stay opt-out in
  Settings → Privacy.
- **Star prompt** — a one-time nudge to star the project on GitHub.

Installed copies update in place via Sparkle.

## Droidective v2.4.1

### Improvements

- **Sidebar footer** — the "Manage features" button stays on one line, and the
  sidebar has a higher minimum width so the footer no longer wraps when narrowed.

Installed copies update in place via Sparkle.

## Droidective v2.4.0

A live in-app screen mirror, a video editor, and self-contained tools — scrcpy
and ffmpeg now ship inside the app, so there's nothing to `brew install`. The
build is also signed with a Developer ID and notarized by Apple.

### New features

- **In-app screen mirror** — mirror and control the device live in the app
  window, built on a native scrcpy engine (no `scrcpy` install). Take a
  screenshot, record the screen, hear device audio, sync the clipboard both
  ways, adjust volume, and drive Back / Home / Recents.
- **Video Editor** — trim, rotate, flip, crop, change speed, mute, convert the
  format (MP4 / MOV / MKV / WebM / GIF), and compress — with undo/redo
  (`⌘Z` / `⇧⌘Z`). A finished recording opens straight in the editor, and you can
  open any existing video to edit.
- **Self-contained tools** — scrcpy-server and a static ffmpeg are bundled in the
  app, so mirroring, recording, and video export work with no `brew install`.

### Improvements

- **Screen recording** runs through the mirror — no ~3-minute cap, device audio,
  and it survives rotation — with pause/resume and a discard / save / edit prompt
  when you stop.
- **Live edit preview** — rotate, flip, crop, speed, and mute reflect in the
  preview as you change them. Crop is a focused mode with the player controls
  hidden and Apply / Cancel / Reset (Esc) actions.
- **Privacy consent redesigned** — the first-launch telemetry screen is clearer,
  with iconned rows, a recommendation, and both anonymous crash reports and usage
  analytics on by default (still nothing is sent until you continue, and it's
  changeable anytime in Settings → Privacy).

### Install

Download the `.dmg` below and drag **Droidective** into **Applications**. This
build is signed with a Developer ID and notarized by Apple, so it opens without
any quarantine workaround.

Installed copies from v2.1.0+ update in place via Sparkle.

## Droidective v2.3.0

A big screenshot-editor update — annotations you can move, resize, and rotate
after drawing, blur and opacity controls, editable text, and a rotatable crop —
plus a handful of fixes.

### New features

- **Editable annotations** — select any markup (shapes, arrows, pen, text,
  redactions) to move, resize, or delete it; a freshly drawn one is selected
  automatically so you can adjust it right away.
- **Rotate** — rotate any annotation, the crop box, or the whole screenshot
  (90°) with a drag handle.
- **Redaction controls** — adjustable blur strength for blur redactions, and
  fill opacity for solid ones.
- **Editable text** — re-open a text label to change it, and drag a handle to
  resize it.
- **Rotatable crop** — tilt the crop box to straighten as you crop.

### Fixes

- Text fields now show the brand-green focus ring on every Mac (it followed the
  macOS system accent before) and dim when the window is inactive.
- Blur redaction no longer leaks the original image at its edges.
- ⌘= / ⌘- zoom no longer discards in-progress work, such as a captured
  screenshot.
- **Apps** — uninstalling a user app no longer reports a false "protected"
  error, and the detail pane clears once the app is removed.
- Demo Mode is a sidebar toggle instead of a separate screen.
- Renamed **Current Activity** to **Copy Current Activity**.

### Install

Download the `.dmg` below and drag **Droidective** into **Applications**. The
build is ad-hoc signed but not notarized, so clear the quarantine once:

```sh
xattr -dr com.apple.quarantine "/Applications/Droidective.app"
```

Installed copies from v2.1.0+ update in place via Sparkle.

## Droidective v2.2.1

A fix for the accent color on Macs set to a specific system accent.

### Fixes

- Buttons, toggles, sliders, and other standard controls now always use the
  brand green. They previously followed the macOS system accent color, so on a
  Mac set to a specific accent (for example Blue) they rendered in that color
  instead of green.

### Install

Download the `.dmg` below and drag **Droidective** into **Applications**. The
build is ad-hoc signed but not notarized, so clear the quarantine once:

```sh
xattr -dr com.apple.quarantine "/Applications/Droidective.app"
```

Installed copies from v2.1.0+ update in place via Sparkle.

## Droidective v2.2.0

A UI overhaul: a refreshed theme, feature hubs that keep the sidebar short, a
screenshot annotation editor, and every feature on by default.

### New features

- **Screenshot editor** — a capture now opens in an editor with pen, highlighter,
  shapes (rectangle, ellipse, arrow, line), text, and redaction (blur or solid),
  plus zoom, crop, and undo/redo (`⌘Z` / `⇧⌘Z`). Save or copy when you're ready;
  nothing is written to disk until then. Captures from the sidebar, a global
  hotkey, or the menu bar still save straight to the capture folder.
- **Feature hubs** — React Native, Simulate, and Connection each gather their
  related actions onto one screen, and the Apps explorer now also handles per-app
  management (open, force-stop, clear cache/data, disable, uninstall) alongside
  info and permissions. Gathered tools stay searchable and hotkey-able.
- **Live memory graph** — Memory Usage charts Total PSS over time on an axis that
  scales to the live range.
- **Notifications panel** — a side panel keeps the toasts that matter (errors,
  warnings, and results that produced a file).

### Improvements

- **Theme** — a new dark/light terminal palette and logo, and detail panes that
  center their content instead of stretching edge to edge.
- **Sidebar** — features group by category with drag-to-reorder (within a group
  or whole groups), tighter rows, and a centered drop guideline. Instant actions
  fire straight from the sidebar without opening a screen.
- **Every feature on by default** — the catalog ("Manage features") is now for
  hiding the ones you don't want; Restore Defaults is gone.

### Install

Download the `.dmg` below and drag **Droidective** into **Applications**. The
build is ad-hoc signed but not notarized, so clear the quarantine once:

```sh
xattr -dr com.apple.quarantine "/Applications/Droidective.app"
```

Installed copies from v2.1.0+ update in place via Sparkle.

## Droidective v2.1.0

Device control, in-app feedback, and automatic updates.

### New features

- **Device control suite** — **Wi-Fi** (connection details, radio toggle, saved
  networks, and saved passwords on rooted devices), **Private DNS** (off /
  automatic / DNS-over-TLS provider), **Root Status** (multi-signal root
  detection), and **System Restrictions** (dev toggles for the package verifier,
  hidden-API access, and stay-awake, plus SELinux and read-write remount on root).
- **About & Feedback** — report a bug or request a feature through pre-filled
  GitHub issues (app/OS/device diagnostics attached), star the project, and find
  author info, from a new sidebar panel.
- **Automatic updates** — Droidective now updates itself with signed updates via
  Sparkle; also available from the app menu.

### Privacy

- Anonymous crash reporting (on by default, opt-out) and opt-in usage analytics,
  with a first-launch disclosure and controls in Settings → Privacy. No device
  serials, file paths, or command contents are ever sent.

## Droidective v2.0.0

A round of new tools and workflow upgrades on top of v1. Now 39 features; ADBKit
has 146 unit tests.

### New features

- **Performance Monitor** — per-core CPU, system + per-process RAM, app FPS/jank,
  and network throughput, charted live with dynamic axes and a hover crosshair.
  Record a session and export it to JSON + CSV.
- **Network Speed** — a dedicated download/upload monitor (device-wide and
  per-interface) with session totals, recording, and export.
- **Home screen + welcome tour** — a getting-started landing page and a
  first-launch walkthrough (replayable anytime).
- **Per-feature command bar** — Recent runs (the exact adb commands + output),
  the Commands a feature uses (copyable), and an embedded terminal, beneath every
  feature.

### Improvements

- **Mirror Screen (scrcpy)** options — max size, bit-rate, FPS, record-to-file,
  view-only, always-on-top, fullscreen, keep-awake, turn-screen-off.
- **Screen Record** options — resolution, bit-rate, time limit, rotate, timestamp
  overlay. **Screenshot** — capture delay and copy-to-clipboard.
- **Sidebar** — VS Code-style flat list, drag-to-reorder (when ungrouped),
  `⌘1`–`⌘9` quick-select, pinned items, category-grouping toggle.
- **Setup Doctor** verifies the toolchain (adb / scrcpy / emulator / ffmpeg /
  Homebrew). App icons in the Apps list. `⌘=`/`⌘-` font zoom. The device + bundle
  pickers lock while a recording is in flight.

### Notes

The "Frequent" sidebar section was removed. Each feature's how-it-works note now
shows inline beneath the feature rather than in a toolbar popover.

## Droidective v1.0.0

The first public release of **Droidective** — a native macOS companion for
Android and React Native debugging. A Raycast-style command palette puts 37
one-click `adb` actions a `⌘K` away, with no terminal required.

Built in Swift 6 + SwiftUI, with all logic in a platform-agnostic `ADBKit`
package (111 unit tests, runs without a device).

### Highlights

- **Command palette (`⌘K`)** — search and run any feature; arrow-key navigation,
  a Frequent section, and per-feature hotkeys.
- **Device bar** — pick a device (with Android version + battery), run-on-all
  fan-out, a contextual app-bundle picker, and an active-overrides pill.
- **Emulator manager** — list, launch (normal / cold boot / wipe data), and stop
  your Android Studio AVDs.
- **File Explorer** — browse device storage with multi-select, copy/cut/paste,
  delete, new folder, Get Info, drag-in / push from the Mac, and pull with a
  real progress bar.
- **Apps explorer** — every user + system app, searchable by name/version/bundle,
  with live runtime-permission control and APK pull.
- **Logcat** — live stream with level/app/tag/text filters, follow-to-bottom,
  tag highlighting, and export.
- **Screen** — scrcpy mirroring, screenshots with in-app preview and drag-out,
  screen recording with optional GIF, demo mode.
- **Device state overrides** — fake battery, dark mode, font & density,
  animation scale, locale, network toggles, HTTP proxy — all reset-tracked.
- **Diagnostics** — crash catcher (Slack/Jira formatting), one-click bug-report
  zip, device overview (RAM, storage, battery health & cycle count, CPU, app
  counts).
- **Custom commands** — your own `adb` macros with `{bundleId}`/`{serial}`
  placeholders, tokenized safely (never run through a shell).

Every feature carries an ⓘ "how it works" note, and every file pulled from the
device asks where to save.

### Requirements

- macOS 14 (Sonoma) or later
- Android `adb` (the app finds it via `ANDROID_HOME`, `~/Library/Android/sdk`, or
  Homebrew, and offers a one-click install if missing)
- Optional: `scrcpy`, `ffmpeg`, the Android SDK `emulator`

### Install

Download the `.dmg` below, open it, and drag **Droidective** into
**Applications**.

The build is ad-hoc signed but not notarized, so on first launch macOS shows
*"Droidective is damaged and can't be opened."* Clear the Gatekeeper quarantine
once:

```sh
xattr -dr com.apple.quarantine "/Applications/Droidective.app"
```

Then open it normally. Building from source (`brew install xcodegen && make run`)
avoids the quarantine entirely.
