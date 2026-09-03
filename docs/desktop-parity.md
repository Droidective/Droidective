# Desktop parity tracker — Windows & Linux

What the macOS app does, feature by feature, and how far `desktop/` has got.
The goal is not "a Windows client exists"; it is that someone moving between
the two should not have to relearn anything.

**This file is the tracker.** Tick items as they land. Add a line rather than
rewriting one when something turns out to be more work than it looked.

## Status today

| | Count |
| --- | --- |
| ⬜ Not started | 4 |
| 🟡 Partial | 55 |
| ⛔ Not applicable off-Apple | 2 |
| **Total registry features** | **61** |

"Partial" is doing a lot of work in that table: 19 of the 52 are actions that
run from the palette but have no screen of their own, and the 33 that do have
screens are each missing something the Mac version offers. Read it as *nothing
is finished*, not as *most of it is done*.

The four not started are `frida-console`, `api-client`, and the two that are
**blocked rather than unscheduled**: `screen-record` and `video-editor` both
need ffmpeg provisioned for Windows and Linux, and this repo only commits a
macOS universal binary.

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

The shell came first, and it has landed: sidebar, tab strip, split panes,
palette, per-feature hotkeys, UI zoom, device bar, menu bar, toasts. A screen
ported now opens in a tab, splits, takes a shortcut and reports through the
toasts without being reworked for any of it. Thirty-three screens exist.

### What is next, in order

The ordering principle is **risk before features**. Thirty-three screens have
been built for two operating systems that **nobody has ever launched the app
on** — CI compiles both and runs the unit suites, and that is all. Every screen
in this document is theoretical until that is not true, so validating it comes
before adding to it.

1. ~~**Run the app on Linux, and keep it running.**~~ **Landed — and it did not
   come up.** `scripts/smoke-desktop-linux.sh` now runs on every PR
   (`desktop-linux-smoke`, over the `.deb` `desktop-native` bundles), installs
   the package in a bare `ubuntu:24.04` so apt resolves its declared Depends and
   nothing else, launches it under Xvfb, drives the palette, and photographs
   both frames. Everything it asserts is fatal; the first version of the script
   printed `WARNING: no droidectived process` and exited 0, which is how it
   would have passed over the bug below.

   **The first launch found two.** Both are the same shape — a build machine has
   a toolchain and a user's machine has nothing:

   - **The daemon could not start at all.** `droidectived` was dynamically
     linked against the Swift runtime, so it died at exec with
     `libswiftCore.so: cannot open shared object file` and the app came up
     showing "droidectived would not start" with all thirty-three screens
     behind it. `build-daemon-sidecar.sh` now passes `--static-swift-stdlib` on
     Linux (and only there: macOS ships the runtime, and Swift on Windows has no
     static stdlib to link).
   - **Then it could not resolve `libcurl.so.4`.** FoundationNetworking links
     it, `ubuntu:24.04` does not ship it, and no Tauri dependency pulled it in.
     Declared as `bundle.linux.deb.depends`; `libcurl4t64` provides `libcurl4`,
     so the plain name resolves on Debian and Ubuntu alike.

   - **And then it came up and did nothing.** With the daemon alive, the app
     painted its whole shell and sat there: "0 features", "Looking for
     devices...", no error. The daemon was serving all 61 features to `curl`
     from inside the same container, so the fault was above it. Tracing the
     two commands the client makes at startup found `list_features` returning
     61 while **`list_devices` never returned at all** - `Promise.all` waits
     for both, so the whole session hung on one of them.

     The cause is in ADBKit: `adb devices` on a machine whose adb *server* is
     not yet running forks that server, prints two lines, and exits - and on
     Linux corelibs then **never reaps the child**. It sits as a zombie,
     `Process.terminationHandler` never fires, and the continuation waiting on
     it is suspended for the life of the process. The watchdog is no escape
     either: its only recovery is terminating a process that is still running,
     and this one is already gone. `SystemProcessRunner` now watches for the
     exit itself with `waitpid(WNOHANG)` on a reaper thread - off-Darwin only,
     since this is a corelibs gap and the Mac is the shipping app. The cold
     call went from **hanging past 60 seconds to 0.185 s**.
     `aChildThatForksAGrandchildAndExitsIsStillReaped` is the regression test,
     and nothing else in that suite produced the shape.

     **Windows had it too, and worse than it first read.** It was written down
     as "slow, not dead": a synthetic stand-in returned after 30 s — the
     grandchild's own lifetime — and the test was gated off the platform for
     destabilising a neighbour. Both readings were wrong.
     `AdbColdStartProbeTests` times the real call on a real Windows host, and
     its first run **hung**: thirty minutes in CI against ten for the whole
     suite beside it, until it was cancelled by hand. adb's grandchild is a
     *server*, and a server does not exit — so what looked like a bounded 30 s
     wait on a sleeping stand-in is an unbounded one on the thing itself. The
     Windows app's "0 features" launch screenshot was the Linux bug exactly,
     and one frame could not say so.

     `ExitWatcher` — the reaper, renamed for having two implementations — waits
     on the process handle there. `WaitForSingleObject` is signalled the moment
     the child exits, inherited pipes and surviving grandchildren included, and
     holding that handle open is also what stops the pid being recycled under
     the kill paths, which is the hazard its POSIX half has to guard against.
     The neighbour blamed for interference — `timeoutKillsAndFlags`, reading
     30.3 s — was never interference either: `sleepForever` on Windows *is* a
     30 s ping, so a test stuck at exactly its length was the same missing exit
     report seen from the other end. Both run on Windows now. The two pipe
     drains also became concurrent, since a grandchild inherits the pair and
     waiting them out one after the other doubled the only case the grace
     exists for.

   **It works now**, and the smoke shows it rather than asserting it: the
   window comes up with 42 features and a device bar that has finished
   looking, and driving Ctrl+K -> "terminal" -> Enter opens a Terminal tab
   with a live shell prompt drawn by xterm.js over the daemon's pty. The whole
   stack - IPC, daemon, pty, stream, renderer - in one photograph.

   *And it settled the mirror.* `scripts/probe-webkit-webcodecs.sh` no longer
   only asks `isConfigSupported`, which is a *claim* WebKitGTK answers out of
   the GStreamer registry: it now encodes a real Annex-B keyframe with ffmpeg
   and decodes it. Stock Ubuntu 24.04 throws `No decoder found for codec
   avc1.42C029`; with `gstreamer1.0-libav` the same frame comes back as a
   **64x64 `VideoFrame`**. So the decoder is real, the `.deb`'s Recommends puts
   it there by default, and `codecSupport()`'s message is the fallback rather
   than the plan. What is still unwatched is a *device* stream painting into a
   canvas, which needs a device the container does not have.
