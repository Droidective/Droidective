# Desktop parity tracker — Windows & Linux

What the macOS app does, feature by feature, and how far `desktop/` has got.
The goal is not "a Windows client exists"; it is that someone moving between
the two should not have to relearn anything.

**This file is the tracker.** Tick items as they land. Add a line rather than
rewriting one when something turns out to be more work than it looked.

## Status today

| | Count |
| --- | --- |
| ⬜ Not started | 31 |
| 🟡 Partial | 23 |
| ⛔ Not applicable off-Apple | 6 |
| **Total registry features** | **60** |

"Partial" is doing a lot of work in that table: 19 of the 23 are actions that
run from the palette but have no screen of their own, and the four that do have
screens (Apps, Logcat, File Explorer, Crash Catcher) are each missing something
the Mac version offers. Read it as *nothing is finished*, not as *a third is
done*.

## How this was built

The per-feature sections are **generated from the sources**, not written from
memory: the registry as `/v1/features/list` serves it, the id → view mapping
from `FeatureDetailRoute` + `FeatureDetailView.pane`, and the "must replicate"
lists from the actual `Button`/`Toggle`/`Picker`/`Menu`/`TextField`/`.help`/
`.searchable`/`.keyboardShortcut` calls in each SwiftUI view.

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

The sidebar, the tab strip, split panes and the palette have landed, so a screen
ported now opens in a tab, splits, and is reachable from the palette without
being reworked for any of it. Hotkeys and the chrome are still outstanding.

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
- [ ] **Auto-hiding sidebar** (Dock-style).
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
- [ ] **Multi-window** (`docs/multi-window.md`).
- [ ] **⌘= / ⌘- zoom** of the whole UI.

### Finding things

- [x] **Command palette** — Ctrl/⌘ + K or T, and the tab strip's `+`, which
      focuses its pane first so the choice lands there. Arrows move, Enter
      opens, Ctrl/⌘ + P pins. With no query it opens on the pinned list; with
      one, relevance decides and pins are not promoted. Commands are not in it
      yet — this app has no custom commands to offer.
- [ ] **Per-feature hotkeys**, recordable, with a live-preview recorder.
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

- [ ] Device **dropdown** with model, state and enrichment (already close).
- [ ] **Wireless pair & connect sheet** — pairing code, direct `ip:port`, and
      the one-click USB→Wi-Fi bootstrap.
- [ ] **Run-on-all** across connected devices for `supportsRunAll` features.
- [ ] **Launch an emulator** from the bar.
- [ ] **Pull progress strip** in the window's safe-area inset.

### Chrome and feel

- [x] **Per-feature icons.** The daemon drops `FeatureDef.icon` on purpose —
      those are SF Symbol names, which mean nothing off Apple — so
      `desktop/src/lib/icons.ts` pairs each registry id with a lucide glyph
      chosen to read as the same thing the Mac's symbol does. A test fails if
      the daemon serves a feature the table has no entry for, so a new feature
      cannot quietly inherit its neighbour's icon.
- [ ] **Settings** — Appearance (accent colour, custom background/text,
      window opacity / blur / grain), General, Hotkeys, Tools, Privacy, MCP.
- [ ] **Window translucency** — the `.bgRoot`/`.bgSurface` token system, with
      `WindowEffects` already pure-tested in ADBKit. Note the Mac's blur is a
      private CoreGraphics call; Windows and Linux need their own (Mica /
      compositor blur) or the slider limits to opacity.
- [ ] **Light theme** — the asset catalog has both; `desktop/` ported dark only.
- [ ] **Toasts** for action results, instead of an inline banner per screen.
- [ ] **Command Log** — every user-initiated adb call, as
      `CommandLog.userInitiated` records it.
- [ ] **Welcome tour** on first run.
- [ ] **Update pill + What's New** — Sparkle is macOS-only, so this needs its
      own updater on Windows/Linux.
