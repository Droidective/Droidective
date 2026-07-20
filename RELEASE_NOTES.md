## Droidective v3.6.0

The JS Console and Reactotron learn to export and search inside objects,
logcat becomes a real columnar log viewer, emulators finally go by their AVD
names, the React Native role reaches iOS Simulators, and the window gets a
custom background and text color.

### JS Console

- **Export the filtered feed** — the share icon in the filter bar saves
  exactly the rows the feed is showing (level and text filters applied) as a
  JSON file, or copies them to the clipboard.
- **Find in object, with clickable results** — typing in an expanded
  object's find field lists `path: value` matches; clicking one expands the
  tree along the path and highlights the node in place.
- **Clear cache and restart** — Restart app becomes a split button; the new
  option clears the app's cache first, and a hung cache clear can't stall
  the restart.
- **A connection that takes care of itself** — discovery now runs
  `adb reverse` for you (and retries a transiently failed one), a half-dead
  connection self-heals, the session survives pane moves, and auto-connect
  waits for a target to settle before attaching, so it no longer crashes an
  app that's still booting.
- **Quieter rows** — URLs underline only on hover, the whole row toggles
  its object, and the hover copy button reserves its space so rows never
  reflow.

### Reactotron

- **Export a pane** — the same JSON file / clipboard menu as the console,
  per timeline pane.
- **Clickable search results in JSON trees** — searching a payload lists
  matches; clicking one reveals the node in place.
- **Reworked filter controls** in the timeline.

### Logcat

- **Aligned columns** — time (toggle the clock from the toolbar), pid-tid,
  the process *name* (resolved live, refreshed as new processes spawn), a
  filled level chip, the tag in a stable color, and the message tinted by
  severity. Monospaced, scannable, and steady while streaming.
- **Selection holds the tail** — clicking a line pauses follow so the
  stream can't scroll your selection away; the jump button resumes.
- **No more bounce at the cap** — the 5000-line ring now trims in chunks as
  one editing pass.

### Devices

- **Emulators go by their AVD name** — "Medium Tablet" instead of the
  generic system-image model, everywhere devices are listed: the device
  dropdown and pill, Quick Actions device rows and run-on-all toasts, and
  the menu bar.
- **Mirror from the device bar** — a display button next to the device pill
  opens the scrcpy mirror (Android devices, hidden while the mirror is
  already open).
- **The React Native role spans platforms** — booted iOS Simulators join
  the device bar and launch lists, iOS Logs and the Simulate hub join the
  role's curation, and the emulators screen covers both.

### Appearance

- **Custom window background and text colors** — pick both, like the
  accent; the app's light/dark scheme follows the background's luminance,
  opaque feeds and lists honor it, and a low-contrast text choice warns
  without blocking. The Font settings section is now called Text.
- **Grain at any opacity** — the film-grain texture no longer needs a
  translucent window; the slider works at 100% too.

### Updates

- **A redesigned What's New sheet** — an accent-badged masthead and styled
  release notes, applied to older entries too.

### Fixes

- Succeeded install rows hide themselves after five seconds; failures stay
  until retried.
- Terminal: top-strip tabs no longer clip, and closed tabs' numbers are
  reused.
- The React Native hub no longer greys every quick action while one runs.
- The sidebar toggle works again after a split-resize eviction, and the JS
  Console releases keyboard focus when its tab goes to the background.
- Export failures (console and Reactotron) now show an error toast instead
  of silently doing nothing.
- Mirror Screen re-fits its video when the pane resizes — resizing a split
  no longer leaves dead space on one side with the device screen drawn past
  the pane edge.

### Install

Download `Droidective-v3.6.0.dmg` below. Existing installs update in place
via Sparkle.

---

## Droidective v3.5.0

The window turns to glass, Reactotron's timeline remembers your filters and
splits properly, Send Text becomes a manageable snippet library, and Quick
Actions can stop emulators.

### Translucent window (new)

- **See your desktop through the app** — Settings ▸ Appearance gains a
  Window section with Opacity, Blur, and Grain sliders. Below 100% opacity
  the whole window turns to glass (down to 10%): what's behind shows through
  every pane, softened by Blur and textured by a Metal-rendered Grain. Every
  surface obeys, the terminal included.
