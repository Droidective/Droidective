# Desktop parity tracker — Windows & Linux

What the macOS app does, feature by feature, and how far `desktop/` has got.
The goal is not "a Windows client exists"; it is that someone moving between
the two should not have to relearn anything.

**This file is the tracker.** Tick items as they land. Add a line rather than
rewriting one when something turns out to be more work than it looked.

## Status today

| | Count |
| --- | --- |
| ⬜ Not started | 17 |
| 🟡 Partial | 42 |
| ⛔ Not applicable off-Apple | 2 |
| **Total registry features** | **61** |

"Partial" is doing a lot of work in that table: 19 of the 42 are actions that
run from the palette but have no screen of their own, and the 23 that do have
screens are each missing something the Mac version offers. Read it as *nothing
is finished*, not as *most of it is done*.

**Screens with a real pane today** (23): Terminal, Apps, Logcat, Device Info, File
Explorer, Crash Catcher, Bug Report, Performance, Root Status, Developer
Settings, System Restrictions, Wi-Fi, Private DNS, Network Speed, Emulators,
Install App, App Info, Permissions, Memory Usage, Sandbox Browser, Manage App,
Deep Links, Reactotron — plus the two app-chrome screens, the catalog and
About. That list is not written here twice:
`scripts/generate-parity-tracker.py` reads it out of the desktop app's pane
router, so a screen that lands is partial in the checklist below without anyone
remembering to say so.

**Only two features are out of scope**, and only because they drive an Apple
toolchain rather than a device: `ios-logs` and `push-notification` are `xcrun
simctl` against an iOS Simulator. Everything else — the mirror, screen record,
the video editor, Reactotron, multi-window, Quick Actions, the tour, the
updater, notifications, every drag-and-drop path — is a porting job with an
entry in the backlog. Hard is not the same as impossible, and a ⛔ that means
"hard" is a decision nobody goes back to revisit.

**The UI is the Mac's UI.** Where a control exists on both, it looks and
behaves the way `App/Sources/FeatureDetail/Views/` makes it behave — same
wording, same icon, same confirmation shape, same gesture. A nicer idea for
Windows and Linux is still a difference someone has to relearn, so it does not
belong here; if it is genuinely better, it goes in the Mac app first. The two
standing exceptions are named where they occur: a keyboard shortcut whose
modifier has no Windows/Linux equivalent, and a label that names a platform
("Pull to Mac").

## How this was built

The per-feature sections are **generated from the sources**, not written from
memory: the registry as `/v1/features/list` serves it, the id → view mapping
from `FeatureDetailRoute` + `FeatureDetailView.pane`, the "must replicate" lists
from the actual `Button`/`Toggle`/`Picker`/`Menu`/`TextField`/`.help`/
`.searchable`/`.keyboardShortcut` calls in each SwiftUI view, and which screens
this app already has from the desktop pane router itself.

That means the lists are **evidence, not a specification**. They are a floor:
an affordance that is not a literal string in the view (a gesture, a drag, an
inferred empty state) will be missing, so each feature still needs a look at
its view before it is called done. Regenerate after registry changes rather
than hand-editing the generated half:

```sh
# with a daemon running, capture the registry, then rebuild the generated half
curl -s -X POST http://127.0.0.1:$PORT/v1/features/list \
  -H "Authorization: Bearer $(cat "$TOKEN_FILE")" > /tmp/features.json
python3 scripts/generate-parity-tracker.py . /tmp/features.json
```

Everything above the "Per-feature checklists" heading is hand-written and is
not regenerated — paste the generated half back under it.

## Order of work

The shell comes first. Porting screens into a window that has no tabs, no
split panes and no palette produces something that looks like Droidective in a
screenshot and does not feel like it in use — and every screen ported before
the shell exists will need reworking to live inside it.

The sidebar, the tab strip, split panes, the palette, per-feature hotkeys, the
UI zoom and the device bar have landed, so a screen ported now opens in a tab,
splits, takes a shortcut and reports through the toasts without being reworked
for any of it. What is left of the shell is the menu bar, multi-window, and the
window translucency.

1. **Shell parity** (below) — tabs, split panes, sidebar, palette, hotkeys.
2. **The screens people open every day** — logcat, file explorer, device info,
   apps, crash catcher.
3. **The rest of the views**, then the long tail of actions that deserve a
   real screen rather than a form.

---

## Cross-cutting shell

Sourced from `CLAUDE.md` and the App sources. The navigation half has landed;
the chrome and the device bar have not.

### Navigation and layout

- [x] **Grouped sidebar** of features by category, with per-category collapse
      (`LayoutState.collapsedCategories`). Category order and headings are held
      in `desktop/src/lib/sidebar.ts`, not sent over the wire — the daemon
      serves registry order, which is not display order. A test fails if the
      daemon starts serving a category that table has never heard of.
- [x] **Drag to reorder** — a feature drags within its group, a category header
      drags the whole group, with an accent insertion guideline. A feature may
      not leave its category, and a drop past the last row of a group lands at
      the end of *that group*, not the end of everything (`applyDrop`).
      Two platform requirements make this work at all: Tauri's
      `dragDropEnabled` must be `false` (its native handler otherwise swallows
      HTML5 drag) and WebKit needs `-webkit-user-drag: element`, because the
      app sets `user-select: none` and WebKit will not drag unselectable
      content.
- [x] **Auto-hiding sidebar** (Dock-style) — the device bar's leading button
      switches between the pinned sidebar and auto-hide, hovering the window's
      left edge peeks it, and Ctrl/⌘ + B toggles. ADBKit's `SidebarVisibility`
      is ported to `lib/sidebarMode.ts` with its two transitions intact,
      including the one worth keeping: with the pinned sidebar evicted by a
      split-resize, the button brings it back rather than switching a mode
      nobody could see. Only the *mode* is persisted; whether it happens to be
      peeked right now is a fact about this session.
- [x] **Feature tabs** — a permanent Home tab leading the strip, drag to
      reorder, ⌘W / Ctrl+W to close, ⌘1–⌘9 to jump. Open tabs stay mounted and
      hidden rather than unmounted, so a background tab keeps its log stream and
      its loaded lists. Ported from ADBKit's `TabState`, close-focus rules
      included.
- [x] **Split panes** — two panes, clamped 30–70% with the same absolute
      per-pane floor (`PaneSplit`, ported to `lib/panes.ts`), a draggable
      divider that persists, and the pane rules ported from ADBKit's
      `Workspace`. A tab's right-click menu splits, moves it across, or closes
      it and its neighbours. The shortcut is **Ctrl/⌘ + \\**, not ⌘D: Ctrl+D is
      end-of-input in every Linux shell, and it is the split-editor binding
      people already have from VS Code.
- [x] **Drop-to-split** — dragging a tab onto the trailing edge of the only
      pane splits there; dropping it on the other pane's strip moves it.
- [ ] **Drops from outside the app** — a file dragged from the file manager
      onto the File Explorer (`adb push`), and an APK or AAB dropped on the
      window to install it. The blocker is that `dragDropEnabled: false` is
      what makes the *tab* drags work at all, so the two have to coexist rather
      than one being switched off for the other.
- [ ] **Multi-window** (`docs/multi-window.md`).
- [x] **⌘= / ⌘- zoom** of the whole UI, with ⌘0 for Actual Size and the same
      eight steps the Mac walks, so the same number of presses lands on the same
      size in both apps. The content is laid out at `size / scale` and scaled up
      — the Mac's own description of its `scaleEffect` — and the sizing is
      explicit rather than left to the engine, because `zoom` on the root
      behaves like page zoom only where the standardised version shipped and
      this app also runs on WebKitGTK. Also in Settings ▸ Appearance ▸ Window.

### Finding things

- [x] **Command palette** — Ctrl/⌘ + K or T, and the tab strip's `+`, which
      focuses its pane first so the choice lands there. Arrows move, Enter
      opens, Ctrl/⌘ + P pins. With no query it opens on the pinned list; with
      one, relevance decides and pins are not promoted. Commands are not in it
      yet — this app has no custom commands to offer.
- [x] **Per-feature hotkeys**, recordable, with a live-preview recorder — from
      Settings ▸ Hotkeys or a sidebar row's right-click. The Mac's rules: at
      least one of Ctrl/Alt/⌘, Esc cancels, Backspace clears, an instant action
      runs where anything else opens. Two differences, both stated where they
      occur. They fire **while the window has focus**, not globally: the OS
      registration arrives with the Quick Actions panel below, and the recorder
      says so rather than promising it now. And a **toggle opens rather than
      running** — the Mac flips it from the override state it tracks, which this
      app does not keep, so it would have to guess a direction and write it to a
      device. The combinations the shell owns (⌘K/T/W/\\/,/1–9) are refused with
      the name of the command that holds them, because a window shortcut cannot
      outrank the shell the way an OS-registered one does.
- [ ] **Global hotkey → Quick Actions panel** — the non-activating mini app:
      grid of every runnable action, pinned first, custom commands, pick-device
      interstitial, ⌘⏎ run-on-all.
- [x] **Pinned / favourites** — a Pinned section leading the sidebar and the
      palette's empty-query list, pinned from either. Members are lifted out of
      their categories rather than listed twice, as `enabledFeatures(in:)` does
      on the Mac. Quick Actions does not exist here yet to share them with.
- [ ] **Manage features catalog** — turn features off; everything is on by
      default.

### Device bar

- [x] Device **dropdown** with model, state and enrichment — a popover rather
      than a `<select>`, because the Mac's menu is where an emulator gets
      launched and a device gets paired, and a native select cannot hold
      sections that *do* things. Its sections in its order: the devices, the
      AVDs not already running, Wireless debugging, Manage emulators. The
      leading status icon carries the colour and the tooltip, outside the menu,
      as the Mac splits them. **Absent:** the Windows section (multi-window,
      backlog 21) and the iOS Simulators section (`simctl`).
- [x] **Wireless pair & connect sheet** — the Mac's three tabs, its numbered
      steps and its wording: Android 11+ pairing with the code and the
      *pairing* port, a plain connect that takes a bare host at adb's own 5555,
      and the one-click USB→Wi-Fi bootstrap. Endpoints are parsed
      **daemon-side** by `ConnectionService.parseEndpoint`, so the two apps
      cannot disagree about what adb accepts; this side only decides when a
      button lights up (`lib/endpoint.ts`, deliberately permissive). A
      successful pair carries the endpoint the device then advertised over mDNS,
      so it connects without asking for a port the phone never showed.
- [x] **Run-on-all** across connected devices for `supportsRunAll` features —
      the switch appears only with more than one ready device *and* a focused
      feature the registry says fans out, and `effectiveRunOnAll` gates the
      fan-out on both, so a switch left on from Send Text can never reach a
      single-device action. The device pill is pinned while it is in effect.
      Send Text and Install App are the two ported features it applies to.
- [x] **Launch an emulator** from the bar — the AVDs with no running serial,
      re-read whenever the device set changes.