2. ~~**Do the same for Windows, as far as it goes.**~~ **Landed, and it does not
   go as far.** `scripts/smoke-desktop-windows.ps1` silently installs the NSIS
   package, launches the app, and asserts the three things the Linux run proved
   were worth asserting: the app is still up after thirty seconds,
   `droidectived` is running beside it, and **the first `/v1/devices/list`
   comes back inside ten seconds**. That last one is where the Windows hang was
   finally caught and where it is now kept caught: on the `v3.10.0-beta.3` tag
   the installed app answered it in **0.2 s**, against never. No device is
   needed and none is present — an empty answer is fine, an answer *arriving*
   is the assertion. The window title and a screenshot are *reported* rather
   than asserted — a runner's session may have no interactive window station,
   and failing on that would be failing on a property of the runner rather than
   of the app.

   Two limits, both real. There is **no Windows container**, so it runs on the
   runner itself: the machine already has whatever the toolchain left behind,
   so a missing runtime dependency — the exact class of bug the Linux smoke
   caught twice — can still hide. And it runs **only on a beta tag**, in
   `desktop-artifacts`, because that is the only job that builds a Windows app
   at all; a Swift toolchain on Windows is far too slow to put on every push.
   Late feedback about whether the thing starts still beats none.

   What stays on [`manual-verification.md`](manual-verification.md): a person
   launching it on a real desktop.