- The Settings window widens to 640×540, and the per-feature how-it-works
  notes (and their Appearance toggle) are gone.

### Reactotron, reworked

- **Filters survive** — each timeline pane's event-kind filter, API
  method/status refinements, and search persist per pane across feature
  switches and app relaunches; the split itself is remembered too.
- **Per-pane clear** — in a split, each pane gets its own clear that leaves
  the other pane alone. An accidental right-pane clear is undone by closing
  and reopening the split, and a cleared pane now says "Pane cleared"
  instead of showing setup instructions over a live session.
- **The split stops jumping** — opening or closing the split keeps the main
  pane anchored on the row you're reading (expanded rows included) instead
  of snapping back to the newest event.
- **No more horizontal scrolling** — rows fit the pane at any width: long
  lines truncate in the middle with the full text in the expanded row, and
  the API Response/Request tabs collapse to a menu in narrow panes so no
  control is ever clipped.
- **Click anywhere on a row** to expand it — copying lives on the hover
  copy button, the right-click menu, and the expanded row's selectable text.
- **⌘-click URLs in the JS Console** — http(s) links in console output are
  underlined; ⌘-click opens them in your browser, plain clicks still select
  text (bare domains like `config.io` never turn into links).

### Send Text, redesigned

- The feature becomes two hub sections over one snippet list — sending and
  managing snippets live together, New Snippet sits next to the list, and
  only failed sends report inline.
- **Click-to-append placeholders** — snippet placeholders insert with a
  click; the `{ip}` placeholder shows only for the React Native role.

### Quick Actions

- **Stop running emulators and simulators** straight from the panel.

### Install

Download `Droidective-v3.5.0.dmg` below. Existing installs update in place
via Sparkle.

---

## Droidective v3.4.1

A crash fix for AAB to APK, and a stricter keystore picker.

### Fixes

- **No more crash when converting an AAB** — asking for notification
  permission (so the converter can tell you when a background install
  finishes) crashed the app on the newest macOS, whether you allowed or
  denied. The permission request now uses a thread-safe path.
- **The keystore chooser only accepts keystores** — the signing file picker
  greys out everything except `.keystore` and `.jks` files, in both the AAB
  converter's signing sheet and APK Studio's Sign tab.

### Install

Download `Droidective-v3.4.1.dmg` below. Existing installs update in place
via Sparkle.

---

## Droidective v3.4.0

An AAB to APK converter joins the toolset (the 58th), updates now install
themselves silently, the Crash Catcher becomes a real multi-crash browser,
and wireless pairing connects on its own.

### AAB to APK (new)

- **Convert an Android App Bundle to an installable APK** — the new tool runs
  `bundletool build-apks --mode=universal` and writes `<name>-universal.apk`
  to your capture folder. Optionally sign with your release keystore
  (passwords passed via temp files, never on the command line); without one,
  bundletool uses your debug keystore.
- **Works offline out of the box** — bundletool and uber-apk-signer ship
  inside the app, with upgrades still managed in Settings ▸ Tools.
- **Double-click `.aab` or `.apk` files in Finder** — bundles open in the
  converter; APKs open a workspace tab with app info, per-device install
  rows, and Open in APK Studio.
- **Installs run in the background** — they survive navigation and window
  closes, show live progress under the device bar, and post a macOS
  notification when a batch finishes while the app is in the background.

### Updates install themselves

- **Silent download** — with automatic downloads on (the default), updates
  download and stage in the background; a "Relaunch to update" pill appears
  at the bottom of the sidebar. Click it to update now, or just quit — the
  update applies anyway.
- **With auto-download off** you get an "Update available" pill and a
  once-per-version notification instead; nothing downloads until you say so.
- **What's New after updating** — the first launch of a new version offers
  the release notes in-app.
- Checks run on launch and hourly; manual checks (menu, Settings, About) are
  the only place "You're up to date" appears. Background (menu-bar-only) mode
  gets its own Update rows in the menu.

### Crash Catcher, rebuilt

- **A multi-crash browser** — the buffer is split into individual crashes
  (Java, native, React Native, ANR) in a list + detail layout, instead of one
  raw dump.
- **Filter by kind, process, or text**, with trace highlighting (marker lines
  red, `Caused by:` orange, frames dimmed), a raw/messages toggle, copy as
  plain/Slack/Jira, and save to file.