- [x] **Disconnect a wireless device** from the bar, as the Mac offers beside a
      wireless device's pill.
- [ ] **Pull progress strip** in the window's safe-area inset. Needs the
      protocol to grow a pull that *reports* — today `/v1/files/pull` either
      answers or does not — so it is not UI work, and it sits with the other
      pull gaps below.

### Chrome and feel

Every window, panel, sheet and menu the Mac has. Sourced by reading
`App/Sources/Root/`, `App/Sources/Settings/` and `ADTApp.swift`, not from
memory — the file each item names is the thing to replicate.

- [x] **Per-feature icons.** The daemon drops `FeatureDef.icon` on purpose —
      those are SF Symbol names, which mean nothing off Apple — so
      `desktop/src/lib/icons.ts` pairs each registry id with a lucide glyph
      chosen to read as the same thing the Mac's symbol does. A test fails if
      the daemon serves a feature the table has no entry for, so a new feature
      cannot quietly inherit its neighbour's icon.

#### The sidebar footer (`SidebarPaletteView`)

- [x] **Manage Features** — opens the `catalog` tab, and reads "+ N more
      features" once anything is hidden.
- [x] **About & Feedback** (ⓘ) — opens the `about` tab: version, report an
      issue, star on GitHub.
- [x] **Settings** (gear) — opens the Settings window.

#### Settings (`SettingsView`, 969 lines, seven tabs)

- [ ] **General** — every item is still waiting on its subsystem: the role
      picker, Open at login, background mode, the Quick Actions preferences,
      and the updater. The tab lists them and says which backlog item each
      arrives with, rather than showing switches that control nothing.
- [x] **Appearance** — Theme (light/dark/system) and Accent as presets *and* a
      colour well *and* a hex field with Reset, plus the light theme itself
      and the low-contrast warning. A Window section carries the sidebar mode
      and the UI size. **Still missing:** Background and Text colour, Font
      family, the Window opacity/blur/grain sliders (which the section names as
      not ported), and the Developer self-metrics overlay.
- [x] **Privacy** — Data & Storage ▸ the captures and pulls folder, with Open.
      Telemetry says outright that this app sends nothing, which is true and
      worth stating rather than leaving as an unchecked box. **Still
      missing:** Change…/Reset for the folder, and the Command Log.
- [x] **Doctor** — the toolchain check over `ToolDetectionService`: a verdict,
      then adb and emulator with their version and path, and the install source
      for anything missing. The Mac's own two checks — scrcpy and ffmpeg are
      detected but not *checked*, because on the Mac they are bundled and here
      the features that would need them are not ported yet. The app never
      installs a tool itself, on either platform. The device bar carries the
      "adb not found" warning off the same one detection.
- [ ] **Tools** — the managed-tool store: download, size, remove, upgrade.
- [x] **Hotkeys** — every feature in sidebar order with a live-preview
      recorder, plus the Mac's "Hidden features with shortcuts" section, since a
      feature turned off in the catalog keeps its shortcut and would otherwise
      be unbindable. The Global pair names what it waits on rather than showing
      a recorder that controls nothing.
- [ ] **MCP** — shown conditionally on the Mac; the Reactotron MCP server's
      switches. Follows Reactotron (backlog 23).

#### Panels and sheets

- [x] **Notification panel** (`NotificationPanelView`) — a persistent right
      column of the important notifications, toggled by the **bell in the
      device bar**, with its own empty state.
- [x] **Toasts** (`ToastOverlay`) — top-trailing, per action result, with a
      level and an optional Show in folder. Every ported screen was converted
      off its inline banner.
- [ ] **Command Log** (`CommandLogView`) — every `CommandLog.userInitiated`
      adb call, opened from Privacy.
- [ ] **Role picker** (`RolePickerView`) — shown on first launch before the
      tour (`LaunchPrompt.rolePicker`), and re-openable from General. A role
      curates which features the sidebar lists.
- [x] **Manage Features catalog** (`CatalogView`) — everything on by default;
      this is for turning things off, with a right-click on a group header for
      the whole group.
- [x] **About & Feedback** — the `about` tab: version, Report an Issue, Request
      a Feature, GitHub, Releases.
- [ ] **Welcome tour** (`TourView` + `TourDemos`) — skippable, ending on the
      two Quick Actions pages and the confetti finale.
- [ ] **What's New** (`WhatsNewPresenter`) — on first launch of a new version.
- [ ] **Star prompt** (`StarPromptView`) — the recurring, capped GitHub nudge.
- [x] **Wireless connect sheet** (`WirelessConnectSheet`) — the three-tab
      pairing / connect / tcpip bootstrap, opened from the device dropdown.
- [ ] **Installed-apps picker** (`InstalledAppsPickerView`) and the **bundle
      manager** (`BundleManagerView`).
- [ ] **Overrides pill** (`OverridesPillView`) — the standing reminder that a
      device override is in effect.
- [ ] **Install inbox** (`InstallInbox`) — an APK opened from the file manager
      before the window exists has to be buffered, not dropped.
- [ ] **Self-metrics overlay** (`DevOverlay`), behind the Appearance switch.

#### The menu bar (`ADTApp.swift`)

A webview has no menu bar of its own, so this is a real port: Tauri's native
menu plus the accelerators. Every item here is also a keyboard shortcut
somebody already has in their fingers.

- [ ] **File** ▸ New Window.
- [ ] **Terminal** ▸ New, Split Vertically, Split Horizontally, Close, Rename…,
      Next, Previous.
- [ ] **Tab** ▸ New Tab, Close Tab, Next, Previous, Show Tab 1–9.
- [ ] **Go**, **View** ▸ the sidebar commands, and the zoom pair.
- [ ] **Edit** ▸ Find Feature, Manage Features, Find in Terminal…, Find Next,
      Find Previous.
- [ ] **Help** ▸ Report an Issue…, Request a Feature…, Droidective on GitHub,
      Release Notes. **About Droidective** in the app menu.

#### Look

- [ ] **Window translucency** — the `.bgRoot`/`.bgSurface` token system, with
      `WindowEffects` already pure-tested in ADBKit. Note the Mac's blur is a
      private CoreGraphics call; Windows and Linux need their own (Mica /
      compositor blur) or the slider limits to opacity.
- [x] **Light theme** — ported from the asset catalog's own colorset values,
      applied as CSS custom properties on `:root` so every existing token
      follows it.
- [x] **Custom accent**, with the low-contrast warning. **Background and text
      colour are still missing**, as is the luminance-following scheme.
- [x] **The ⌘= / ⌘- zoom.** **Font family and the text-size scale are still
      missing** — the zoom scales everything together, where the Mac also lets
      the text size move on its own.
- [x] **Empty states per feature** ("connect a device") — the Mac's
      `NoDeviceView` shape, with its per-feature copy table ported.
- [ ] **Native notifications** — a finished background install, a crash caught
      while watching, an update staged. `tauri-plugin-notification`, behind the
      same Settings ▸ General switch the Mac puts it behind.
- [ ] **Background mode and a tray icon** — closing the window keeps the app
      resident, stops the kept-alive sessions, and leaves the global hotkey
      working.


---

## Defects in what already shipped

Found by driving the app against a live emulator, not by reading it.

- [x] ~~**`copyText` never reaches the clipboard.**~~ A result carrying
      `copyText` now lands on the clipboard the moment it arrives, as
      `AppState.show` does on the Mac, and says so. Through a Rust command
      (`tauri-plugin-clipboard-manager`), not `navigator.clipboard`, which
      needs a gesture the browser agrees was one and can fail silently on
      WebKitGTK — the same failure in a new place.
- [x] ~~**`revealPath` has no affordance.**~~ A "Show in folder" button, via
      `tauri-plugin-opener`. Both plugins are registered for their Rust APIs
      only, so the webview's capability file stays at `core:default`.
- [x] ~~**The destructive confirmation is sticky.**~~ An arming now records
      *which* button on *which* target, and expires after five seconds
      (`lib/confirm.ts`). A Cancel button appears while armed, the window
      losing focus disarms, and an arming on one app never authorises the same
      verb on another.
- [x] ~~**Logcat cannot be restarted.**~~ Stop becomes Start, and the
      subscription comes back with the buffer intact.
- [~] **Logcat has no level or app filter.** The level picker, the
      find-vs-filter split, export, clear and tag chips have landed. The *app*
      filter has not: it needs a pid → package map the daemon does not serve
      yet, and matching on the tag would be a filter that quietly misses lines.
- [x] ~~**The app list re-fetches on every tab switch**, because the pane
      remounts and the data is not lifted.~~ Fixed by the tab shell: an open
      tab stays mounted while it is in the background, so the pane no longer
      remounts and nothing re-fetches.

---

## Backlog

The order the remaining work is planned in, and what each item actually costs.
Tick an item here when its PR merges; the detail stays in the sections above.

**Done.**

| | Goal | Landed in |
| --- | --- | --- |
| ✅ | Grouped sidebar and feature tabs | #252 |
| ✅ | A glyph per feature | #253 |
| ✅ | The three action-result defects | #254 |
| ✅ | Split panes | #255 |
| ✅ | Command palette and pinned features | #256 |
| ✅ | Logcat: level, find-vs-filter, tags, export, restart | #257 |
| ✅ | Device info | #260 |
| ✅ | File explorer | #263 |
| ✅ | Crash catcher | #264 |
| ✅ | Performance monitor | #265 |
| ✅ | Toasts and the notification panel | #265 |
| ✅ | Root Status, Developer Settings, System Restrictions | #265 |
| ✅ | Wi-Fi and Private DNS | #265 |
| ✅ | App Info, Permissions, Memory, Sandbox, Manage App | #265 |
| ✅ | Sidebar footer, catalog, About, Settings, light theme | #265 |
| ✅ | Network Speed | #265 |
| ✅ | Emulators and Install App | #265 |
| ✅ | Per-feature hotkeys and their recorder | — |
| ✅ | Device bar: dropdown, wireless sheet, run-on-all, launch an emulator | — |
| ✅ | Auto-hiding sidebar and the ⌘= / ⌘- UI zoom | — |
| ✅ | Deep links, Bug Report, and Settings ▸ Doctor | — |

**Next, in order.** Everything from *File explorer* down needs four layers, not
one — a daemon route in Swift, a Rust command, a pane, and tests at both ends.
The daemon serves devices, features, apps and logcat today and nothing else, so
that is the real cost of each screen, and it is why they are ordered by how
often someone opens them rather than by how hard they look.

1. ~~**Device info.**~~ Landed — and it is the worked example of the four
   layers: `DaemonProtocol.Route.deviceProps` + a `DaemonBackend` method, a
   Rust `device_props` command, `lib/deviceinfo.ts` for the arranging, and a
   pane. Copy that shape for the rest.
2. ~~**File explorer.**~~ Landed — browse, copy/cut/paste, delete, pull, new
   folder, Get Info, the Root toggle, and a row context menu, over four
   filesystem routes plus `/v1/device/root`. It is the worked example for a
   screen that *writes*: paths travel verbatim and are quoted once, in
   `FileExplorerService`. Gaps below.