3. ~~**The three remaining hubs** — `react-native`, `simulate`, `connection`.~~
   **Landed**, each the Mac's view section for section: the RN hub's quick-action
   cards, its two Metro paths and the deep links; Simulate's battery,
   appearance, layout, locale, network and proxy; Connection's live Wi-Fi and IP,
   the port reverse, and the wireless and Private DNS sections *themselves* —
   the same components their standalone screens render, as on the Mac, where
   each of those screens is one `HubColumn` around the section the hub embeds.
   Nothing re-implements an action: every control hands its values to the
   `run_action` route a generated form already uses (`useHubAction`).

   All four hubs now fold their members away, so the sidebar matches the Mac's
   — except `apps`, whose members stay standalone because this app's Apps
   explorer has no detail pane to fold them into. `hubs-panes.test.ts` reads the
   router and fails on a hub added to `IMPLEMENTED_HUBS` without one, which is
   the failure that would stranded its members behind a screen that does not
   exist.

   **Two things the Mac's screens have and these do not**, both named on the
   screen rather than quietly missing: Simulate's push-notification section is
   `simctl` (absent, as the Emulators screen's simulator section is), and its
   "Reset all overrides" reads `activeOverrides`, a reconciled record this app
   does not keep — so the two toggles say they apply on flip rather than
   implying they read the device.

   **It also fixed a bug this exposed.** The three hubs were `implemented:
   false` on the wire: the Mac routes a `.view` through `FeatureDetailRoute` and
   never consults `FeatureEngine.implementedIDs`, so their absence from that set
   was invisible there — but the daemon serves it as the wire's `implemented`
   flag, and a client that believes it hides screens the Mac ships. Install App
   was in the same state and had been **missing from this app's sidebar while
   having a working pane**. `everyRoutedViewIsImplemented` in AppTests now fails
   on the next one.
4. ~~**Logcat's app filter.**~~ **Landed.** `POST /v1/logcat/pid` resolves a
   package to its process id, and the `logcat` subscription carries a `pid` that
   becomes `adb logcat --pid` — so the *device* filters, and the ring buffer
   holds only that app's lines. A client-side filter over a mixed buffer would
   let a chatty neighbour evict the lines being looked for before anyone saw
   them, which is why the Mac does it this way too.

   The loop around it is the Mac's, and it is the part worth getting right:
   an app that is not running is waited for rather than silently streaming the
   whole device, and the pid is re-read on a timer because `logcat --pid` goes
   silent *forever* when an app relaunches under a new one. Both decisions are
   `lib/logcat-app.ts`, pure and tested; the hook is the timer and the request.
   The toolbar says which of the two empty feeds you are looking at — "waiting
   for" and "that app is quiet" are indistinguishable otherwise.

   It follows the Apps tab's selection rather than a bundle store this app does
   not have, which is the one selector every other per-app screen here already
   uses — and the Mac's own arrangement, since it hides the device bar's bundle
   pill on this screen for the same reason. "App on screen" adopts the
   foreground app, as `adoptForegroundApp()` does.

   The subscription's `filter` field went with it: it was documented in the
   protocol as a level filter and had never been read by anything.
5. ~~**Notifications** (backlog 18).~~ **Landed** — and smaller than it looked,
   because the Mac does not decide per event: `SystemNotifier` mirrors the
   toasts already marked important, so an install finishing and a watched crash
   landing both arrive without either screen knowing a tray exists. No Settings
   switch: the Mac has none (see the Look section).

   **The Mac has since dropped the backgrounded condition**, so this is a
   difference to close. Every important toast now posts, foreground included: a
   5s overlay in the corner of one window is missable whether or not that
   window is frontmost, and Notification Center is the only record that
   outlives it. Drop the `isFocused()` gate, and mirror the two things that
   came with the change — a click opens the in-app notification bar on the row
   the notification came from (`AppCore.revealNotifications`, keyed by the
   `AppNotification.id` carried in `userInfo`), and that id doubles as the
   request identifier so a re-post replaces its notification instead of
   stacking a second copy. Note the trap the Mac hit: macOS suppresses a
   notification while the posting app is frontmost unless the delegate's
   `willPresent` says otherwise, so check whether the tray has an equivalent
   before concluding the posts are not firing.
6. ~~**Background mode and the tray** (20), then **Quick Actions** (19).~~
   **Landed**, in that order and for the stated reason. Closing the window hides
   the app, stops the work that was only running because a window was open, and
   leaves a tray icon whose menu is `MenuBarView` row for row. The recorded
   shortcuts are now registered with the OS, so they fire from whatever app you
   are in — the divergence the recorder used to apologise for. And the panel
   itself: a search field over a five-across grid, arrows moving it while the
   query is being typed, the destructive second press, the pick-device
   interstitial, form actions in place.

   **Two conditions the Mac does not need**, both forced: a hidden window is
   only offered where a tray icon actually exists (a Linux session can decline
   to give one, and hiding a window nobody can bring back is not a mode), and
   the Mac's "Show menu bar icon" switch is absent, because turning the tray off
   while the window is hidden would be exactly that trap. The panel is also not
   a non-activating `NSPanel` — no such window exists on Windows or Linux — so
   it takes focus and hands it back by hiding.

   **The pick-an-app step has landed**: a `needsBundle` action asks which app,
   after its device is settled — "which app" is a question about a particular
   device, so asking the other way round would offer a list that might not
   exist on the one finally chosen. It lists the device's *user* apps, where
   the Mac lists its saved bundles first; there is no bundle store here yet.
   Landing it uncovered an older bug: only one screen can be in front and the
   panel checks the form first, so a form action that then pushed an
   interstitial left the form up with the interstitial behind it — a form
   action with two devices connected had been a Run button that did nothing.

   **What the panel still does not have**: Manage Apps, Emulators, Install APK,
   and the resume-where-I-left-off window. The first three are screens of their
   own; the last is a preference over behaviour this panel does not have, since
   it is created on demand rather than kept alive behind the app.
7. ~~**API Testing** (`api-client`)~~ — **landed.** Collections, folders,
   environments, `{{variable}}` scopes with the unresolved ones surfaced rather
   than sent, assertions, the runner, six code-generation targets, Postman
   import and export, and a cURL paste that parses back. The collection runner
   is deliberately *not* a daemon route: the client walks the tree and sends one
   request at a time, so progress is live and Stop is instant.
8. ~~**ffmpeg for Windows and Linux**~~ — **screen record landed;** the video
   editor has not. Off Apple this could not be provisioned and reused: the Mac
   records through the Apple-gated mirror media stack, so the daemon grew its
   own pipeline — `FfmpegPipe` feeding the scrcpy H.264 stream to `ffmpeg -f
   h264 -i pipe:0 -c:v copy`, with segmented pause/resume through the concat
   demuxer. ffmpeg itself is now a managed download (BtbN's builds, digest
   verified, `.tar.xz` on Linux and `.zip` on Windows) rather than a bundled
   binary, which is also what unblocked Settings ▸ Tools.
9. ~~**Multi-window** (21)~~ — **landed.** One window per device, each with its
   own tabs and its own `localStorage` key, the exclusivity banner with Focus
   and Take Over, and a tinted device icon on every window after the first.
   Two traps worth keeping in mind: the window's label must be in the URL it is
   opened with, or both windows read as `main` and share one layout; and Tauri
   2's `Emitter::emit` reaches *every* listener whatever object it is called on,
   so a targeted event needs `emit_to`.
10. ~~**Drag and drop** (17)~~ — **landed, and on the manual list.** An APK or
    app bundle dropped anywhere installs; anything else dropped on the File
    Explorer is pushed to the directory it is showing. The dropped *bytes* are
    staged through a Rust command rather than the path being read from Tauri's
    own drop handler, and that is forced rather than chosen: turning that
    handler on stops every HTML5 drag in the page working — the tab strip, the
    sidebar, the mirror wall — which was checked rather than assumed. One file
    copy against rewriting every in-app drag onto pointer events. The gesture
    itself is in `docs/manual-verification.md`, because no synthetic event on
    this platform can produce a drag.
11. **The polish.** Window translucency (15) and the role picker (9) have
    landed; the welcome tour (22) has not, and the updater (23) is blocked on a
    signing keypair rather than on effort — `tauri-plugin-updater` needs one
    whose private half lives in a GitHub secret, which is the maintainer's to
    create. Settings ▸ MCP is the remaining tab, and it is a port task of its
    own size rather than a checkbox: `ReactotronMCP` is `#if
    canImport(Network)`-gated end to end and taps ADBKit's Apple-only
    `ReactotronServer`, so serving it off Apple means feeding
    `McpCommandStore` from the daemon's NIO relay instead.
12. **`frida-console`**, last of the real features: it needs a rooted device to
    verify, which makes it the hardest to be sure of and the least used.

Not in this list, and not scheduled: `ios-logs` and `push-notification`, which
drive an Apple toolchain rather than a device.

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
- [x] **Drops from outside the app** — a file dragged from the file manager
      onto the File Explorer (`adb push`), and an APK or app bundle dropped
      anywhere on the window to install it. The two coexist rather than one
      being switched off for the other: `dragDropEnabled: false` stays, so the
      in-app drags keep working, and the dropped *bytes* are staged through a
      Rust command instead of Tauri handing over a path. The gesture is on the
      manual list — no synthetic event can produce a drag in a webview.
- [x] **Multi-window** (`docs/multi-window.md`) — one window per device, its
      own tabs and layout key, the Focus / Take Over banner, and a tinted
      device icon on every window after the first.
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
      occur. They are **registered with the OS**, so they fire from whatever app
      you are in and from a window closed into the tray; a combination another
      app already holds is refused by the platform, and the window listener goes
      on answering for exactly those, because a shortcut that then worked
      nowhere would be worse than one that works in the window. And a **toggle
      opens rather than running** — the Mac flips it from the override state it
      tracks, which this app does not keep, so it would have to guess a
      direction and write it to a device. The combinations the shell owns (⌘K/T/W/\\/,/1–9) are refused with
      the name of the command that holds them, because a window shortcut cannot
      outrank the shell the way an OS-registered one does.
- [x] **Global hotkey → Quick Actions panel** — the mini app: the grid of every
      runnable action with the pinned ones leading, the custom commands, the
      "Open in Droidective" list, the pick-device interstitial and its All
      devices row for a `supportsRunAll` feature. Recorded in Settings ▸ Hotkeys
      ▸ Global, and also the tray's first item. **Not** non-activating: no such
      window exists on Windows or Linux, so it takes focus and gives it back by
      hiding. Manage Apps, Emulators, Install APK and the pick-bundle
      interstitial are still to come.
- [x] **Pinned / favourites** — a Pinned section leading the sidebar and the
      palette's empty-query list, pinned from either. Members are lifted out of
      their categories rather than listed twice, as `enabledFeatures(in:)` does
      on the Mac. Quick Actions does not exist here yet to share them with.
- [x] **Manage features catalog** — turn features off; everything is on by
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

- [~] **General** — Background (the keep-running switch, with its reason when
      no tray exists), Quick Actions (close-after-run, and the per-action list
      that keeps one out of the panel) and Tray (which features the menu lists)
      all work. **Still waiting:** the role picker, Open at login and the
      updater, which the tab names rather than showing switches that control
      nothing. The Mac's "Resume where I left off" is deliberately absent — see
      the panel's entry.
- [x] **Appearance** — Theme (light/dark/system) and Accent as presets *and* a
      colour well *and* a hex field with Reset, plus the light theme itself
      and the low-contrast warning — and the same three ways for **Background**
      and **Text**, with the scheme following a custom background. A Window
      section carries the sidebar mode and the UI size. **Still missing:** Font
      family and the text-size scale, the Window opacity/blur/grain sliders
      (which the section names as not ported), and the Developer self-metrics
      overlay.
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
- [x] **Tools** — the managed-tool store: download, size, remove, upgrade.
      ffmpeg and the Temurin JRE join the catalogue off Apple, since neither is
      bundled there.
- [x] **Hotkeys** — every feature in sidebar order with a live-preview
      recorder, plus the Mac's "Hidden features with shortcuts" section, since a
      feature turned off in the catalog keeps its shortcut and would otherwise
      be unbindable. The Global pair names what it waits on rather than showing
      a recorder that controls nothing.
- [ ] **MCP** — shown conditionally on the Mac; the Reactotron MCP server's
      switches. Reactotron itself has landed, so that is no longer the blocker:
      the `ReactotronMCP` package is `#if canImport(Network)`-gated end to end
      and taps ADBKit's Apple-only `ReactotronServer`, so serving it off Apple
      means feeding `McpCommandStore` from the daemon's NIO relay instead. A
      port task of its own size rather than a checkbox — the tab says so
      instead of showing switches that control nothing.

#### Panels and sheets

- [x] **Notification panel** (`NotificationPanelView`) — a persistent right
      column of the important notifications, toggled by the **bell in the
      device bar**, with its own empty state.
- [x] **Toasts** (`ToastOverlay`) — top-trailing, per action result, with a
      level and an optional Show in folder. Every ported screen was converted
      off its inline banner.
- [ ] **Command Log** (`CommandLogView`) — every `CommandLog.userInitiated`
      adb call, opened from Privacy.
- [x] **Role picker** (`RolePickerView`) — shown on first launch, and
      re-openable from Settings ▸ General, which also names the role in effect.
      The catalogue is served (`/v1/features/roles`) rather than re-listed in
      TypeScript: a role is six lists of feature ids, and a second copy would
      drift the first time a feature joined one.
- [x] **Manage Features catalog** (`CatalogView`) — everything on by default;
      this is for turning things off, with a right-click on a group header for
      the whole group.
- [x] **About & Feedback** — the `about` tab: version, Report an Issue, Request
      a Feature, GitHub, Releases.
- [ ] **Welcome tour** (`TourView` + `TourDemos`) — skippable, ending on the
      two Quick Actions pages and the confetti finale. The Mac's demo stage
      plays recordings of the *Mac* app, which would be the wrong window
      chrome and the wrong modifier keys here, so the six drawn fallbacks are
      what a port would follow.
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

- [x] **File** ▸ New Window, New Window for Device.
- [x] **Terminal** ▸ New, Split Vertically, Split Horizontally, Close, Rename…,
      Next, Previous.
- [x] **Tab** ▸ New Tab, Close Tab, Next, Previous. **Show Tab 1–9** is instead
      Alt+1–9 on the *sidebar*, matching what those keys do in this app.
- [x] **View** ▸ Toggle Sidebar and the zoom trio.
- [x] **Edit** ▸ Find Feature, Manage Features. **Find in Terminal** is not
      here: the terminal's find bar is Ctrl+F inside the pane, and a menu item
      that only worked while one particular tab was focused would be a menu
      item that is usually dead.
- [x] **Help** ▸ Report an Issue…, Request a Feature…, Droidective on GitHub,
      Release Notes, About Droidective.

`lib/menuKeys.ts` mirrors the Rust table and `menuKeys.test.ts` fails if the
two disagree, so a relabelled item cannot leave a stale accelerator behind.

#### Look

- [x] **Window translucency** — Opacity and Grain are the Mac's sliders, with
      the Mac's arithmetic ported to `lib/window-effects.ts` and checked
      against `WindowEffectsTests`' own numbers; the tokens are re-expressed at
      an alpha in `lib/glass.ts` (root carries the opacity, lifted surfaces only
      the contrast step) and 100% hands the palette back untouched, so an
      untouched window renders exactly as before. Grain is an SVG
      `feTurbulence` film rather than a Metal shader, portalled outside the zoom
      transform so zoom does not magnify the specks. **Two divergences.** Blur
      is a *switch*, not a slider — no platform exposes a radius (Windows has
      Acrylic and Mica, both on-or-off), and a slider with two positions would
      be a worse lie than a switch; `src-tauri/src/glass.rs` picks Acrylic on
      Windows, since Mica is 11-only and tints rather than blurs. And **Opacity
      is unavailable on Linux entirely**: the app draws its own GTK menu bar
      above the webview there, and that strip has nothing to paint itself on
      over a transparent window — the desktop shows through File, Edit and
      View, which is exactly what shipped in beta.4 before a user photographed
      it. `tauri.linux.conf.json` turns the window transparency off,
      `lib/platform.ts` stops the page painting itself translucent to match, a
      Rust test fails if the two configs drift, and the Linux smoke job now
      counts pure-black pixels inside the window so the next hole of this shape
      fails CI instead of reaching somebody. Grain still works on Linux.
- [x] **Light theme** — ported from the asset catalog's own colorset values,
      applied as CSS custom properties on `:root` so every existing token
      follows it.
- [x] **Custom accent**, with the low-contrast warning, and **Background and
      Text colour** beside it: the Mac's eight presets, a colour well, a hex
      field and a Reset. `BackgroundPalette` and `TextPalette` are ported to
      `lib/background.ts` and tested against the stock steps — fed `#1A1A1A` the
      derivation has to land on the asset catalog's own `#232323` and `#333333`,
      or a custom colour would not have the hierarchy the stock one does. The
      **luminance-following scheme** came with them: a custom background decides
      light or dark, and the Theme picker greys out saying so, exactly as on the
      Mac.
- [x] **The ⌘= / ⌘- zoom.** **Font family and the text-size scale are still
      missing** — the zoom scales everything together, where the Mac also lets
      the text size move on its own.
- [x] **Empty states per feature** ("connect a device") — the Mac's
      `NoDeviceView` shape, with its per-feature copy table ported.
- [x] **Native notifications** — an important result posts one, which is
      `SystemNotifier`'s rule rather than a list of events: `postToast`
      mirrors the toasts already marked important, so a crash caught while
      watching and a finished install arrive without either screen knowing
      about the tray. The titles are its titles (all four now lead with the
      app name), a failure carries the sound, and a batch can opt its members
      out and post one summary — which the install does.

      **There is no Settings switch, because the Mac has none.** This entry
      used to promise one; reading `SettingsView.swift` rather than trusting
      the note is what found that the Mac leaves the choice to the OS's own
      per-app notification settings. Adding one here only would be a
      difference to relearn, and the rule says a better idea goes in the Mac
      app first.

      **Open difference:** the Mac no longer waits for the window to be
      unfocused, and a click on one opens the in-app notification bar on the
      matching row. See item 5 of the landed list above for what closing this
      involves — the gate, the click route, the request identifier, and the
      `willPresent` trap that hides foreground posts.

      Two things it does not read from the DOM, both because the DOM answers a
      different question. Backgrounded is the window manager's `isFocused()`,
      not `document.hasFocus()` — the latter is about the *document*, so a
      window plainly in front reports false whenever focus sits somewhere the
      DOM does not own, and posting a notification for a result already on
      screen is the most irritating thing a desktop app does. And permission is
      asked for at the moment one is first needed, not at launch, exactly as
      `requestAuthorizationOnce` does.
- [x] **Background mode and a tray icon** — closing the window hides it, stops
      every live subscription (`stopAllStreams`, which is what
      `AppState.enterBackground` does by walking its open features), and leaves
      the tray and the global shortcuts working. The tray menu is `MenuBarView`
      row for row, pushed from the page because everything in it — the device's
      name, the chosen features — lives there.

      **Only where a tray exists.** macOS always has a menu bar; a Linux session
      can decline to give the app an indicator, and hiding a window nobody can
      bring back is not a mode worth having. The app records whether the icon
      was really created and Settings says so instead of offering the switch.
      The `.deb` therefore depends on `libayatana-appindicator3-1`. For the same
      reason the Mac's **"Show menu bar icon" switch is absent**: turning the
      tray off while the window is hidden is exactly that trap.


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

### A finding that applies to more than one item

`URLSessionWebSocketTask` **compiles off-Darwin and does not work**. A probe in
`swift:6.2-noble` fails every send and receive with `NSURLErrorDomain Code=-1002
"WebSockets not supported by libcurl"`. CI cannot catch this: compiling is all
it checks, so an ADBKit WebSocket client passes `test-linux` and `build-windows`
and then fails on a real machine. `JSConsoleClient` is exactly that shape and is
safe only because just the Mac app calls it.

Plain HTTP `URLSession` is fine — libcurl does that — so `MetroInspector` and
`MetroSymbolicator` stay portable. Only the socket does not. For a portable
WebSocket, pick by side: a **listener** is SwiftNIO in the daemon, the way
`ReactotronRelay` does it; a **client** is either a NIO client or, where the
other end is on this machine, the webview's own. The JS console took the second
route, which is why it needed no new transport at all.


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
| ✅ | Mirror and Mirror Wall | #299 |
| ✅ | Wireless ADB, Custom Commands, APK Inspect/Sign, AAB Convert | #300 |
| ✅ | APK Decompile, APK Studio, JS Console | this branch |

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

- **A shortcut another app already holds stays a window shortcut.** The
  registration is offered to the OS for every binding, and the platform refuses
  the ones it cannot grant. The window listener answers for exactly those, which
  is better than the alternative in both directions: nothing fires twice
  (a registered shortcut is grabbed before the webview sees it), and a
  combination the OS would not take still works where the app has focus.

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
18. ~~**Notifications and their settings.**~~ **Landed.** `post_notification`
    over `tauri-plugin-notification`, registered for its Rust API only like the
    clipboard and the opener, so the webview's capability file stays at
    `core:default`. The decision of *what* earns one is the Mac's and lives in
    `lib/notifications.ts` beside the decision of what is kept in the history.
    The settings switch turned out not to exist on the Mac — see the Look
    section for why this app does not grow one either.
19. ~~**The Quick Actions panel.**~~ **Landed.** A second Tauri window with
    `alwaysOnTop`, no decorations and no taskbar entry, created on first use —
    a second webview costs real memory, and someone who never presses the
    hotkey should never pay it. One bundle, two entry points: the URL says
    which app to render. `lib/quick-actions.ts` is the ported
    `PaletteSearch.quickActions`, including the rule that is easy to get
    backwards — a hub member **is** offered here, and its enabledness rides on
    its hub. Not non-activating, which no window on these platforms can be.
20. ~~**Background mode and the menu bar.**~~ **Landed.** `tauri-plugin-global-shortcut`
    plus a tray icon, and the close handler that hides rather than quits —
    guarded on the tray having actually been created, since a Linux session can
    decline to give one and a window hidden with no way back is not a mode.
21. **Multi-window** (`docs/multi-window.md`) — one window per device, the
    per-window workspace split, the Focus / Take Over banner for the exclusive
    features, and the window tint.
22. **The welcome tour** on first run.
23. **The updater** — Sparkle is macOS-only, so this is `tauri-plugin-updater`
    behind the same "Relaunch to update" pill and What's New sheet.
24. **Reactotron** — landed, relay and pane both. The rest of this entry is the
    relay's design, which is still the thing worth reading.
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
    the files says otherwise: of the seventeen in `ADBKit/Services/Mirror`,
    **ten are already portable** — `ScrcpyStreamDecoder`,
    `ScrcpyAudioStreamDecoder`, `ScrcpyControlMessage`, `ScrcpyDeviceMessage`,
    `ScrcpyServerParams`, `ScrcpyServerLocator`, `H264NAL`, `PCMMixdown`,
    `MirrorAudioFallback`, `ShowTouches`, plus `MirrorWall`'s layout maths, which
    lives under `Features/`. scrcpy's own server speaks the same protocol to any
    host.
    ffmpeg builds for Windows and Linux, but nothing in this repo provisions it
    for either yet: `App/Resources/ffmpeg` is a committed macOS universal binary
    and `scripts/unpack-ffmpeg.sh` verifies it with `lipo`. Screen record and the
    video editor need that gap closed first — the mirror itself does not.

    **Seven files are gated, and they are the whole job.** (The entry said five;
    the two it missed are the ones whose `#if` is not on the first line, and
    neither changes the shape of the work — `H264Format` is glue for the Apple
    display layer and recorder, so the webview path wants nothing from it, and
    `MicrophoneCapture` belongs to screen record rather than the mirror.)

    | Gated on | What it does | The portable answer |
    | --- | --- | --- |
    | `MirrorTransport` | `Network.framework` socket to the scrcpy server over `adb forward` | NIO **in the daemon**, exactly the move `ReactotronRelay` already made — see below |
    | `MirrorSession` | the orchestrator — gated only because it holds the others | falls out once they are |
    | `H264Decoder` | VideoToolbox | settled: the webview's `VideoDecoder` — see below |
    | `H264Format` | CoreMedia glue: format descriptions and `CMSampleBuffer`s | none needed — it exists to feed `AVSampleBufferDisplayLayer` and `AVAssetWriter` |
    | `MirrorAudioPlayer` | AVFoundation playback | the webview's `AudioDecoder`, or a Rust audio crate |
    | `MirrorRecorder` | AVFoundation writer | ffmpeg, once it is provisioned off-Apple |
    | `MicrophoneCapture` | AVFoundation host mic | screen record's problem, not the mirror's |

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
    - **Per artifact, the fix differs — and v3.10.0-beta.1 settled which
      artifacts there are.** Linux ships a `.deb` and an `.AppImage`, not the
      tarball an earlier draft of this entry assumed, so both mitigations are
      real rather than theoretical:
      - The `.deb` gets `bundle.linux.deb.recommends`, not `depends`. apt
        installs Recommends by default, so almost everyone gets the codec, while
        an app that is 61 features wide stays installable for the 60 that do not
        need it. `depends` would make a video codec a condition of running the
        file explorer.
      - The `.AppImage` has `bundle.linux.appimage.bundleMediaFramework`, and it
        is **not** ready to switch on: linuxdeploy bundles what the *builder*
        has, and the Linux job installs with `--no-install-recommends` and no
        gstreamer codec packages at all, so today it would bundle nothing. It
        also costs 15–35 MB and has a live over-bundling bug against Mesa 25+
        hosts. Adding the packages to the builder comes first, and an AppImage
        that is actually run comes before believing either.
      - No RPM ships, so the trap there is only worth remembering if one is
        added: Fedora's decoder lives outside the default repos (RPM Fusion, or
        the Cisco openh264 repo), so a hard `Requires:` would make the package
        uninstallable on a stock system.

    Also worth correcting: on Linux this is **software** decode via
    `avdec_h264`; hardware would need the VA-API plugins on top. Only
    Windows/WebView2 gets hardware decode for free.

    Then, in order: the transport on NIO in the daemon (the `adb forward` tunnel
    *must* be torn down — see the mirror-teardown convention, which the Mac
    learned by leaking one per quit); the session; one tile; then the wall, whose
    layout is already ported. Screen record and the video editor ride the
    session, so they follow rather than lead.

    **Landed so far.** `ScrcpyTransport` (the NIO sockets, with the
    accept-then-drop handshake `adb forward` forces) and `ScrcpySession` (the
    transport, `ScrcpyStreamDecoder` and the mapping onto the wire, with one
    teardown over all three) — both in `DaemonCore`, named apart from ADBKit's
    `MirrorTransport`/`MirrorSession` because on macOS both modules are visible
    at once and the bare names are ambiguous. The `mirror` stream topic is wired
    (`docs/droidectived-protocol.md` §5.4): `config` then frames, Annex-B, taps
    back through `write`. `H264NAL.avcCodecString` is the one piece that went to
    ADBKit, being pure H.264 parsing both hosts could use.

    **One tile has landed too.** `MirrorPane` decodes into a `<canvas>` with
    `useMirror`, and the three rules the daemon cannot enforce for a client are
    `lib/mirror.ts`, tested without a decoder or a device: configure on `config`
    and not before, discard until the next `key` after a `dropped`, and size
    from the decoded frames rather than the config's hint. Input goes back the
    other way through `lib/scrcpy-control.ts`, a port of ADBKit's
    `ScrcpyControlMessage` pinned to the same byte vectors its Swift suite
    asserts — including the Mac's own pointer id of 0 rather than scrcpy's mouse
    sentinel, because those values are the ones proven against real hardware.

    **What the tile still owes the Mac's screen:** audio (its own scrcpy socket,
    not yet plumbed), Show touches, the reconnect button, and opening a mirror
    in a separate window. The per-feature checklist below lists them.

    **And the wall.** `MirrorWallPane` puts up to six tiles in a grid, each its
    own session at the quality `MirrorWall.quality(tiles:)` gives it — ported to
    `lib/mirror-wall.ts` and pinned to the numbers the Swift suite asserts,
    because a port that agreed only with itself would drift from the Mac's
    layout one release at a time. It picks its own devices from a header menu
    rather than following the device bar, and a tile reorders by dragging its
    **caption strip**: a drag handle on the video would eat every swipe on the
    device, which is the note the Mac left.

    Per-tile quality is why the `mirror` topic gained `maxSize`/`maxFps`. The
    client resolves them because only it knows how many tiles it is drawing;
    the daemon clamps them, because they become arguments to a process on the
    device and a value scrcpy refuses arrives as a mirror that never produces a
    frame rather than as the bad number that caused it.

    **What the wall still owes the Mac's:** the selection is not persisted (the
    Mac keeps it per window as `WindowState.mirrorWallSerials`), there is no
    breaking a tile out into its own window, and no Full View.

    **Proven against a real device.** Subscribing to `mirror` on a live
    emulator produced a `config` of `avc1.42C029` at 360×800 followed by real
    H.264 frames, each keyframe starting with an Annex-B start code whose first
    NAL is the SPS — the prepending rule, confirmed on bytes a device actually
    sent. The `adb forward` was open while streaming and gone after
    `unsubscribe`, which is the leak convention checked rather than asserted.

    **What is still unseen is the picture.** The daemon's half is proven and
    WebCodecs' H.264 support is measured on the real target, but no frame has
    been decoded into a canvas in a running window — `useMirror`'s
    `VideoDecoder` wiring is unit-tested and has not been watched. That is the
    step that wants a person at a machine with a device attached.

    **The server jar ships with the app now.** The Tauri bundle carries the
    committed `App/Resources/scrcpy-server` — the very same file, since a Java
    jar is architecture-independent — and passes its path to the sidecar as
    `--scrcpy-server`, so nobody installs scrcpy themselves. That was the Mac's
    promise and it is the port's now too. `ScrcpyServerLocator.bundledVersion`
    is the one version both hosts read, and an ADBKit test holds the Mac's
    `BundledTools.scrcpyVersion` to it, because the pair describes one committed
    file and a mismatch does not degrade — the device-side server aborts, so the
    mirror simply never starts.

    A bundled path that is *not* there fails rather than falling back: quietly
    mirroring through whatever scrcpy the machine happens to have is exactly the
    version mismatch that test exists to prevent. A daemon started by hand
    passes no path and gets the installed one, which is what a developer has.

    **The Linux codec dependency is declared too.** `bundle.linux.deb.recommends`
    now names `gstreamer1.0-libav`, so apt pulls the H.264 decoder in by default
    and the probe's message becomes the fallback rather than the plan.

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