- **Watch mode** polls every 5 seconds and toasts when a new crash lands;
  **Clear Buffer** empties the device's crash log behind a confirmation.
- **No more missing crashes** — the fetch cap rises from 512 KB to 16 MB; the
  old cap silently dropped the newest crashes on busy devices.

### Send Text snippets, reworked

- **One "＋ New Snippet" button** replaces the bookmark menu and chip; your 6
  most recently used snippets sit under the field as one-click tags.
- **A searchable library** below the Run button — name and preview per row,
  click to insert, right-click to remove, with search appearing once the
  library grows past 10.

### Wireless & connection

- **Pairing auto-connects** — after a successful Android 11+ pair, the sheet
  discovers the device's connect endpoint over mDNS and connects without
  asking for the second port.
- **A bare IP connects on 5555** — the Connect field no longer requires an
  explicit port.

### Layout & polish

- **Split panes stay usable** — the divider clamps to 30–70%, and every
  feature adapts to narrow panes (toolbars reflow to two rows, master
  columns scale proportionally, Mirror Screen's control bar folds into an
  overflow menu instead of clipping). Dragging past the limit hides the
  sidebar to make room.
- **The welcome tour is skippable** — Skip, Esc, or click-away all end it;
  the finale gains a Finish button.
- **Reading pauses the feed** — expanding a Reactotron item or a JS Console
  object pauses tail-follow so streaming events can't scroll it away.
- **Drop-to-split works with APK tabs open** — a full-pane drop target in the
  AAB/APK screens was swallowing tab drags.
- The light app icon is now used everywhere, and toolbar pickers hug their
  labels instead of floating in fixed-width gaps.

### Install

Download `Droidective-v3.4.0.dmg` below. Existing installs update in place
via Sparkle.

---

## Droidective v3.3.1

iOS Logs is rebuilt around how the simulator's unified log actually behaves,
and ⌘F now always lands where you expect it.

### iOS Logs, rebuilt

- **Scoped to your apps by default** — the unified log unfiltered is the whole
  simulator OS (thousands of lines a second). The stream now covers only
  installed apps' processes; *Everything* is one click away when you need
  system logs.
- **Scrollback that holds still** — scrolling up freezes the feed; new lines
  wait behind a "N new" pill (with a waiting count in the status bar) and
  fold in when you click it or scroll back to the tail. No more unscrollable
  firehose.
- **Xcode-style entries** — the message leads, with a toggleable metadata
  line (time · process (pid) · subsystem · category), a severity color bar,
  and tinted error/fault rows.
- **Error & fault counters** — live tallies in the status bar; click to flip
  the feed to errors only and back.
- **Sharper filtering** — a multi-select level menu (Info and Debug also
  widen what the simulator emits), a process menu built from the stream
  itself (or right-click a line), free-text filter, and ⌘F find.

### ⌘F lands where you expect

- **No more focus jumping to the sidebar** — ⌘F used to be claimable by a
  hidden tab, sending focus to the sidebar search. It now always targets the
  screen you're on: the find bar in Logcat, iOS Logs, and the JS Console —
  and in Reactotron it focuses the timeline search, its only text filter.
  The sidebar search only takes focus from ⌘T or a click.

### Settings

- **Check for Updates in Settings** — the Updates section shows the installed
  version with a Check for Updates button, alongside the update toggles.
- **Quick Actions can close after a run** — a new option dismisses the panel
  once an action succeeds (failures keep it open so the error stays
  readable).

### Install

Download `Droidective-v3.3.1.dmg` below, or `brew install --cask
rohindh-r/tap/droidective`. Existing installs update in place via Sparkle.

---

## Droidective v3.3.0

A JS console that stays connected, a screen mirror that no longer eats CPU
after you leave it, logcat search split into separate Filter and Find, and a
first iOS feature: streaming a simulator's native logs.

### Logcat: Filter vs Find

- **Filter and Find are now separate** — the toolbar field *filters* (shows
  only matching lines, as before); a new find bar (⌘F) *finds*: it highlights
  matches and steps through them with ⌘G/⇧⌘G and a "2 of 7" counter without
  hiding anything.