3. ~~**Crash catcher.**~~ Landed — two routes over `CrashExtractor`, then the
   browser: kind and process filters that list only what is present, a search,
   Watch on a 5 s poll that announces an arrival, Raw log, copy for
   Slack/Jira/plain, save to a file, and a Clear Buffer that keeps its
   watermark so the main-buffer fallback cannot resurface what it cleared.
4. ~~**Performance monitor.**~~ Landed — record-first as `PerformanceView` is,
   with the Stop-then-export dialog and both export formats.
5. ~~**Per-feature hotkeys** with a live-preview recorder.~~ Landed —
   client-side, from Settings ▸ Hotkeys and a sidebar row's right-click. Window
   shortcuts, not OS-registered ones; the global half arrives with item 19.
6. ~~**Device bar parity**~~ — landed: the dropdown with its sections, the
   wireless pair/connect sheet, run-on-all for `supportsRunAll`, launching an
   emulator, and disconnecting a wireless device. `supportsRunAll` is a new
   field on the wire; the endpoint parsing stayed daemon-side on purpose. **The
   pull-progress strip did not**: it needs a pull that reports progress, which
   the protocol has no shape for yet, so it moved to the gaps below beside the
   other pull limitations.
7. ~~**The notification surfaces.**~~ Landed — `ToastOverlay` and the history
   panel behind the device bar's bell, with every ported screen converted off
   its inline banner. The Command Log sheet is still outstanding: it needs the
   daemon to record its adb calls, which it does not do yet.
8. **Settings** — landed as a seven-tab window with General, Appearance and
   Privacy doing something and the other four naming what they wait on.
   Appearance carries Theme and Accent (presets · colour well · hex + Reset)
   and the light theme, ported from the asset catalog's own values. Still
   missing: **Background and Text colour**, the **font family and text-size
   scale**, and the **window opacity / blur / grain sliders** — those last
   need a per-platform answer for the blur (see item 15).
9. **The sidebar footer and what it opens** — landed: Manage Features
   (`CatalogView`), About & Feedback, and the gear, plus per-feature "connect
   a device" empty states matching `NoDeviceView`. Still missing: the **role
   picker** (`RolePickerView`, shown on first launch before the tour).
10. ~~**The device-state screens.**~~ Landed — root-status, dev-settings and
    system-restrictions, over four routes. The Developer Options definitions
    travel with their values so no client re-types a title; only the section
    grouping is client-side, with a test that fails if it drifts.
11. ~~**The connection screens.**~~ Landed — wifi, private-dns and
    network-speed. The last needed a second stream topic (`netspeed`), marked
    an increment so a dropped sample is reported rather than leaving a silent
    gap in the chart.
12. ~~**The per-app screens.**~~ Landed — app-info, permissions, meminfo,
    sandbox-browser and app-management, over seven routes. Three device
    answers travel as answers rather than errors: not installed, not running,
    and not debuggable.
13. ~~**Emulators and install-app.**~~ Landed. Emulators is the Mac's screen
    minus its iOS Simulators section, and its Relaunch waits on adb rather
    than `consolePID`, which shells out to a macOS-only `/usr/sbin/lsof`.
    Install App picks through `tauri-plugin-dialog` in the Rust process,
    because a webview drag hands over a `File` with no path — **so it has no
    drag and drop yet**, and the zone says so. It also installs onto one
    device rather than every targeted one, pending run-on-all (item 6).
14. ~~**Deep links and bug report.**~~ Landed, with the Doctor tab alongside
    them since it is one route over a service that already existed. Deep links
    live in the daemon's store — **the same file the Mac app writes**, under the
    shared support dir — so a developer running both has one store; the Mac keys
    it by saved-bundle id and this keys it by package id, so the two sets sit
    side by side rather than merging, and that is the honest state of it until
    this app grows a bundle store. The bug report needed one gated ADBKit
    change: its zip step went through `HostArchive`, so Windows uses the system
    bsdtar while the POSIX argument vector is byte-identical to what it always
    ran.
15. **Window translucency** — the auto-hiding sidebar and the UI zoom have
    landed; translucency has not. `WindowEffects` is already pure-tested in
    ADBKit, so the *math* is done, but the blur needs a per-platform answer
    (Mica on Windows, a compositor effect on Linux) and Settings ▸ Appearance ▸
    Window says so rather than showing sliders that move nothing.
16. **The menu bar** — landed. `src-tauri/src/menu.rs` declares File / Edit /
    View / Tab / Help / Go as a table and Rust forwards each click to the page,
    which is where everything they act on lives (`useMenuCommands`). Two
    invariants are tests rather than intentions: `menu.rs`'s own suite refuses a
    duplicate id, an accelerator bound twice, and a terminal command without
    Shift; `useMenuCommands.test.ts` reads that table and fails on an item with
    no handler *or* a handler with no item. The terminal's six state-dependent
    items grey out when no terminal is open, the way
    `.disabled(!terminalCommandsEnabled)` does on the Mac.

    **The menu owns its accelerators and the page defers.** Both answering one
    would run it twice — Ctrl+W closing two tabs — so `lib/menuKeys.ts` lists
    what the menu binds, `useShellShortcuts` returns early on it, and
    `menuKeys.test.ts` reads `menu.rs` to keep the two lists identical, labels
    included. That is the Mac's own arrangement (`NSMenu` sees a key before any
    view) and it fails in the recoverable direction: a platform that failed to
    deliver an accelerator leaves the command one click away, where a
    double-fire silently destroys work. `reservedCommand` now refuses the
    menu's combinations too, so a feature hotkey can no longer be bound to
    something the platform would shadow.

    Still to come here: **New Window** and **New Window for Device** (they need
    multi-window, item 21), **Find in Terminal / Find Next / Find Previous**
    (the xterm search addon and the Mac's find bar), and **Full View** (⇧⌘F).
    Omitted rather than added as items that do nothing.

    **Three accelerators had to move, each forced rather than chosen:**

    | Mac | here | why |
    | --- | --- | --- |
    | ⌘N New Terminal | Ctrl+**Shift**+N | Ctrl+N is the shell's next-history-line |
    | ⌘D / ⇧⌘D splits | Ctrl+Shift+D / Ctrl+Shift+**E** | Ctrl+D is end-of-input; D is taken by the first axis, and GNOME Terminal splits with E |
    | ⇧⌘W Close Terminal | Ctrl+Shift+W | unchanged in shape, listed because Ctrl+W alone deletes a word |
    | ⌘1–9 Go rows | **Alt**+1–9, Alt+0 | the Mac has ⌘ *and* ⌃ for two meanings; here Ctrl+digit stays the tabs, as it is in every browser |

    ⌘T is *not* a divergence: the Mac's "New Tab" opens the search palette and
    the chosen feature lands in a tab, which is exactly what Ctrl+T has always
    done here. It was nearly "fixed" the wrong way — reading `ADTApp.swift`
    rather than trusting the label is what caught it.

**Known gaps inside work already called done.**

- **Logcat's per-app filter.** Needs a pid → package map the daemon does not
  serve. Matching on the tag instead would be a filter that quietly misses
  lines, which is worse than not having one.
- **The palette lists features, not commands.** There are no custom commands in
  this app yet for it to offer.
- **Drop-to-split is unverified by automation.** Synthetic mouse events do not
  start an HTML5 drag in WKWebView, so every drag path in this app is checked by
  hand. Keep the *decision* a drop makes in `lib/` where it can be tested, and
  only the event wiring uncovered.

- **The File Explorer cannot push.** The Mac drags files in from Finder to
  `adb push` them. Here `dragDropEnabled` is `false` — it has to be, or Tauri's
  native handler swallows the tab drags — so an OS file drop reaches the DOM as
  a `File` with no path, and pushing it would mean reading its bytes and
  staging them somewhere first. The route (`FileExplorerService.push`) is
  already there when someone wants it.

- **No ⌘C / ⌘X / ⌘V in the File Explorer, and no keyboard navigation.** The
  buttons do all of it. The hotkey work in item 5 built the *recorder* and the
  per-feature dispatch, not a per-screen key map, so this is still open — and it
  belongs to the screen rather than the shell, since only the explorer knows
  what a selection is.

- **A pull overwrites a same-named file** in `~/Downloads/Droidective` without
  asking, as `export_text` already does. The Mac asks for a save location; a
  save dialog here is a plugin and a capability for one button. The Crash
  Catcher's Save writes to the same folder under the same rule.

- **A pull cannot be cancelled, and shows no progress.** The Mac's pull
  progress strip lives in the window's safe-area inset and polls the
  destination file's size against the known source size. Here a pull is a
  request that either answers or does not — so the strip is a *protocol* gap
  rather than a UI one, and it is the one part of the device-bar item (6) that
  did not land with the rest.

- **App Info's Pull APK saves to `~/Downloads/Droidective`** rather than asking
  where. Same rule as every other pull here, and the same gap.

- **Memory Usage polls on its own timer rather than through the stream.** Two
  seconds, stopped when the pane unmounts — but a hidden keep-alive tab keeps
  polling, which the Mac pauses via `tabIsActive`. It needs the pane to know
  whether it is the visible one.

- **Settings has no role picker, no Command Log, no Tools and no MCP tab.** Each
  names its blocker in the tab itself. Hotkeys and Doctor have landed.

- **A bug report needs `zip` on a Linux host.** macOS ships it and Windows uses
  the system bsdtar, but on Linux it is a package that may not be installed —
  so the failure names the archiver it could not run rather than blaming the
  device. Writing a zip without an external tool would mean a new dependency for
  one button.

- **No global hotkeys.** The recorded shortcuts are window shortcuts: they fire
  while Droidective has focus, where the Mac registers them with the OS and they
  fire from anywhere. The recorder and the Hotkeys tab both say so. It arrives
  with the Quick Actions panel (backlog 19), which needs the same
  `tauri-plugin-global-shortcut`.

- **A hotkey on a toggle opens it rather than running it.** The Mac flips a
  state override from `activeOverrides`, which it tracks and this app does not,
  so running one would mean guessing a direction and writing it to a device. An
  instant action runs, exactly as on the Mac.

- **Install App has no drag and drop and no live stage line.** The drop is
  backlog 17. The stage line — "Unpacking", "Reading device", "Installing 4
  APKs" — needs the install's `onStage` callback to reach the client, which
  means a stream rather than the request/response route it has; for a large
  `.xapk` that is a minute with no feedback beyond "Installing…". It *does*
  install onto every targeted device now.

- **Emulators lists no iOS Simulators.** Deliberate: `xcrun simctl` is one of
  the two genuinely unportable things. The section is absent rather than
  present and permanently empty.

- **The Crash Catcher's failed empty state has no Try Again button.** Refresh
  sits in the toolbar above it and is never hidden, so a second button beside
  it would be two names for one action.

**Landed: the Terminal.** Real login shells over the daemon's `pty` topic,
drawn by xterm.js. Tabs with a Chrome-style top strip (the Mac's default since
v3.1.0), panes split from the `TerminalSplitTree` model ported to
`desktop/src/lib/terminal.ts` with its ADBKit tests translated alongside it, and
the device on the bar exported as `ANDROID_SERIAL` into each new shell so adb
inside needs no `-s`. Protocol details are in `docs/droidectived-protocol.md`
§5.2. Eight things were learned the hard way and are worth not rediscovering:

- **`TIOCSWINSZ` on the master fails on macOS** with ENOTTY. The window size
  goes on the *slave*, and a terminal whose size never took reports 0×0 — which
  makes every full-screen program draw into nothing.
- **The slave descriptor is held for the pty's whole life.** Closing the last
  slave hangs the master up, so opening one per resize races the child's own
  open and kills the shell before it prints a prompt. Closing it when the child
  is reaped is what makes the master report EOF.
- **`close()` does not interrupt a blocking `read`** on Darwin — it waits for
  it. Since the reader is blocked whenever the shell is idle, closing from
  another thread hung the caller; the reader is woken through a pipe and owns
  closing the master itself.
- **`fork` is required, not `posix_spawn`.** The child needs
  `ioctl(TIOCSCTTY)`, which no spawn file action can express, and without it the
  shell reads a terminal it does not control, takes SIGTTIN and stops — alive,
  echoing every keystroke through the tty driver, running nothing. That failure
  looks exactly like a working terminal until you press Return. The `fork` is in
  C because between fork and exec only async-signal-safe calls are allowed,
  which is why Swift marks `fork` unavailable in the first place.
- **The size is set in one place, the parent.** Setting it in the child raced a
  caller's immediate resize and restored 80×24 about one run in three — only
  under `make verify` load, which is the worst way to find a race.
- **Base64 in both directions, because the payload is bytes.** A pty read ends
  wherever its buffer filled, so a chunk can stop mid-character and a JSON
  string would substitute U+FFFD — on non-ASCII only, which is how that ships.
  Inbound it is the control codes: Ctrl-C is `0x03`, and no JSON string carries
  it. `encodeInput` also avoids `String.fromCharCode(...bytes)`, which throws on
  a paste of a few tens of thousands of characters.
- **A React effect opens the first shell *once*, tracked in a ref.** Guarding on
  "are there no tabs?" opens two: development runs an effect twice and both
  passes see the same empty list, so the feature opened with two ptys and two
  prompts for one click. Visible in a screenshot, invisible in the unit tests.
- **The shell starts in `$HOME`, not the daemon's working directory.** The
  sidecar inherits the launching app's cwd, which in a development build is the
  build folder — so every session began with a `cd`. `Pty.spawn` takes a
  directory and the C shim `chdir`s in the child, unchecked, because a deleted
  directory must not cost someone their terminal.

**Keyboard, and why it diverges.** ⌘T/⌘W/⌘D/⇧⌘D become **Ctrl+Shift+T / W / D /
E**, and the Shift is forced rather than preferred: ⌘ is a modifier no shell has
ever seen, while a bare Ctrl+letter belongs to the program in the terminal —
Ctrl+D is end-of-input, Ctrl+W deletes a word, Ctrl+T transposes. E is the
second split axis because GNOME Terminal already splits with it. The pane
catches these in the capture phase and stops them, so neither xterm nor the
window's own shortcuts see them: the pane with focus wins, which is how every
terminal behaves.

**What the pane still owes the Mac.** Tab *groups* (New Group, Close Group, New
Terminal Here), the right-click context menu, dragging a tab
between panes, drag-and-drop of a file to insert its quoted path
(`TerminalText.droppedPathsInsertion`), the collapsed-rail badges
(`TerminalText.railBadge`), the left-rail alternative to the top strip, the find
bar (⌘F/⌘G), and drag-resizable pane dividers — the panes are equal siblings
today, which is what the split model produces but not what the Mac lets you
adjust. Renaming a tab landed with the menu (double-click it, or ⇧⌘R), as did
Next/Previous Terminal. `TerminalResume`'s reopen-where-you-left-off is deferred on purpose: it
needs the shell's *live* cwd read out of the kernel (`proc_pidinfo` on the Mac,
`/proc/<pid>/cwd` on Linux, nothing on Windows), and restoring tabs without
their directories would look like the Mac and behave differently. **Windows has
no pty here** — ConPTY is a different API, so `openPty` throws and the pane
renders the reason rather than appearing and failing silently.