## Per-feature checklists
### Input & Clipboard
#### `send-text` — Send Text  ·  🟡 partial
> Type text, URLs, or symbols on the device
- **Kind** `formAction`
- **Note** Runs from the palette; no dedicated screen.
- **Parameters** `text` (text)


### Connection
#### `connection` — Connection  ·  🟡 partial
> Copy IP, reverse port, disconnect, DNS & wireless setup
- **Kind** `view`
- **Note** A pane exists; the checklist below is what it is missing.
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

#### `wireless-adb` — Wireless ADB  ·  🟡 partial
> Connect over Wi-Fi (tcpip + Android 11 pairing)
- **Kind** `view` · **hub member**
- **Note** A pane exists; the checklist below is what it is missing.
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

#### `js-console` — JS Console  ·  🟡 partial
> Hermes REPL + live console over the Metro debugger
- **Kind** `view`
- **Note** A pane exists; the checklist below is what it is missing.
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

#### `react-native` — React Native  ·  🟡 partial
> Dev menu, reload, deep links, dev server, process death
- **Kind** `view`
- **Note** A pane exists; the checklist below is what it is missing.
- **macOS view** `ReactNativeView` — `App/Sources/FeatureDetail/Views/ReactNativeView.swift`
- **Must replicate**
  - [ ] button: Forward
  - [ ] button: Set