- **One app selector** — the App menu inside logcat now does everything the
  bar's bundle pill did (pick a saved bundle, add from the device's installed
  apps, grab the app on screen, manage), and the bundle pill no longer
  doubles up above it.

### iOS Logs (new)

- **Stream a simulator's unified log** — the new iOS Logs feature tails a
  booted iOS Simulator's native logs (`log stream`) in the same pane logcat
  uses: level picker, text filter, the ⌘F find bar, export, and right-click
  to filter by process.

### JS Console stays connected

- **No more idle disconnects** — a silent keepalive satisfies React Native's
  inspector-proxy heartbeat, which a plain WebSocket ping doesn't.
- **Reconnects survive app relaunches, phone sleep, and Metro restarts** —
  auto-reconnect no longer strands itself on a stale device id.
- **Plays nice with React Native DevTools** — when another debugger takes
  over (RN ≤ 0.84 allows one), the console stands down with a notice instead
  of fighting for the session; on RN 0.85+ both attach side by side.
- **No duplicate logs on reconnect** — Hermes' replayed console history is
  deduplicated, so the feed no longer doubles after each reconnect.

### Screen mirror

- **Fixed: runaway CPU after using the mirror** — switching away from the
  mirror while it was still connecting could leak a session that kept
  streaming and decoding until the app quit (the reported 500%+ CPU). Leaked
  sessions and stray adb tunnels are gone.
- **Lower latency** — frames render as they decode, touch input isn't
  batched by the TCP stack, and the slow-motion catch-up after opening the
  mirror is gone.
- **Device audio is now opt-in** — the mirror starts video-only; the Audio
  switch streams device audio too (Android 11+). The choice persists.

### Improvements

- **Device dropdown refreshes itself** — opening it re-scans for devices;
  the separate refresh button appears only when nothing is connected.
- **Smooth resizing** — dragging the sidebar edge and the split-pane divider
  no longer jitters.
- **Newest-first logs** — Logcat, JS Console, and Reactotron can flip to
  newest-at-top.
- **Beta update channel** — Settings ▸ General ▸ Updates gains an opt-in
  beta channel; opting out never downgrades.
- Reactotron's Copy as cURL keeps query params and form fields, timeline
  frames stay in wire order, and large frames no longer truncate.
- Pulling an app's APK grabs every split APK, not just base.apk.
- Device platforms, features, and the Emulators screen scope to your role.

### Install

Download `Droidective-v3.3.0.dmg` below, or `brew install --cask
rohindh-r/tap/droidective`. Existing installs update in place via Sparkle.

---

## Droidective v3.3.0-beta.2

This beta fixes the runaway-CPU reports traced to the screen mirror and cuts
the mirror's display and input latency.

### Screen mirror

- **Fixed: runaway CPU after using the mirror** — switching away from the
  mirror tab while it was still connecting could silently restart the session
  in the background, where nothing could ever stop it. Each leaked session
  kept streaming and decoding (about a core each, and they stacked) until the
  app quit — the reported 500%+ CPU after using the mirror traces to this.
- **Fixed: stray adb processes and tunnels** — a stop racing a starting
  session could strand an idle adb client, its port forward, and the
  device-side server. Teardown now also cleans up whatever the racing start
  created.
- **Lower latency** — frames render the moment they're decoded instead of
  being paced against a mismatched clock, touch input is no longer batched by
  the TCP stack, and frames can't queue behind a busy UI — the slow-motion
  catch-up for the first seconds after opening the mirror is gone, along with
  picture smearing when the app was under load.
- **Device audio is now opt-in** — the mirror starts video-only; the Audio
  switch in the control bar streams device audio too (restarts the mirror,
  Android 11+). The choice persists.

### Reactotron

- **Copy as cURL keeps query params and form fields** — copied requests now
  reproduce the original URL and body.
- Timeline frames stay in wire order, and large frames no longer truncate.

### Also in this beta

- Pulling an app's APK grabs every split APK, not just base.apk.

---

## Droidective v3.3.0-beta.1

The first beta-channel release. The headline is a JS console that stays
connected: four root causes of the repeated disconnects are fixed, verified
against React Native 0.82 through 0.86.

### JS Console stays connected