**The subsystems, after the screens.** These were once listed as "not planned".
They are planned: the goal is that someone moving between the two apps does not
have to relearn anything, and "this one is missing a whole subsystem" fails that
just as badly as a missing button. Each is a release of its own, so they come
after the screens rather than instead of them.

17. **Drag and drop, everywhere the Mac has it.** The shell's tab and sidebar
    drags already work. Still missing: dropping a file from the file manager
    onto the File Explorer to `adb push` it, and dropping an APK/AAB on the
    window to install it. Both need `dragDropEnabled: true`-style handling the
    webview can use — the current `false` is what makes the *tab* drags work,
    so this needs Tauri's native drop **and** HTML5 drag to coexist rather than
    one being turned off for the other. That is the actual engineering problem;
    it is not a reason to skip the feature.
18. **Notifications and their settings.** The Mac posts a native notification
    when a background install finishes, when a watched crash lands, and when an
    update is staged, with a Settings ▸ General switch behind it.
    `tauri-plugin-notification` is the equivalent; the settings pane is item 8.
19. **The Quick Actions panel** — the non-activating global-hotkey mini app:
    the grid of every runnable action, pinned first, custom commands, the
    pick-device interstitial, ⌘⏎ run-on-all. Needs a second Tauri window with
    `alwaysOnTop` + no focus steal, and a global shortcut.
20. **Background mode and the menu bar** — closing the window keeps the app
    resident behind a tray icon, stops the kept-alive sessions, and the global
    hotkey still opens Quick Actions. `tauri-plugin-global-shortcut` plus a
    tray icon.
21. **Multi-window** (`docs/multi-window.md`) — one window per device, the
    per-window workspace split, the Focus / Take Over banner for the exclusive
    features, and the window tint.
22. **The welcome tour** on first run.
23. **The updater** — Sparkle is macOS-only, so this is `tauri-plugin-updater`
    behind the same "Relaunch to update" pill and What's New sheet.