#### `reactotron` — Reactotron  ·  🟡 partial
> Live React Native inspector — logs, network, state, custom display
- **Kind** `view`
- **Note** A pane exists; the checklist below is what it is missing.
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

#### `mirror-wall` — Mirror Wall  ·  🟡 partial
> Mirror up to six devices side by side
- **Kind** `view`
- **Note** A pane exists; the checklist below is what it is missing.
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

#### `scrcpy` — Mirror Screen  ·  🟡 partial
> Mirror and control the device with scrcpy
- **Kind** `view`
- **Note** A pane exists; the checklist below is what it is missing.
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

#### `screen-record` — Screen Record  ·  🟡 partial
> Record via scrcpy — no time limit, with audio
- **Kind** `view`
- **Note** A pane exists; the checklist below is what it is missing.
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
- **Note** Not started — needs ffmpeg's filter graph and a preview scrubber. The managed ffmpeg it would use is now downloaded (Settings ▸ Tools), so this is the editor itself rather than the toolchain.
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

#### `simulate` — Simulate  ·  🟡 partial
> Fake battery, appearance, locale, network & proxy
- **Kind** `view`
- **Note** A pane exists; the checklist below is what it is missing.
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
#### `aab-convert` — AAB to APK  ·  🟡 partial
> Convert an Android App Bundle into an installable APK
- **Kind** `view`
- **Note** A pane exists; the checklist below is what it is missing.
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