- **No more idle disconnects** — React Native's inspector proxy kills a
  debugger socket that stays quiet through its heartbeat window, and a
  WebSocket ping doesn't count. The console now sends a tiny silent no-op
  evaluate as a keepalive, paced so even a wedged JS thread can't stall it.
- **Reconnects survive app relaunches, phone sleep, and Metro restarts** —
  the proxy hands the app a fresh device id whenever it re-registers; the
  console now falls back to the app's id, so auto-reconnect no longer strands
  itself on a stale id.
- **Plays nice with React Native DevTools** — when another debugger takes the
  app over (RN ≤ 0.84 allows only one), the console stands down with a notice
  instead of stealing the session back in a loop. On RN 0.85+ both attach
  side by side.
- **No duplicate logs on reconnect** — Hermes replays its console history on
  every attach; a replay gate drops the already-shown portion, so the feed no
  longer doubles after each reconnect.
- **Newest-first, when you want it** — Logcat, JS Console, and Reactotron
  gain a reverse-order button.

### Beta update channel

- **Receive beta updates** — Settings ▸ General ▸ Updates gains an opt-in
  beta channel (how you're reading this). Opting in checks immediately;
  opting out never downgrades — the app simply waits for the next stable.

### Also in this beta

- Device platforms, features, and the Emulators screen scope to your role.
- Reactotron connection gaps and truncated timeline rows are fixed.
- The Settings update toggles now render their state correctly.
- Gallery tiles align to a uniform 16:10 crop.

---

## Droidective v3.2.0

Wireless debugging moves into the device dropdown: pair and connect a device
over Wi-Fi from anywhere in the app, with a guided flow for each path.

### Connect over Wi-Fi

- **Pair & connect from the device dropdown** — the device menu gains a
  "Wireless debugging" section with *Pair new device…* and *Connect to
  device…*, opening a guided sheet with three paths:
  - **Pair new device** — numbered steps that mirror the phone's Android 11+
    pairing dialog: where to find it, one field for the `ip:port` it shows plus
    the 6-digit code, then a connect step that explains the connection port
    differs from the pairing port (the host carries over after pairing).
  - **Already paired** — a single `ip:port` field for a device that was paired
    before or is already in tcpip mode.
  - **Via USB cable** — one click switches a plugged-in device to Wi-Fi
    debugging and connects; the device list updates live.
- **Paste-friendly addresses** — every address field takes the exact
  "IP address & Port" string the phone displays (IPv6 and stray whitespace
  included); buttons stay disabled until the input is valid.
- **Clear outcomes** — adb's own reason is shown inline on failure (wrong
  code, unreachable host, an adb too old to pair), and a successful
  connection selects the new device and confirms in a notification.

### Fixes

- The tab strip's Home button no longer sits flush against its divider.

---

## Droidective v3.1.0

Custom commands get a full rework, the Quick Actions panel becomes yours to
curate, and dismissed updates stop disappearing.

### Custom Commands

- **One box, full command lines** — type commands exactly as you'd run them in
  a terminal (`adb shell am force-stop {bundleId}`); the separate adb/Terminal
  mode tabs are gone. Lines starting with `adb` still run through
  Droidective's own adb — tokenized safely, device `-s` injected — and
  everything else runs through your login shell.
- **Multi-line commands** — the editor is a proper multi-line box; each line
  runs in order through your shell. Save with ⌘⏎.
- **Pick the terminal** — a command that shows output "in a terminal" can open
  Droidective's Terminal (default) or your Mac's default terminal app, with
  the selected device exported as `ANDROID_SERIAL` either way.
- **Redesigned editor** — labeled fields, one-click `{bundleId}` / `{serial}`
  chips, and a live cue showing where the line will run.

### Quick Actions

- **Pick an app in place** — running a `{bundleId}` command with no app
  selected opens a picker (saved bundles first, then the device's installed
  apps) instead of failing.
- **Clear device guards** — a device-targeting command with nothing connected
  says so up front, and the multi-device picker covers custom commands too.
- **Pin custom commands** — ⌘P or right-click; pinned tiles lead the grid
  alongside pinned features.
- **Choose what shows** — right-click any action tile to hide it from the
  panel; manage the full list under Settings ▸ General ▸ Quick Actions.

### App management