24. **Reactotron** — **the relay has landed; the pane has not.**
    `ReactotronRelay` in the daemon is a NIO WebSocket listener speaking
    upstream's protocol, feeding the portable `ReactotronCommand` decoders that
    ADBKit already shares with the Mac. It reaches a client as the `reactotron`
    stream topic (protocol §5.3), and `POST /v1/reactotron/reverse` opens the
    `adb reverse tcp:9090` tunnel that lets a device find it — with the same
    three retries the Mac uses, because a just-attached device refuses the first
    one.

    Proven against real sockets rather than a fake: thirteen tests drive a
    `URLSessionWebSocketTask` through the handshake, command decoding, frame
    ordering, an undecodable frame, a disconnect, and the port being taken. A
    mock would have proved nothing here — the whole class is a listener, and the
    masking and reassembly are exactly what does not survive being faked.

    **What is left, in order.** Each step stands on its own, which is why they
    are separate — and the pure layers come first because they are the ones that
    can be tested without a renderer, which is all this app has.

    1. ~~**The timeline model, in `lib/`.**~~ **Landed.** Seven modules and 112
       tests: `json.ts` (the sentinel repair and the bounded preview),
       `embedded-json.ts`, `json-search.ts`, `reactotron.ts` (the wire types
       decoded to a tagged event), `reactotron-rows.ts` (badge, headline,
       filterable kind), `reactotron-buffer.ts` (the bounded ring and the frame
       reducer) and `reactotron-filter.ts`. The caps are the Mac's own —
       `ReactotronTimeline`'s 2000 rows and 128 MiB, trimmed oldest-first with
       7/8 hysteresis — for the Mac's reason: a React Native client streams
       frames of arbitrary size, so a count cap alone still lets the retained
       timeline reach gigabytes.

       Three things came out differently from the plan, each on purpose:

       - **`JSONValue` does not come across.** Swift needs a tagged union to
         hold an arbitrary payload; TypeScript already has one. Every *decision*
         in ADBKit's enum is ported, and its tests came with them, but
         `case .string(let text)` is just `typeof value === "string"`.
       - **`JSONTreeLayout` does not come across either.** It is pixel
         arithmetic — SF Mono's 0.6 em advance, a 14 pt disclosure column —
         computing how many characters fit a wrapped line, because SwiftUI's
         `lineLimit` is "a drawing instruction the height doesn't always
         follow". A DOM wraps text natively and `-webkit-line-clamp` collapses
         it correctly, so porting the maths would be porting the workaround, not
         the behaviour. The behaviour — three wrapped lines collapsed, a
         disclosure when the value overflows them — is step 3's, in CSS.
       - **Two fields were added to the `reactotron` envelope** (protocol §5.3),
         because the model is wrong without them: `bytes`, since a client can
         only recover a frame's size by re-serializing every payload as it
         arrives, and `code`, since the Mac's most useful disconnect notice —
         1001 means the app out-produced the connection, log ids not whole
         objects — cannot be written without the close status. Both are proven
         off a real client's frames in `ReactotronRelayTests`.
    2. ~~**The feed pane.**~~ **Landed.** `ReactotronPane` over
       `useReactotron`, with the toolbar's filter/search/sort/clear, the status
       strip, the row, Reactotron's own four-section filter dialog, and the
       waiting screen that carries the `adb reverse` button — because a relay
       listening with no tunnel is the failure that reads as the feature being
       broken. The relay's `bytes` and `code` fields are what let the row bound
       itself and the disconnect notice name its cause.

       It takes a device rather than requiring one, which is the difference from
       every other feed here, so it joins `emulators` and `terminal` in
       `FeaturePane`'s `hostPane` — all three run against *this* machine and
       work with nothing connected. `hints.test.ts` reads the router to decide
       which panes need a connect-a-device line, so it now cuts at `hostPane`:
       `reactotron` is *handed* a device and still must not be on that list.

       Verified live against a stand-in React Native client: the badge tones,
       the API statuses (200/201/304/500/401 and `ERR` for the 0 a failed
       request reports), a logged object previewed as compact JSON, the four
       filter sections offering only the methods the app actually sent, and the
       1001 disconnect notice with its amber edge bar.

       **Two divergences from the Mac, both deliberate.** A headline truncates
       at the end rather than in the middle — CSS has no middle ellipsis, and
       `shortPath` already trims a URL to path plus query, so the interesting
       part survives. And the per-pane split (with its own filter and
       `reactotronPane<n>NewestFirst` per pane) is not here: the split-pane
       model is backlog 20's, so this is one pane whose sort is per tab.

       **One bug found and fixed on the way**, in the relay this depends on: an
       actor is not a lock across a suspension, and both `start` and `stop`
       suspend. A start landing mid-stop saw a nil channel, bound the same port
       and got EADDRINUSE from a socket that was still open — reporting "another
       Reactotron is probably running" with nothing else on the port; a stop
       landing mid-start shut down the event-loop group the bind was waiting on,
       which never completes, wedging the relay for the life of the process. The
       first is what closing a timeline tab and reopening it did, and React's
       double-mount did it on the very first open, so the pane failed every
       time. Fixed with an explicit phase, and pinned by two tests that used to
       hang the suite rather than fail it.
    3. ~~**The detail side.**~~ **Landed.** A row expands into its payload:
       `json-tree.ts` flattens a value into rows (pure, so the two things that
       are easy to get subtly wrong are testable — the render order, and the
       grafting of a stringified payload's rows in the string's place),
       `JsonTree` renders them with find-in-object over `json-search.ts`, and
       `ReactotronDetail` dispatches per event kind. `ReactotronApiDetail` adds
       the whole URL, the status/method/duration lines, the four payload tabs
       and Copy as cURL; `reactotron-curl.ts` is `ReactotronCurl` ported
       decision for decision, including all four repairs — the explicit verb so
       a GET carrying a body does not become a POST, the params a rewritten
       `responseURL` lost, the FormData rebuild, and `--form-string` so a value
       starting with `@` is not read as a file. The copy verbs are
       `reactotron-copy.ts`: line, object, value, and events-as-JSON.

       The ordinal paths are the coupling that makes a search result clickable:
       `json-tree.ts` and `json-search.ts` agree on one scheme — object children
       sorted by key, array items in order — and a test asserts the coupling
       rather than each side alone. The collapse is CSS, not the ported pixel
       maths (see step 1).

       Verified live against **StreamLab**, a real React Native app with
       `reactotron-react-native`, `reactotron-redux` and `reactotron-redux-saga`
       wired up. Two things only a real client showed: its config calls
       `clear()` on startup, which exercised the per-connection clear scoping
       and exposed an empty state that claimed a filter was hiding events when
       there were none; and a real `api.response` body arrives as a *string* of
       JSON, so the Response tab showing ten user objects is `parseEmbedded`
       grafting rather than a wall of escaped text.
    4. ~~**Export and the restarts.**~~ **Landed.** The toolbar's export menu
       saves or copies what is *shown*, so a filter narrows the export as well
       as the view, and both verbs hand over the same thing: the **raw wire
       commands**. Raw rather than enriched, matching the Mac — a badge and a
       headline are this app's rendering choices, and a machine-readable export
       must not invite a script to depend on something free to change.

       The split Restart button restarts on a press and offers the two clearing
       variants behind its chevron: `pm clear --cache-only`, raced against a
       10-second timeout because it never returns on some images (observed on
       the API 36 emulator), and `pm clear`, always behind a confirmation
       because it signs you out. A failed clear is reported rather than fatal —
       the restart proceeds and the wording says which happened.

       Picking the app to restart is `lib/reactotron-restart.ts`, pure and
       tested: the client's own name first (the only signal naming the app that
       is actually talking to us), then the foreground app but *only* when it is
       something we can see installed, then ask. That middle step needed a new
       daemon route, `POST /v1/apps/foreground`, whose absent answer is an
       omitted key rather than an error — the launcher is in front more often
       than any app is.

       Verified live against StreamLab: **the export copied 11 real events** in
       the wire shape with no presentation leaked, and **Restart app moved the
       app's pid** (20890 → 21121) with the notice reading
       "Restarting com.streamlab…" and the strip flipping to "no app
       connected" until it came back.

    **What item 24 still lacks**, both named rather than implied: the Mac opens
    a **picker sheet** when it cannot work out which app to restart, where this
    reports the reason and points at the Apps screen; and the **per-pane split**
    (two timelines side by side, each with its own filter and
    `reactotronPane<n>NewestFirst`) belongs to backlog 20's split-pane model, so
    the sort here is per tab.

    Deliberately later: the **MCP server** over the relay. `ReactotronMCP` is a
    separate package that depends on the Mac-gated `ReactotronServer`, so
    pointing it at this relay is its own change rather than part of the pane.

    One thing to know before debugging it: **two Reactotrons can both bind
    9090.** `portInUse` catches the collision when the address families match,
    but observed on a Mac running both apps, the Mac app held the IPv6 wildcard
    while the daemon took IPv4 loopback and neither failed — so the device's
    traffic goes to whichever owns IPv4 loopback. The Mac has the same property
    against upstream's Electron app, so it is parity, not a regression.
25. **Mirror, screen record, and the video editor.** Smaller than it looks.
    The instinct is "a decode/render stack to write from scratch", but counting
    the files says otherwise: of the eighteen in `ADBKit/Services/Mirror`,
    **thirteen are already portable** — `ScrcpyStreamDecoder`,
    `ScrcpyAudioStreamDecoder`, `ScrcpyControlMessage`, `ScrcpyDeviceMessage`,
    `ScrcpyServerParams`, `ScrcpyServerLocator`, `H264Format`, `H264NAL`,
    `PCMMixdown`, `MirrorAudioFallback`, `ShowTouches`, plus `MirrorWall`'s
    layout maths. scrcpy's own server speaks the same protocol to any host.
    ffmpeg builds for Windows and Linux, but nothing in this repo provisions it
    for either yet: `App/Resources/ffmpeg` is a committed macOS universal binary
    and `scripts/unpack-ffmpeg.sh` verifies it with `lipo`. Screen record and the
    video editor need that gap closed first — the mirror itself does not.

    **Five files are gated, and they are the whole job:**

    | Gated on | What it does | The portable answer |
    | --- | --- | --- |
    | `MirrorTransport` | `Network.framework` socket to the scrcpy server over `adb forward` | NIO **in the daemon**, exactly the move `ReactotronRelay` already made — see below |
    | `MirrorSession` | the orchestrator — gated only because it holds the two below | falls out once they are |
    | `H264Decoder` | VideoToolbox | settled: the webview's `VideoDecoder` — see below |
    | `MirrorAudioPlayer` | AVFoundation playback | the webview's `AudioDecoder`, or a Rust audio crate |
    | `MirrorRecorder` | AVFoundation writer | ffmpeg, once it is provisioned off-Apple |

    **The transport goes in the daemon, not ADBKit.** "The same move as
    `ReactotronRelay`" means its *location* too, and that file's own header says
    why: ADBKit's graph staying free of swift-nio is what lets `swift test` run
    on Windows, so the Apple-only listener stays gated in ADBKit and the
    portable counterpart lives in `DaemonCore`, with everything above it — the
    decoders, `ScrcpyServerParams`, `ScrcpyControlMessage` — as the shared
    portable code. The mirror is the same shape: `MirrorTransport` keeps its
    `#if canImport(Network)` gate for the Mac, and the daemon gets the NIO one.

    **`H264Decoder` is not the decode path**, which makes the job larger than
    its 62 lines suggest. Its own comment says it exists *only to keep the
    latest decoded frame for screenshots*; live display feeds **compressed**
    buffers straight to `AVSampleBufferDisplayLayer`. So the port owes both a
    live present and a still grab. A `canvas` gives both — draw the
    `VideoFrame`, `toBlob()` for the capture.

    **Step 0 is settled: decode in the webview, via WebCodecs `VideoDecoder`,
    behind a runtime probe.** The daemon relays the stream it already parses;
    the canvas is a DOM node, so it inherits the Mirror Wall's grid layout,
    caption-strip drag, breakout and Full View for free. The rejected pair:
    **Rust with a native surface** — no codec dependency, but six native
    surfaces positioned over a scrolling webview and re-synced on every resize,
    reorder and breakout, with Wayland and X11 differing, which is the class of
    thing that works in dev and breaks on real hardware; and **decoded frames
    through the daemon** — 1080p60 raw is ~370 MB/s, which is not a thing to
    send through JSON framing.

    The gating question was whether WebKitGTK has it. **Measured, not assumed** —
    a real `WebKitWebView` on Ubuntu 24.04 (WebKitGTK 2.52.3), asking
    `VideoDecoder.isConfigSupported` directly, by
    `scripts/probe-webkit-webcodecs.sh`, which re-runs the whole table when a
    distro bumps its webview:

    | | `avc1.42E01E` | `avc1.4D401F` | `avc1.640028` | `vp8` |
    | --- | --- | --- | --- | --- |
    | stock `libwebkit2gtk-4.1-0` | ❌ | ❌ | ❌ | ✅ |
    | `+ gstreamer1.0-libav` | ✅ | ✅ | ✅ | ✅ |

    So the API is there — `VideoDecoder`, `VideoFrame`, `EncodedVideoChunk` all
    defined, `isSecureContext` true (wry registers its scheme as secure, in
    `webkitgtk/web_context.rs`) — but **H.264 is a GStreamer plugin the app does
    not ship**, and `gstreamer1.0-libav` is not a dependency of
    `libwebkit2gtk-4.1-0`. Two consequences worth writing down:

    - **The probe is part of the feature, not a diagnostic.** One
      `isConfigSupported` call decides between a working mirror and a precise
      "install *this*" message. Without it the failure is a black rectangle.
    - **Per artifact, the fix differs.** A `.deb` can `depends` on it, the way
      the bundle already depends on `android-tools-adb`. An AppImage has
      `bundle.linux.appimage.bundleMediaFramework`. The tarball that
      `docs/release-channels.md` describes has no package manager at all, so
      there the probe's message *is* the answer. Fedora's decoder lives outside
      the default repos (RPM Fusion, or the Cisco openh264 repo), so a hard
      `Requires:` would make an RPM uninstallable on a stock system — do not add
      one.

    Also worth correcting: on Linux this is **software** decode via
    `avdec_h264`; hardware would need the VA-API plugins on top. Only
    Windows/WebView2 gets hardware decode for free.

    Then, in order: the transport on NIO in the daemon (the `adb forward` tunnel
    *must* be torn down — see the mirror-teardown convention, which the Mac
    learned by leaking one per quit); the session; one tile; then the wall, whose
    layout is already ported. Screen record and the video editor ride the
    session, so they follow rather than lead.

    **The wire is cheap, but its drop policy is not.** The 370 MB/s above is
    *decoded* frames; the encoded stream is scrcpy's bitrate, ~1–8 Mbps, so
    base64 over the existing text protocol costs a third of about a megabyte a
    second and needs no second encoding path in `WebSocketBridge` (whose
    text-only comment gives "no client wants it" as the reason, and this is the
    first client that might). scrcpy sends **Annex-B** with periodic SPS/PPS,
    which is exactly what `VideoDecoder` wants when `description` is absent — no
    AVCC repackaging. What does need thought at the session step:
    `StreamSession`'s bounded buffer drops frames under load, and dropping an
    arbitrary NAL corrupts the picture until the next keyframe, so a video
    stream's drop policy has to be keyframe-aware rather than inherited.

    Two things the Mac learned the hard way and this must not relearn: a
    session's teardown has to be **awaited** at quit or its `adb forward`
    survives the process, and a new session for the same on-screen tile has to
    **adopt the new display layer** or the tile keeps drawing the stopped one.