- [ ] **Empty states per feature** ("connect a device") rather than one global
      message.

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
4. **Performance monitor** — a *stream*, not a request: live CPU/RAM/FPS with a
   per-process list, recording, and export.
5. **Per-feature hotkeys** with a live-preview recorder. Client-side, and the
   only shell item left that people will miss daily.
6. **Device bar parity** — wireless pair and connect, run-on-all for
   `supportsRunAll`, launch an emulator, the pull-progress strip.
7. **Toasts and the Command Log** — action results as toasts instead of a banner
   per screen, and every user-initiated adb call recorded the way
   `CommandLog.userInitiated` records it.
8. **Settings** — Appearance (accent colour, light theme), General, Hotkeys,
   Privacy. The light theme is a second set of tokens the asset catalog already
   has.
9. **Manage-features catalog** and per-feature "connect a device" empty states.
10. **The device-state screens** — dev-settings, root-status,
    system-restrictions. Toggle tables over one route each. `root-status` now
    has its route: `/v1/device/root` already carries every signal, not just the
    verdict.
11. **The connection screens** — wifi, private-dns, network-speed.
12. **The per-app screens** — app-info, permissions, meminfo, sandbox-browser,
    manage-app. All hang off the bundle already chosen in Apps.
13. **Emulators and install-app.**
14. **Deep links and bug report.**
15. **Auto-hiding sidebar, UI zoom, window translucency** — `WindowEffects` is
    already pure-tested in ADBKit; blur needs a per-platform answer.

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
  buttons do all of it; the shortcuts wait on the hotkey work in item 5, which
  is where key handling should live rather than one screen growing its own.

- **A pull overwrites a same-named file** in `~/Downloads/Droidective` without
  asking, as `export_text` already does. The Mac asks for a save location; a
  save dialog here is a plugin and a capability for one button. The Crash
  Catcher's Save writes to the same folder under the same rule.

- **The Crash Catcher announces an arrival in a banner, not a toast.** The Mac
  raises one; this app has no toasts yet (item 7), so Watch reports into the
  same banner strip every other screen uses. It stays until dismissed rather
  than fading, which is the one behaviour a banner can offer that a toast
  cannot.

- **The Crash Catcher's failed empty state has no Try Again button.** Refresh
  sits in the toolbar above it and is never hidden, so a second button beside
  it would be two names for one action.

**Not planned.** Multi-window, the Quick Actions panel, the welcome tour, and
the update pill. Each is a whole subsystem, and none of them is why anyone opens
this app. Reactotron stays blocked until the relay's `Network.framework`
listener is ported to NIO; mirror, screen-record and the video editor are
Apple-only by design.

---

## Per-feature checklists

Legend: ⬜ not started · 🟡 partial · ⛔ not applicable off-Apple.

### Input & Clipboard
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

#### `emulators` — Emulators & Simulators  ·  ⬜ todo
> Launch and stop Android emulators & iOS Simulators
- **Kind** `view`
- **Note** Not started on Windows/Linux.
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

#### `network-speed` — Network Speed  ·  ⬜ todo
> Live download & upload throughput with recording
- **Kind** `view`
- **Note** Not started on Windows/Linux.
- **macOS view** `NetworkView` — `App/Sources/FeatureDetail/Views/NetworkView.swift`
- **Must replicate**
  - [ ] label: Export
  - [ ] label: seconds
  - [ ] tooltip: Export the recording as JSON + CSV

#### `private-dns` — Private DNS  ·  ⬜ todo
> Off, automatic, or a DNS-over-TLS provider
- **Kind** `view` · **hub member**
- **Note** Not started on Windows/Linux.
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

#### `wifi` — Wi-Fi  ·  ⬜ todo
> Connection details, toggle, saved networks & passwords
- **Kind** `view`
- **Note** Not started on Windows/Linux.
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
#### `deep-link` — Deep Links  ·  ⬜ todo
> Launch and save deep links per app
- **Kind** `view` · **hub member** · **needs an app**
- **Note** Not started on Windows/Linux.
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
  - [ ] button: Run adb reverse for the device
  - [ ] button: Run
  - [ ] button: Copy
  - [ ] button: Copy as JSON
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
  - [ ] tooltip: Copy this entry (right-click for JSON)
  - [ ] tooltip: Reveal in the tree
  - [ ] search: searchable list
  - [ ] menu: right-click context menu
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