#### `apk-decompile` — Decompile APK  ·  🟡 partial
> Browse Java (jadx) or smali + resources (apktool)
- **Kind** `view` · **hub member**
- **Note** A pane exists; the checklist below is what it is missing.
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

#### `apk-inspector` — APK Inspector  ·  🟡 partial
> Inspect an APK — manifest, permissions, SDK, signing
- **Kind** `view` · **hub member**
- **Note** A pane exists; the checklist below is what it is missing.
- **macOS view** `ApkInspectorView` — `App/Sources/FeatureDetail/Views/ApkInspectorView.swift`
- **Must replicate**
  - [ ] button: Choose APK…
  - [ ] button: Inspect another…
  - [ ] label: \(title) (\(items.count))
  - [ ] label: Signing

#### `apk-sign` — Sign APK  ·  🟡 partial
> Zipalign and sign an APK — debug key or your keystore
- **Kind** `view` · **hub member**
- **Note** A pane exists; the checklist below is what it is missing.
- **macOS view** `ApkSignView` — `App/Sources/FeatureDetail/Views/ApkSignView.swift`
- **Must replicate**
  - [ ] button: Choose APK…
  - [ ] button: Choose a different APK…
  - [ ] button: Open in Finder

#### `apk-studio` — APK Studio  ·  🟡 partial
> Inspect, decompile, recompile, and sign APKs in one place
- **Kind** `view`
- **Note** A pane exists; the checklist below is what it is missing.
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
#### `api-client` — API Testing  ·  🟡 partial
> Send HTTP requests, import Postman collections, assert on responses
- **Kind** `view`
- **Note** A pane exists; the checklist below is what it is missing.
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

#### `custom-commands` — Custom Commands  ·  🟡 partial
> Your own adb, terminal, and script actions
- **Kind** `system`
- **Note** A pane exists; the checklist below is what it is missing.
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
- **Note** A pane exists; the checklist below is what it is missing.
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


<!-- counts: {'done': 0, 'partial': 57, 'todo': 2, 'gated': 2} -->