**What genuinely cannot be ported.** Two features, and only for the reason
that they drive an Apple toolchain rather than a device: `ios-logs` and
`push-notification` are `xcrun simctl` against an iOS Simulator, which does not
exist on Windows or Linux. Everything else on the ⛔ list above is a porting
job, and the checklist now says which.

---

## Per-feature checklists### Input & Clipboard
#### `send-text` — Send Text  ·  🟡 partial
> Type text, URLs, or symbols on the device
- **Kind** `formAction`
- **Note** Runs from the palette; no dedicated screen.
- **Parameters** `text` (text)


### Connection
#### `connection` — Connection  ·  ⬜ todo
> Copy IP, reverse port, disconnect, DNS & wireless setup
- **Kind** `view`
- **Note** Not implemented on macOS either.
- **macOS view** `NetworkConnectionView` — `App/Sources/FeatureDetail/Views/NetworkConnectionView.swift`
- **Must replicate**
  - [ ] button: Forward
  - [ ] label: Copy IP
  - [ ] tooltip: Refresh

#### `emulators` — Emulators & Simulators  ·  🟡 partial
> Launch and stop Android emulators & iOS Simulators
- **Kind** `view`
- **Note** A pane exists; the checklist below is what it is missing.
- **macOS view** `EmulatorsView` — `App/Sources/FeatureDetail/Views/EmulatorsView.swift`
- **Must replicate**
  - [ ] button: Wipe Data
  - [ ] button: Cancel
  - [ ] button: Relaunch
  - [ ] button: Stop
  - [ ] button: Launch
  - [ ] button: Cold Boot (skip snapshot)
  - [ ] button: Wipe Data…
  - [ ] button: Shut Down
  - [ ] button: Boot
  - [ ] label: Refresh
  - [ ] tooltip: Stop the emulator and boot it again

#### `get-ip` — Copy Device IP  ·  🟡 partial
> Get the Wi-Fi IP address and copy it
- **Kind** `instantAction`
- **Note** Runs from the palette; no dedicated screen.

#### `network-speed` — Network Speed  ·  🟡 partial
> Live download & upload throughput with recording
- **Kind** `view`
- **Note** A pane exists; the checklist below is what it is missing.
- **macOS view** `NetworkView` — `App/Sources/FeatureDetail/Views/NetworkView.swift`
- **Must replicate**
  - [ ] label: Export
  - [ ] label: seconds
  - [ ] tooltip: Export the recording as JSON + CSV

#### `private-dns` — Private DNS  ·  🟡 partial
> Off, automatic, or a DNS-over-TLS provider
- **Kind** `view` · **hub member**
- **Note** A pane exists; the checklist below is what it is missing.
- **macOS view** `PrivateDnsView` — `App/Sources/FeatureDetail/Views/PrivateDnsView.swift`
- **Must replicate**
  - [ ] button: Apply
  - [ ] picker: Mode
  - [ ] tooltip: Refresh

#### `reverse-port` — Reverse Port  ·  🟡 partial
> Forward a device port to your machine (Metro 8081)
- **Kind** `formAction` · **hub member**
- **Note** Runs from the palette; no dedicated screen.
- **Parameters** `port` (preset)

#### `wifi` — Wi-Fi  ·  🟡 partial
> Connection details, toggle, saved networks & passwords
- **Kind** `view`
- **Note** A pane exists; the checklist below is what it is missing.
- **macOS view** `WiFiView` — `App/Sources/FeatureDetail/Views/WiFiView.swift`
- **Must replicate**
  - [ ] button: Connect
  - [ ] field: SSID
  - [ ] label: Passwords need root
  - [ ] tooltip: Refresh
  - [ ] tooltip: Copy password

#### `wireless-adb` — Wireless ADB  ·  ⬜ todo
> Connect over Wi-Fi (tcpip + Android 11 pairing)
- **Kind** `view` · **hub member**
- **Note** Not started on Windows/Linux.
- **macOS view** `WirelessAdbView` — `App/Sources/FeatureDetail/Views/WirelessAdbView.swift`
- **Must replicate**
  - [ ] button: Enable Wi-Fi & Connect
  - [ ] button: Pair
  - [ ] button: Connect
  - [ ] button: Disconnect


### React Native
#### `deep-link` — Deep Links  ·  🟡 partial
> Launch and save deep links per app
- **Kind** `view` · **hub member** · **needs an app**
- **Note** A pane exists; the checklist below is what it is missing.
- **macOS view** `DeepLinksView` — `App/Sources/FeatureDetail/Views/DeepLinksView.swift`
- **Must replicate**
  - [ ] button: Delete
  - [ ] button: Cancel
  - [ ] button: Save
  - [ ] field: URL (e.g. myapp://orders/123)
  - [ ] field: Label (optional)
  - [ ] label: Add deep link
  - [ ] label: Delete \(link.label)
  - [ ] tooltip: Launch on device

#### `js-console` — JS Console  ·  ⬜ todo
> Hermes REPL + live console over the Metro debugger
- **Kind** `view`
- **Note** Not started on Windows/Linux.
- **macOS view** `JSConsoleView` — `App/Sources/FeatureDetail/Views/JSConsoleView.swift`
- **Must replicate**
  - [ ] button: Clear Data & Restart
  - [ ] button: Cancel
  - [ ] button: Save as JSON…
  - [ ] button: Copy to Clipboard
  - [ ] button: Show All
  - [ ] button: Hide All
  - [ ] button: Copy
  - [ ] button: Copy as JSON
  - [ ] button: Deselect
  - [ ] button: Run adb reverse for the device
  - [ ] button: Run
  - [ ] field: Find in console
  - [ ] field: 8081
  - [ ] field: Filter
  - [ ] label: Reload JS
  - [ ] label: Clear cache and restart
  - [ ] label: Clear data and restart
  - [ ] label: Restart app
  - [ ] label: adb reverse
  - [ ] tooltip: Reload the JS bundle — what ⌘R in React Native DevTools does
  - [ ] tooltip: Metro dev-server port — varies per app
  - [ ] tooltip: Find & highlight in console (⌘F)
  - [ ] tooltip: Clear the console
  - [ ] tooltip: Choose which log levels to show
  - [ ] search: searchable list
  - [ ] shortcut: "c", modifiers: .command
  - [ ] export: save/export to a file

#### `open-dev-menu` — Open Dev Menu  ·  🟡 partial
> Open the React Native developer menu
- **Kind** `instantAction` · **hub member**
- **Note** Runs from the palette; no dedicated screen.

#### `process-death` — Simulate Process Death  ·  🟡 partial
> Background then kill the app to test restoration
- **Kind** `instantAction` · **hub member**
- **Note** Runs from the palette; no dedicated screen.

#### `react-native` — React Native  ·  ⬜ todo
> Dev menu, reload, deep links, dev server, process death
- **Kind** `view`
- **Note** Not implemented on macOS either.
- **macOS view** `ReactNativeView` — `App/Sources/FeatureDetail/Views/ReactNativeView.swift`
- **Must replicate**
  - [ ] button: Forward
  - [ ] button: Set

#### `reactotron` — Reactotron  ·  🟡 partial
> Live React Native inspector — logs, network, state, custom display
- **Kind** `view`
- **Note** Built, with two named gaps — the relay, the timeline model, the toolbar and filter dialog, the waiting screen with its `adb reverse` button, expandable rows with JSON trees, find-in-object, the API tabs, Copy as cURL, the copy verbs, the filter-aware export and the split Restart button. Missing: the restart's picker sheet, and the per-pane split (backlog 20's model). Backlog 24.
- **macOS view** `ReactotronView` — `App/Sources/FeatureDetail/Views/ReactotronView.swift`
- **Must replicate**
  - [ ] button: OK
  - [ ] button: Retry
  - [ ] button: Add
  - [ ] button: Evaluate
  - [ ] button: All
  - [ ] button: Cancel
  - [ ] button: Done
  - [ ] button: Save as JSON…
  - [ ] button: Copy to Clipboard
  - [ ] button: Copy
  - [ ] button: Copy as JSON
  - [ ] button: Deselect
  - [ ] button: Copy \(selectionCount) Selected Events
  - [ ] button: Copy \(selectionCount) Selected as JSON
  - [ ] button: Copy object
  - [ ] button: Copy line
  - [ ] button: Restore
  - [ ] button: Copy value
  - [ ] button: Send
  - [ ] button: Got it
  - [ ] button: Clear Data & Restart
  - [ ] picker: View
  - [ ] picker: App
  - [ ] field: Path to watch, e.g. user.name
  - [ ] field: e.g. store.getState()
  - [ ] field: Search keys & values…
  - [ ] label: Reverse :9090
  - [ ] label: AI Agents
  - [ ] label: Refresh
  - [ ] label: Dispatch
  - [ ] label: Take Snapshot
  - [ ] label: Pane cleared
  - [ ] label: Clear cache and restart
  - [ ] label: Clear data and restart
  - [ ] label: Restart app
  - [ ] tooltip: Force-stop and relaunch the connected app so it reconnects
  - [ ] tooltip: Run adb reverse tcp:9090 tcp:9090 on connected devices
  - [ ] tooltip: Clear the whole timeline — both panes
  - [ ] tooltip: Split into two panes
  - [ ] tooltip: Clear the timeline
  - [ ] tooltip: Stop watching this path
  - [ ] tooltip: Refresh available values
  - [ ] tooltip: Close without applying
  - [ ] tooltip: Show only requests with this HTTP method
  - [ ] tooltip: Show only responses in this status class
  - [ ] tooltip: Filter the timeline by event type
  - [ ] tooltip: Copy this line (right-click for the full object)
  - [ ] tooltip: Click to view full size
  - [ ] tooltip: Delete this snapshot
  - [ ] tooltip: Reveal in the tree
  - [ ] menu: right-click context menu
  - [ ] shortcut: .cancelAction
  - [ ] shortcut: .defaultAction
  - [ ] shortcut: "c", modifiers: .command
  - [ ] export: save/export to a file

#### `reload-js` — Reload JS  ·  🟡 partial
> Reload the JS bundle (double-tap R)
- **Kind** `instantAction` · **hub member**
- **Note** Runs from the palette; no dedicated screen.

#### `rn-dev-host` — Set Dev Server Host  ·  🟡 partial
> Point the app at a different Metro host
- **Kind** `formAction` · **hub member**
- **Note** Runs from the palette; no dedicated screen.
- **Parameters** `host` (text)


### Screen & Capture
#### `demo-mode` — Demo Mode  ·  🟡 partial
> Clean status bar for store screenshots
- **Kind** `toggleAction`
- **Note** Runs from the palette; no dedicated screen.