#### `reactotron` — Reactotron  ·  ⛔ n/a
> Live React Native inspector — logs, network, state, custom display
- **Kind** `view`
- **Note** ReactotronServer is a Network.framework listener; needs a portable NIO listener first.

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

#### `scrcpy` — Mirror Screen  ·  ⛔ n/a
> Mirror and control the device with scrcpy
- **Kind** `view`
- **Note** Mirror pipeline is Apple-only (VideoToolbox/AVFoundation); other hosts drive the scrcpy desktop app.

#### `screen-record` — Screen Record  ·  ⛔ n/a
> Record via scrcpy — no time limit, with audio
- **Kind** `view`
- **Note** Records through the mirror session, which is Apple-only.

#### `screenshot` — Screenshot  ·  🟡 partial
> Capture the screen and save it to your Mac
- **Kind** `instantAction`
- **Note** Runs from the palette; no dedicated screen.

#### `video-editor` — Video Editor  ·  ⛔ n/a
> Trim, rotate, crop, convert & compress video
- **Kind** `view`
- **Note** Rides the mirror/ffmpeg export path built on the Apple media stack.


### Device State
#### `animation-scale` — Animation Scale  ·  🟡 partial
> Set animation scales to 0× or 1×
- **Kind** `toggleAction` · **hub member**
- **Note** Runs from the palette; no dedicated screen.

#### `dark-mode` — Dark Mode  ·  🟡 partial
> Toggle system dark mode
- **Kind** `toggleAction` · **hub member**
- **Note** Runs from the palette; no dedicated screen.

#### `dev-settings` — Developer Settings  ·  ⬜ todo
> Layout bounds, overdraw, taps, animation scales & more
- **Kind** `view`
- **Note** Not started on Windows/Linux.
- **macOS view** `DeveloperSettingsView` — `App/Sources/FeatureDetail/Views/DeveloperSettingsView.swift`
- **Must replicate**
  - [ ] tooltip: Refresh from the device

#### `device-info` — Device Info  ·  🟡 partial
> Browse and search every device property
- **Kind** `view`
- **Note** Built. `/v1/device/props` passes `getprop` through untouched; the
  pane adds a summary header, two-segment grouping, search over key and value,
  copy and export.
- **macOS view** `DeviceInfoView` — `App/Sources/FeatureDetail/Views/DeviceInfoView.swift`
- **Must replicate**
  - [x] field: Filter properties…

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

#### `system-restrictions` — System Restrictions  ·  ⬜ todo
> Dev toggles — verifier, hidden APIs, SELinux (root)
- **Kind** `view`
- **Note** Not started on Windows/Linux.
- **macOS view** `SystemRestrictionsView` — `App/Sources/FeatureDetail/Views/SystemRestrictionsView.swift`
- **Must replicate**
  - [ ] button: Remount /system read-write
  - [ ] tooltip: Refresh


### Logs & Diagnostics
#### `bug-report` — Bug Report  ·  ⬜ todo
> Zip screenshot + logs + device info + version
- **Kind** `view`
- **Note** Not started on Windows/Linux.
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
- **Note** iOS Simulator only, via simctl — macOS-only toolchain.