- **Restart, everywhere apps are managed** — a one-click force-stop +
  relaunch in the Apps explorer, the Manage App screen, and the Quick
  Actions panel; the JS Console's Restart app rides the same path.
- **Launching works on more devices** — apps open via their resolved
  launcher activity (`am start`) instead of relying on `monkey`, which is a
  do-nothing stub on some OEM/custom Android builds. When a launch does
  fail, the message now says whether the app is missing or just has no
  launcher activity.

### Updates

- **Checks twice a day** instead of daily.
- **Dismissed updates come back** — closing or skipping the update alert now
  resurfaces it as a notification on every launch until you install, with a
  Check for Updates button. Turning off automatic update checks in Settings
  silences the reminder too.

### Welcome tour

- The tour now ends in two Quick Actions steps: pick the global hotkey, then
  a finale that draws your hotkey as animated keycaps — pressing it for real
  opens the panel, finishes the tour, and fires a confetti celebration.

### Terminal & tabs

- The Terminal's tab list defaults to the Chrome-style top strip (the left
  rail is one click away).
- Tab strips gain right-click **Close Other Tabs** (anything with unsaved
  work still asks first).

### Removed

- The app no longer installs tools via Homebrew. The setup Doctor and the
  device bar now link to the official install source (Android Studio or the
  platform-tools download) instead of running `brew` for you — already
  installed tools keep being found wherever they live.

### Fixes

- The auto-hide sidebar no longer draws a stray horizontal line across its
  middle when revealed.
- The window title follows the active tab instead of sticking on
  "About & Feedback".
- One Settings… item in the app menu on macOS 26 (it was duplicated).
- JS Console: clicking "adb reverse" right after typing a new Metro port now
  reverses the new port — no ⏎ needed first.

## Droidective v3.0.1

A bug-fix release: confirmations before destructive actions, several features
that now work without an Android device selected, honest status messages, and
tighter analytics.

### Fixes

- **Uninstall asks first** — the Uninstall button in the Apps list now shows a
  confirmation, matching Clear Data. It previously removed the app and its data
  on the first click.
- **Logcat streams after a device authorizes** — opening Logcat on a device
  that was still unauthorized left the stream empty even after you approved the
  adb prompt. It now starts as soon as the device is ready.
- **APK tools open without a device** — APK Studio, APK Inspector, Sign APK, and
  Decompile APK work on local files and no longer require an Android device;
  they stayed usable with only an iOS Simulator selected.
- **Monkey Test confirms before running** — it warns before sending random
  events, and when a long run hits the time limit it reports that events were
  already sent instead of "failed".
- **Frida on a non-rooted device** — Frida now checks for root before pushing
  the server and shows a clear message pointing to frida-gadget, instead of a
  status that said "Started" while also requiring root.
- **Change Locale is honest** — the toast now says the locale change was
  requested (a full system change can require root) rather than claiming it
  was set.
- **Crash Catcher shows one crash** — the last-crash view no longer runs
  together multiple crashes when several are buffered.
- **Reactotron opens without an Android device** — its server is host-side, so
  it no longer requires an Android device to be selected.
- **Screen Record surfaces a disconnect** — if the device drops mid-recording,
  the timer stops and the captured footage is kept for saving, instead of the
  timer running on against a dead stream.
- **Performance recording survives a disconnect** — samples are kept and stay
  exportable when the device disconnects, rather than being cleared.
- **Network Speed totals** — session download/upload totals no longer jump to a
  bogus value if the device reboots mid-recording.
- **Quick Actions panel** — "all devices" only fans out actions that support it
  (matching the main window), multi-device runs report each device's outcome,
  the panel opens on the display under the pointer, and a quick screenshot names
  the saved file.
- Manage App's confirmation states how many devices it affects; the app picker
  refreshes when you switch devices; and tool detection re-checks after you
  install adb (or another tool) while the app is open.

### Privacy

- Anonymous analytics no longer include the device model or Android version —
  only whether the device is an emulator or wireless. This matches the privacy
  policy and the Settings description.

### Improvements

- **Bundled developer tools are pinned** — jadx, apktool, uber-apk-signer,
  frida-server, and the bundled Java runtime install known-good pinned versions
  instead of whatever is latest upstream.
- Third-party license notices now cover every bundled and linked component.

Installed copies update in place via Sparkle.

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