#### `mirror-wall` — Mirror Wall  ·  ⬜ todo
> Mirror up to six devices side by side
- **Kind** `view`
- **Note** Not started — several mirrors at once, on the same pipeline as `scrcpy`, so it follows the mirror. Backlog 25.
- **macOS view** `MirrorWallView` — `App/Sources/FeatureDetail/Views/MirrorWallView.swift`
- **Must replicate**
  - [ ] button: Open Each in Its Own Window
  - [ ] button: Arrange Mirror Windows
  - [ ] toggle: Audio from the Focused Device
  - [ ] picker: Columns
  - [ ] label: Devices
  - [ ] tooltip: Pick which devices this wall shows
  - [ ] tooltip: Audio, and breaking tiles out into windows
  - [ ] drag: drag and drop

#### `scrcpy` — Mirror Screen  ·  ⬜ todo
> Mirror and control the device with scrcpy
- **Kind** `view`
- **Note** Not started — the decode/render stack needs writing off Apple (scrcpy's server is portable; VideoToolbox/AVFoundation are not). Backlog 25.
- **macOS view** `ScreenMirrorView` — `App/Sources/FeatureDetail/Views/ScreenMirrorView.swift`
- **Must replicate**
  - [ ] button: Volume down
  - [ ] button: Volume up
  - [ ] button: Mute / unmute
  - [ ] button: Open in a separate window
  - [ ] button: circle
  - [ ] button: square
  - [ ] button: camera
  - [ ] button: Reconnect
  - [ ] toggle: Stream audio (restarts mirror)
  - [ ] toggle: Show touches
  - [ ] toggle: Microphone
  - [ ] tooltip: Audio and touch options
  - [ ] tooltip: Volume, audio, touch, and window options
  - [ ] tooltip: Recording audio — device playback or mic, plus the Mac's mic
  - [ ] tooltip: Mute or unmute what's being recorded

#### `screen-record` — Screen Record  ·  ⬜ todo
> Record via scrcpy — no time limit, with audio
- **Kind** `view`
- **Note** Not started — rides the mirror session, so it follows the mirror. Backlog 25.
- **macOS view** `ScreenRecordView` — `App/Sources/FeatureDetail/Views/ScreenRecordView.swift`
- **Must replicate**
  - [ ] label: Stop & Save
  - [ ] label: Stop

#### `screenshot` — Screenshot  ·  🟡 partial
> Capture the screen and save it to your Mac
- **Kind** `instantAction`
- **Note** Runs from the palette; no dedicated screen.

#### `video-editor` — Video Editor  ·  ⬜ todo
> Trim, rotate, crop, convert & compress video
- **Kind** `view`
- **Note** Not started — needs the mirror pipeline plus the bundled ffmpeg. Backlog 25.
- **macOS view** `VideoEditorView` — `App/Sources/FeatureDetail/Views/VideoEditorView.swift`
- **Must replicate**
  - [ ] label: Open video…


### Device State
#### `animation-scale` — Animation Scale  ·  🟡 partial
> Set animation scales to 0× or 1×
- **Kind** `toggleAction` · **hub member**
- **Note** Runs from the palette; no dedicated screen.

#### `dark-mode` — Dark Mode  ·  🟡 partial
> Toggle system dark mode
- **Kind** `toggleAction` · **hub member**
- **Note** Runs from the palette; no dedicated screen.

#### `dev-settings` — Developer Settings  ·  🟡 partial
> Layout bounds, overdraw, taps, animation scales & more
- **Kind** `view`
- **Note** A pane exists; the checklist below is what it is missing.
- **macOS view** `DeveloperSettingsView` — `App/Sources/FeatureDetail/Views/DeveloperSettingsView.swift`
- **Must replicate**
  - [ ] tooltip: Refresh from the device

#### `device-info` — Device Info  ·  🟡 partial
> Browse and search every device property
- **Kind** `view`
- **Note** A pane exists; the checklist below is what it is missing.
- **macOS view** `DeviceInfoView` — `App/Sources/FeatureDetail/Views/DeviceInfoView.swift`
- **Must replicate**
  - [ ] field: Filter properties…

#### `fake-battery` — Fake Battery  ·  🟡 partial
> Set a fake battery level and unplugged state
- **Kind** `formAction` · **hub member**
- **Note** Runs from the palette; no dedicated screen.
- **Parameters** `level` (slider), `unplugged` (switch)

#### `file-explorer` — File Explorer  ·  🟡 partial
> Browse device storage — copy, move, delete, pull
- **Kind** `view`
- **Note** A pane exists; the checklist below is what it is missing.
- **macOS view** `FileExplorerView` — `App/Sources/FeatureDetail/Views/FileExplorerView.swift`
- **Must replicate**
  - [ ] button: Create
  - [ ] button: Cancel
  - [ ] button: Delete
  - [ ] button: Copy
  - [ ] button: Cut
  - [ ] button: Pull to Mac
  - [ ] button: Get Info
  - [ ] button: Done
  - [ ] toggle: Root
  - [ ] field: Folder name
  - [ ] label: New Folder
  - [ ] label: ..
  - [ ] tooltip: Clear clipboard
  - [ ] tooltip: Browse the whole filesystem as root
  - [ ] tooltip: Refresh
  - [ ] tooltip: Add to selection
  - [ ] menu: right-click context menu
  - [ ] export: save/export to a file

#### `http-proxy` — HTTP Proxy  ·  🟡 partial
> Set or clear the global proxy (Charles, Proxyman)
- **Kind** `formAction` · **hub member**
- **Note** Runs from the palette; no dedicated screen.
- **Parameters** `proxy` (preset)

#### `layout-overrides` — Font & Density  ·  🟡 partial
> Override font scale and display density
- **Kind** `formAction` · **hub member**
- **Note** Runs from the palette; no dedicated screen.
- **Parameters** `fontScale` (slider), `density` (number, optional)

#### `locale` — Change Locale  ·  🟡 partial
> Switch device language for i18n testing
- **Kind** `formAction` · **hub member**
- **Note** Runs from the palette; no dedicated screen.
- **Parameters** `locale` (select)

#### `network-toggles` — Network Toggles  ·  🟡 partial
> Toggle Wi-Fi, mobile data, and airplane mode
- **Kind** `formAction` · **hub member**
- **Note** Runs from the palette; no dedicated screen.
- **Parameters** `wifi` (switch), `data` (switch), `airplane` (switch)

#### `push-notification` — Push Notification  ·  ⛔ n/a
> Deliver a test APNS push to a simulator app
- **Kind** `formAction` · **hub member**
- **Note** iOS Simulator only (simctl push).
- **Parameters** `bundleId` (text), `title` (text), `body` (text), `badge` (number, optional)

#### `simulate` — Simulate  ·  ⬜ todo
> Fake battery, appearance, locale, network & proxy
- **Kind** `view`
- **Note** Not implemented on macOS either.
- **macOS view** `SimulateView` — `App/Sources/FeatureDetail/Views/SimulateView.swift`
- **Must replicate**
  - [ ] button: Reset all overrides
  - [ ] button: Apply
  - [ ] button: Send
  - [ ] button: Set
  - [ ] button: Clear

#### `system-restrictions` — System Restrictions  ·  🟡 partial
> Dev toggles — verifier, hidden APIs, SELinux (root)
- **Kind** `view`
- **Note** A pane exists; the checklist below is what it is missing.
- **macOS view** `SystemRestrictionsView` — `App/Sources/FeatureDetail/Views/SystemRestrictionsView.swift`
- **Must replicate**
  - [ ] button: Remount /system read-write
  - [ ] tooltip: Refresh


### Logs & Diagnostics
#### `bug-report` — Bug Report  ·  🟡 partial
> Zip screenshot + logs + device info + version
- **Kind** `view`
- **Note** A pane exists; the checklist below is what it is missing.
- **macOS view** `BugReportView` — `App/Sources/FeatureDetail/Views/BugReportView.swift`
- **Must replicate**
  - [ ] button: Open in Finder
  - [ ] label: Generate bug report

#### `crash-catcher` — Crash Catcher  ·  🟡 partial
> Browse device crashes — watch, filter, copy for Slack/Jira
- **Kind** `view`
- **Note** A pane exists; the checklist below is what it is missing.
- **macOS view** `CrashView` — `App/Sources/FeatureDetail/Views/CrashView.swift`
- **Must replicate**
  - [ ] button: Clear Buffer
  - [ ] button: Try Again
  - [ ] toggle: Raw log
  - [ ] picker: Kind
  - [ ] picker: Process
  - [ ] field: Filter crashes…
  - [ ] label: Copy
  - [ ] label: Couldn't read crashes
  - [ ] label: No crashes detected
  - [ ] label: Checking…
  - [ ] tooltip: Fetch crashes from the device
  - [ ] tooltip: Show only crashes containing this text
  - [ ] tooltip: Copy this crash for pasting into Slack, Jira, or anywhere
  - [ ] tooltip: Save this crash to a file
  - [ ] tooltip: Clear the device's crash buffer
  - [ ] tooltip: Show the original logcat lines instead of just the messages
  - [ ] export: save/export to a file

#### `ios-logs` — iOS Logs  ·  ⛔ n/a
> Live simulator log stream (unified log)
- **Kind** `view`
- **Note** iOS Simulator only, via simctl — a macOS toolchain, not a device.

#### `logcat` — Logcat  ·  🟡 partial
> Live log stream with search and filters
- **Kind** `view`
- **Note** A pane exists; the checklist below is what it is missing.
- **macOS view** `LogcatView` — `App/Sources/FeatureDetail/Views/LogcatView.swift`
- **Must replicate**
  - [ ] picker: Level
  - [ ] field: Filter lines…
  - [ ] label: All apps
  - [ ] label: Add from installed apps
  - [ ] label: Use app on device screen
  - [ ] label: Add manually / manage…
  - [ ] tooltip: Show only the lines containing this text
  - [ ] tooltip: Find & highlight in the log without hiding lines (⌘F)
  - [ ] tooltip: Export buffer to ~/Downloads/Droidective
  - [ ] tooltip: Clear
  - [ ] tooltip: Stream one app's logs — pick a saved bundle or add a new one
  - [ ] tooltip: Remove tag filter
  - [ ] export: save/export to a file

#### `performance` — Performance Monitor  ·  🟡 partial
> Live CPU, RAM & FPS with recording and export
- **Kind** `view`
- **Note** A pane exists; the checklist below is what it is missing.
- **macOS view** `PerformanceView` — `App/Sources/FeatureDetail/Views/PerformanceView.swift`
- **Must replicate**
  - [ ] button: Export…
  - [ ] button: Stop without exporting
  - [ ] button: Keep recording
  - [ ] picker: Sort
  - [ ] field: Filter by name…
  - [ ] label: Export
  - [ ] label: seconds
  - [ ] tooltip: Start, pause, or resume sampling
  - [ ] tooltip: Stop recording
  - [ ] tooltip: Export the recording as JSON + CSV

#### `root-status` — Root Status  ·  🟡 partial
> Check whether the device is rooted, and how
- **Kind** `view`
- **Note** A pane exists; the checklist below is what it is missing.
- **macOS view** `RootStatusView` — `App/Sources/FeatureDetail/Views/RootStatusView.swift`
- **Must replicate**
  - [ ] label: Re-check


### App Management
#### `aab-convert` — AAB to APK  ·  ⬜ todo
> Convert an Android App Bundle into an installable APK
- **Kind** `view`
- **Note** Not started on Windows/Linux.
- **macOS view** `AabConvertView` — `App/Sources/FeatureDetail/Views/AabConvertView.swift`
- **Must replicate**
  - [ ] button: Choose AAB…
  - [ ] button: Clear
  - [ ] button: Convert to APK
  - [ ] button: Change…
  - [ ] button: Install on device
  - [ ] button: Save a Copy…
  - [ ] button: Reveal in Finder
  - [ ] button: Convert another bundle
  - [ ] label: Connect a device to install onto
  - [ ] export: save/export to a file

#### `apk-decompile` — Decompile APK  ·  ⬜ todo
> Browse Java (jadx) or smali + resources (apktool)
- **Kind** `view` · **hub member**
- **Note** Not started on Windows/Linux.
- **macOS view** `DecompileBrowserView` — `App/Sources/FeatureDetail/Views/DecompileBrowserView.swift`
- **Must replicate**
  - [ ] button: Choose APK…
  - [ ] button: Try again
  - [ ] button: Choose another APK
  - [ ] button: Open APK in jadx-GUI
  - [ ] button: Open decompiled files in Finder
  - [ ] button: Decompile another
  - [ ] picker: Decompiler
  - [ ] label: Find
  - [ ] label: Open externally
  - [ ] tooltip: Find in file (⌘F)

#### `apk-inspector` — APK Inspector  ·  ⬜ todo
> Inspect an APK — manifest, permissions, SDK, signing
- **Kind** `view` · **hub member**
- **Note** Not started on Windows/Linux.
- **macOS view** `ApkInspectorView` — `App/Sources/FeatureDetail/Views/ApkInspectorView.swift`
- **Must replicate**
  - [ ] button: Choose APK…
  - [ ] button: Inspect another…
  - [ ] label: \(title) (\(items.count))
  - [ ] label: Signing

#### `apk-sign` — Sign APK  ·  ⬜ todo
> Zipalign and sign an APK — debug key or your keystore
- **Kind** `view` · **hub member**
- **Note** Not started on Windows/Linux.
- **macOS view** `ApkSignView` — `App/Sources/FeatureDetail/Views/ApkSignView.swift`
- **Must replicate**
  - [ ] button: Choose APK…
  - [ ] button: Choose a different APK…
  - [ ] button: Open in Finder

#### `apk-studio` — APK Studio  ·  ⬜ todo
> Inspect, decompile, recompile, and sign APKs in one place
- **Kind** `view`
- **Note** Not started on Windows/Linux.
- **macOS view** `ApkStudioView` — `App/Sources/FeatureDetail/Views/ApkStudioView.swift`
- **Must replicate**
  - [ ] button: Open another APK
  - [ ] button: Choose APK…
  - [ ] button: Open sources in Finder
  - [ ] button: Sign the rebuilt APK
  - [ ] button: Open in Finder

#### `app-info` — App Info  ·  🟡 partial
> Version, target SDK, size — and pull the APK
- **Kind** `view` · **hub member** · **needs an app**
- **Note** A pane exists; the checklist below is what it is missing.
- **macOS view** `AppInfoView` — `App/Sources/FeatureDetail/Views/AppInfoView.swift`
- **Must replicate**
  - [ ] export: save/export to a file

#### `app-management` — Manage App  ·  🟡 partial
> Open, stop, clear, or uninstall an app
- **Kind** `view` · **hub member** · **needs an app**
- **Note** A pane exists; the checklist below is what it is missing.
- **macOS view** `AppManagementView` — `App/Sources/FeatureDetail/Views/AppManagementView.swift`
- **Must replicate**
  - [ ] button: Cancel

#### `apps` — Apps  ·  🟡 partial
> All installed & system apps — manage, permissions, info
- **Kind** `view`
- **Note** A pane exists; the checklist below is what it is missing.
- **macOS view** `AppsExplorerView` — `App/Sources/FeatureDetail/Views/AppsExplorerView.swift`
- **Must replicate**
  - [ ] button: Clear Data
  - [ ] button: Cancel
  - [ ] button: Uninstall
  - [ ] button: Done
  - [ ] field: Search name, version, or bundle…
  - [ ] label: Open
  - [ ] label: Restart
  - [ ] label: Force Stop
  - [ ] label: Clear Cache
  - [ ] label: Explore files
  - [ ] label: Restore
  - [ ] label: Clear Data
  - [ ] label: Uninstall
  - [ ] tooltip: Refresh
  - [ ] export: save/export to a file

#### `current-activity` — Copy Current Activity  ·  🟡 partial
> Show the foreground Activity right now
- **Kind** `instantAction`
- **Note** Runs from the palette; no dedicated screen.

#### `foreground-package` — Copy Foreground Bundle ID  ·  🟡 partial
> Get the package id of the app on screen now
- **Kind** `instantAction`
- **Note** Runs from the palette; no dedicated screen.

#### `frida-console` — Frida  ·  ⬜ todo
> Set up frida-server or frida-gadget for instrumentation
- **Kind** `view`
- **Note** Not started on Windows/Linux.
- **macOS view** `FridaConsoleView` — `App/Sources/FeatureDetail/Views/FridaConsoleView.swift`
- **Must replicate**
  - [ ] button: Stop frida-server

#### `install-app` — Install App  ·  🟡 partial
> Install an APK, APKS, XAPK, or APKM — drag and drop or pick a file
- **Kind** `view`
- **Note** A pane exists; the checklist below is what it is missing.
- **macOS view** `InstallAppView` — `App/Sources/FeatureDetail/Views/InstallAppView.swift`
- **Must replicate**
  - [ ] button: Choose File…
  - [ ] label: Connect a device to install onto

#### `meminfo` — Memory Usage  ·  🟡 partial
> Live memory usage for an app
- **Kind** `view` · **needs an app**
- **Note** A pane exists; the checklist below is what it is missing.
- **macOS view** `MeminfoView` — `App/Sources/FeatureDetail/Views/MeminfoView.swift`
- **Must replicate**
  - [ ] label: seconds

#### `monkey` — Monkey Test  ·  🟡 partial
> Fire random events to hunt for crashes
- **Kind** `formAction` · **destructive** · **needs an app**
- **Note** Runs from the palette; no dedicated screen.
- **Parameters** `count` (number)

#### `permissions` — Permissions  ·  🟡 partial
> Grant or revoke runtime permissions
- **Kind** `view` · **hub member** · **needs an app**
- **Note** A pane exists; the checklist below is what it is missing.
- **macOS view** `PermissionsView` — `App/Sources/FeatureDetail/Views/PermissionsView.swift`
  - [ ] *(no controls auto-detected — audit by hand)*

#### `sandbox-browser` — Sandbox Browser  ·  🟡 partial
> Browse and pull app files (debug builds)
- **Kind** `view` · **needs an app**
- **Note** A pane exists; the checklist below is what it is missing.
- **macOS view** `SandboxBrowserView` — `App/Sources/FeatureDetail/Views/SandboxBrowserView.swift`
- **Must replicate**
  - [ ] button: Home
  - [ ] label: ..
  - [ ] tooltip: Pull to ~/Downloads/Droidective
  - [ ] export: save/export to a file


### Tool UX
#### `api-client` — API Testing  ·  ⬜ todo
> Send HTTP requests, import Postman collections, assert on responses
- **Kind** `view`
- **Note** Not started on Windows/Linux.
- **macOS view** `ApiClientView` — `App/Sources/FeatureDetail/Views/ApiClient/ApiClientView.swift`
- **Must replicate**
  - [ ] button: OK
  - [ ] button: Discard and Start New
  - [ ] button: Save First…
  - [ ] button: Cancel
  - [ ] button: Import Postman Collection or Environment…
  - [ ] button: Export Everything…
  - [ ] button: Edit Global Variables…
  - [ ] button: Retry
  - [ ] button: Edit Environment
  - [ ] menu: Export Collection…
  - [ ] menu: Export Collection with Secrets…
  - [ ] menu: Run Collection…
  - [ ] field: Enter a URL or paste a cURL command
  - [ ] tooltip: HTTP method
  - [ ] tooltip: Send the request (⌘⏎)
  - [ ] tooltip: Import a cURL command
  - [ ] tooltip: Save this request (⌘S)
  - [ ] tooltip: New request
  - [ ] tooltip: Import, export, and run
  - [ ] tooltip: Active environment
  - [ ] shortcut: .return, modifiers: .command
  - [ ] shortcut: "s", modifiers: .command

#### `custom-commands` — Custom Commands  ·  ⬜ todo
> Your own adb, terminal, and script actions
- **Kind** `system`
- **Note** Not started on Windows/Linux.
- **macOS view** `CustomCommandsView` — `App/Sources/FeatureDetail/Views/CustomCommandsView.swift`
- **Must replicate**
  - [ ] button: Delete
  - [ ] button: Cancel
  - [ ] button: Save
  - [ ] button: Done
  - [ ] button: Add
  - [ ] picker: Show output
  - [ ] picker: Terminal
  - [ ] field: What it does — e.g. Restart app
  - [ ] label: Presets
  - [ ] label: New
  - [ ] label: Delete \(command.name)
  - [ ] label: Added
  - [ ] tooltip: Choose a script or executable to run
  - [ ] shortcut: .cancelAction
  - [ ] shortcut: .return, modifiers: .command

#### `terminal` — Terminal  ·  🟡 partial
> Real shell tabs with the device on ANDROID_SERIAL
- **Kind** `system`
- **Note** A pane exists; the checklist below is what it is missing. Tabs,
  splits and the shell work; the per-tab rename, the tab groups, the context
  menu and dragging a tab between panes do not, and `TerminalResume`'s
  reopen-where-you-left-off is deferred with the cwd read it needs.
- **macOS view** `TerminalView` — `App/Sources/FeatureDetail/Views/TerminalView.swift`
- **Must replicate**
  - [ ] button: Rename
  - [ ] button: Cancel
  - [ ] button: Rename…
  - [ ] button: New Group…
  - [x] button: Split Vertically
  - [x] button: Split Horizontally
  - [x] button: Close Terminal
  - [ ] button: New Terminal Here
  - [ ] button: Close Group
  - [x] button: plus
  - [ ] field: Name
  - [ ] tooltip: Close this terminal (kills its shell)
  - [ ] tooltip: Close this pane (kills its shell)
  - [ ] menu: right-click context menu
  - [ ] drag: drag and drop


<!-- counts: {'done': 0, 'partial': 42, 'todo': 17, 'gated': 2} -->