#### `logcat` — Logcat  ·  🟡 partial
> Live log stream with search and filters
- **Kind** `view`
- **Note** A pane exists; the app filter is what it is still missing.
- **macOS view** `LogcatView` — `App/Sources/FeatureDetail/Views/LogcatView.swift`
- **Must replicate**
  - [x] picker: Level
  - [x] field: Filter lines…
  - [ ] label: All apps
  - [ ] label: Add from installed apps
  - [ ] label: Use app on device screen
  - [ ] label: Add manually / manage…
  - [x] tooltip: Show only the lines containing this text
  - [x] tooltip: Find & highlight in the log without hiding lines
  - [x] tooltip: Export buffer to ~/Downloads/Droidective
  - [x] tooltip: Clear
  - [ ] tooltip: Stream one app's logs — pick a saved bundle or add a new one
  - [x] tooltip: Remove tag filter
  - [x] export: save/export to a file

#### `performance` — Performance Monitor  ·  ⬜ todo
> Live CPU, RAM & FPS with recording and export
- **Kind** `view`
- **Note** Not started on Windows/Linux.
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

#### `root-status` — Root Status  ·  ⬜ todo
> Check whether the device is rooted, and how
- **Kind** `view`
- **Note** Not started on Windows/Linux.
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

#### `app-info` — App Info  ·  ⬜ todo
> Version, target SDK, size — and pull the APK
- **Kind** `view` · **hub member** · **needs an app**
- **Note** Not started on Windows/Linux.
- **macOS view** `AppInfoView` — `App/Sources/FeatureDetail/Views/AppInfoView.swift`
- **Must replicate**
  - [ ] export: save/export to a file

#### `app-management` — Manage App  ·  ⬜ todo
> Open, stop, clear, or uninstall an app
- **Kind** `view` · **hub member** · **needs an app**
- **Note** Not started on Windows/Linux.
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

#### `install-app` — Install App  ·  ⬜ todo
> Install an APK, APKS, XAPK, or APKM — drag and drop or pick a file
- **Kind** `view`
- **Note** Not implemented on macOS either.
- **macOS view** `InstallAppView` — `App/Sources/FeatureDetail/Views/InstallAppView.swift`
- **Must replicate**
  - [ ] button: Choose File…
  - [ ] label: Connect a device to install onto

#### `meminfo` — Memory Usage  ·  ⬜ todo
> Live memory usage for an app
- **Kind** `view` · **needs an app**
- **Note** Not started on Windows/Linux.
- **macOS view** `MeminfoView` — `App/Sources/FeatureDetail/Views/MeminfoView.swift`
- **Must replicate**
  - [ ] label: seconds

#### `monkey` — Monkey Test  ·  🟡 partial
> Fire random events to hunt for crashes
- **Kind** `formAction` · **destructive** · **needs an app**
- **Note** Runs from the palette; no dedicated screen.
- **Parameters** `count` (number)

#### `permissions` — Permissions  ·  ⬜ todo
> Grant or revoke runtime permissions
- **Kind** `view` · **hub member** · **needs an app**
- **Note** Not started on Windows/Linux.
- **macOS view** `PermissionsView` — `App/Sources/FeatureDetail/Views/PermissionsView.swift`
  - [ ] *(no controls auto-detected — audit by hand)*

#### `sandbox-browser` — Sandbox Browser  ·  ⬜ todo
> Browse and pull app files (debug builds)
- **Kind** `view` · **needs an app**
- **Note** Not started on Windows/Linux.
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

#### `terminal` — Terminal  ·  ⬜ todo
> Real shell tabs with the device on ANDROID_SERIAL
- **Kind** `system`
- **Note** Not started on Windows/Linux.
- **macOS view** `TerminalView` — `App/Sources/FeatureDetail/Views/TerminalView.swift`
- **Must replicate**
  - [ ] button: Rename
  - [ ] button: Cancel
  - [ ] button: Rename…
  - [ ] button: New Group…
  - [ ] button: Split Vertically
  - [ ] button: Split Horizontally
  - [ ] button: Close Terminal
  - [ ] button: New Terminal Here
  - [ ] button: Close Group
  - [ ] button: plus
  - [ ] field: Name
  - [ ] tooltip: Close this terminal (kills its shell)
  - [ ] tooltip: Close this pane (kills its shell)
  - [ ] menu: right-click context menu
  - [ ] drag: drag and drop


