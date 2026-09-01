## Droidective v3.10.0-beta.5

Two fixes from a real Linux install, one of which stopped the app installing at
all.

### It installs without adb now

- **adb was a hard dependency of the `.deb`,** so apt refused to install
  Droidective on a machine that did not already have it. That is backwards: the
  app has a setup Doctor whose whole job is to tell you a tool is missing and
  where to get it, and it never got the chance to run. adb is a recommendation
  now — apt still installs it alongside the app by default, and a machine
  without it still gets the app.
- **The advice it gives afterwards fits the machine.** "Install it via Android
  Studio" is the right sentence on a Mac and useless on Ubuntu, where the answer
  is one command. Droidective now reads the distribution and says
  `sudo apt install android-tools-adb`, or the dnf, pacman or zypper equivalent
  — and the button beside the warning copies it, rather than leaving you to
  retype it out of a tooltip. Mint, Pop!_OS, Zorin and elementary get the apt
  answer through `ID_LIKE`; a distribution none of those cover gets the package
  name rather than a guessed command.

### The menu bar is not see-through

- **On Linux the desktop showed through File, Edit and View.** The window was
  made transparent in the last beta so the Opacity slider could work, but Linux
  draws the app's own menu bar above the page, and that strip has nothing to
  paint itself on over a transparent window. The window is opaque there again.
- **Opacity now says it is unavailable on Linux, and why.** Grain still works,
  and nothing changes on Windows.
- **The check that should have caught it exists now.** The Linux job that
  launches and photographs the app on every change was comparing the app
  against a black background, so a hole in it was invisible. It counts the
  pixels the app failed to paint, which for this bug would have been about
  twenty-six thousand of them.

## Droidective v3.10.0-beta.4

Five more of the Mac's features reach Windows and Linux, and two of them could
not simply be moved across — the recorder and the file drops both needed a
different answer here than the one macOS gave. Everything else is the same
screen, the same wording, the same gestures.

### API Testing

- **The whole client is here.** Collections and nested folders, environments,
  `{{variable}}` scopes with the unresolved ones surfaced before a send rather
  than sent as literal braces, assertions on status, timing, body, header and
  JSON path, a collection runner, code generation to six targets, Postman
  import and export, and a cURL paste that parses back into a request.
- **The collection runner deliberately stayed in the app.** It would have been
  one daemon call; instead the client walks the tree and sends one request at a
  time, so progress is live and Stop is instant rather than "the run finishes
  and then tells you".

### Recording the screen

- **The recorder is a new pipeline, not a port.** The Mac records through its
  Apple-only media stack, so there was nothing to move: the daemon now feeds
  the scrcpy H.264 stream straight into ffmpeg and copies the video track
  without re-encoding. Pause and resume produce segments that the concat
  demuxer joins at the end, so a paused take is one file.
- **A recording said 30 seconds for a 12-second file.** The clock had been
  running from the button press, and scrcpy takes a few seconds to produce its
  first frame. It is measured from the first frame to the last now — 13.820
  reported against 13.819 in the file.
- **ffmpeg is downloaded rather than bundled.** Digest-verified from a pinned
  release, `.tar.xz` on Linux and `.zip` on Windows, which is also what
  unblocked **Settings ▸ Tools** — the managed-tool store, with sizes, upgrades
  and removal.

### More than one window

- **One window per device**, each with its own tabs, its own arrangement and
  its own device selection, restored where you left them.
- **The Focus / Take Over banner** for the features that cannot run twice on
  one device — the mirror, the recorder, the JS console — instead of two
  windows racing each other for the same encoder.
- **Every window after the first tints its device icon**, so which window you
  are looking at is answerable without reading the tab strip.

### Files dropped on the window

- **An APK or app bundle dropped anywhere installs it**, whatever screen is in
  front; anything else dropped on the File Explorer is pushed to the directory
  it is showing. Anywhere else says which of the two to do rather than guessing
  a destination on someone else's device.
- **The in-app drags were the constraint.** Turning on the toolkit's own
  file-drop handler stops every drag inside the page working — the tab strip,
  the sidebar, the mirror wall — so instead of trading one for the other, a
  dropped file's *bytes* are staged on the way through. One copy, and nothing
  that already worked had to be rewritten.

### Look and first launch

- **The window can be glass.** Settings ▸ Appearance ▸ Window gains Opacity and
  Grain — the Mac's sliders, with the Mac's arithmetic, so a window set up on
  one machine looks the same on the other. At 100% nothing changes at all.
- **Blur is a switch here, not a slider.** No desktop platform lets an
  application ask for a blur *radius*: Windows has Acrylic, which is on or off,
  and on Linux the compositor decides entirely. A slider with two positions
  would be a worse lie than a switch, so the row says what the platform will
  actually do.
- **First launch asks what you do.** The role picker curates the sidebar to
  Android, React Native, iOS, QA, support or security work — with the tool
  counts following the "I work with React Native" switch live — and Settings ▸
  General names the role in effect and lets you change it. Escape leaves it.

### Fixes

- **A form action with two devices connected was a Run button that did
  nothing.** Only one screen can be in front of the Quick Actions panel, and it
  checked the form first, so the pick-a-device step opened behind the form that
  had just been submitted. Found while adding the step that asks *which app* an
  action that needs one should run against.
- **The Linux smoke test was photographing the wrong thing.** It drives the app
  on every pull request, and once the role picker appeared on first launch its
  keystrokes were going into that instead. It now dismisses the picker and
  proves it went away before driving anything, so the job checks three things
  where it had been checking one.

## Droidective v3.10.0-beta.3

The Windows and Linux app grows the three things it was missing that people
notice first: it tells you when something finishes while you are elsewhere, it
stays out of the way without quitting, and it can be summoned over whatever you
are working in. Behind all of that, the reason the Windows app looked broken on
its first launch turned out not to be what the note in the tracker said.

### The Windows app was hanging, not being slow

- **The first `adb devices` on Windows never returned.** The app came up
  showing "0 features" and no error, which is exactly what Linux did before the
  last beta fixed it there. It had been written down as *slow rather than dead*
  on the evidence of a stand-in that returned after thirty seconds — but the
  stand-in slept, and adb's grandchild is a *server*, which does not exit at
  all. Timing the real call settled it.
- **The fix is a second way to notice a child has gone.** Windows now waits on
  the process handle, which the OS signals the moment the child exits —
  inherited pipes and surviving grandchildren included. The whole ADBKit suite
  runs there in six seconds where one test used to sit at thirty, and the
  regression test that was gated off Windows for "destabilising" a neighbour
  runs again: that neighbour was the same missing exit report, seen from the
  other end.
- **Both smoke tests now time it.** The Linux one, on every pull request, and
  the Windows one on every beta tag, ask the running app for its device list
  and fail if the answer takes longer than ten seconds. An empty answer is
  fine; an answer arriving is the point.
- **The app no longer waits for the device list to show anything.** Its two
  startup calls used to arrive together, which handed the slower of them the
  decision about when the app became usable. The sidebar now paints as soon as
  the registry answers, whatever adb is doing.

### It tells you when you are looking somewhere else

- **A result that lands while you are in another app posts a notification.**
  Not a list of events, but the same rule the Mac uses: the results already
  worth keeping in the notification panel are the ones worth interrupting for,
  so an install finishing and a watched crash landing both arrive without
  either screen knowing a tray exists. Failures carry a sound; routine
  confirmations stay quiet.

### It stays running without staying in the way

- **Closing the window leaves Droidective in the tray** instead of quitting it,
  stops the work that was only running because a window was open — terminal
  shells included — and keeps the shortcuts alive. The tray menu is the Mac's
  menu-bar menu: the selected device, Quick Actions, Screenshot, Mirror Screen,
  the features you chose in Settings, then Open and Quit.
- **Only where there is somewhere to click.** A Linux session can decline to
  give an app a tray icon, and hiding a window nobody can bring back is not a
  mode worth having, so the app checks and Settings says so instead of
  offering the switch. The `.deb` now depends on `libayatana-appindicator3-1`.
- **Recorded shortcuts are registered with the system.** They fire from
  whatever app you are in, and from a window closed into the tray. A
  combination another app already holds is refused by the platform and goes on
  working while Droidective has focus, rather than working nowhere.

### Quick Actions

- **A panel over whatever you are doing**, on a shortcut you record in
  Settings ▸ Hotkeys or from the tray's first item: a search field over a grid
  of everything runnable in place, your saved commands under it, and the
  full-app screens under those. Arrows move the grid while you are still
  typing, Enter runs, Escape closes.
- **It asks before it acts.** A destructive action waits for a second Enter. A
  device-scoped one asks which device when more than one is connected, with an
  All devices row for the actions that fan out. A form action shows its fields;
  so does a toggle, because guessing a direction and writing it to a device is
  worse than asking.
- Manage Apps, Emulators and Install APK are not in the panel yet.

### Appearance

- **Pick the window's background and text colour.** Eight presets, a colour
  well and a hex field, with the lifted surfaces, the hairlines and the muted
  text derived from what you picked — so a custom colour keeps the same
  hierarchy the stock one has. A light background switches the whole app to
  the light treatment, and the Theme picker says so rather than fighting it.

### Install

**Windows** — download the `-setup.exe` and run it, clicking through the
SmartScreen warning. The `.msi` is there for anyone deploying it centrally.

**Linux** — `sudo apt install ./Droidective-0.0.3-beta.1-linux-x86_64.deb`, or
make the `.AppImage` executable and run it. Both need `adb` on `PATH`; the
`.deb` declares it as a dependency, along with `libcurl4` and
`libayatana-appindicator3-1` for the tray, and a recommendation of
`gstreamer1.0-libav` for the mirror.

**macOS** — download the DMG and drag Droidective to Applications. Existing
installs on the beta channel update themselves.

## Droidective v3.10.0-beta.2

The first beta shipped a Windows and Linux app that nobody had ever launched.
This one launches it — in CI, on every pull request — and fixes the three
things that stopped it working when somebody finally did.

### Linux, actually running

- **The app now starts, and CI proves it on every change.** A new job installs
  the `.deb` in a bare `ubuntu:24.04` — so apt resolves the package's own
  declared dependencies and nothing the build machine happened to leave behind
  — launches it under Xvfb, drives the command palette to open a screen, and
  photographs both frames. Every check fails the build rather than warning.
- **The daemon could not start at all.** `droidectived` was dynamically linked
  against the Swift runtime, so on any machine without a Swift toolchain it
  died at exec with `libswiftCore.so: cannot open shared object file`, and the
  app came up showing "droidectived would not start" with all thirty-three
  screens behind it. It now carries its own runtime.
- **Then it could not find `libcurl`.** Declared as a dependency of the `.deb`
  rather than assumed.
- **Then it came up and did nothing.** `adb devices` on a machine whose adb
  *server* is not yet running forks that server and exits — and Linux left the
  exited process unreaped, so the call never returned and the window sat at
  "0 features" with no error. The process runner now notices that exit itself.
  The cold call went from hanging indefinitely to 0.185 s.

### Windows

- **It gets launched too, on every beta tag.** The installer runs silently, the
  app starts, and the release fails if the app or its daemon is not alive
  thirty seconds later. There is no Windows container, so this proves less than
  the Linux check does — the runner already has what the toolchain left — but
  it is the first time the Windows build has been started at all.

### New in the app

- **Three more screens: React Native, Simulate and Connection.** The hub
  screens, each matching the Mac's section for section — the RN quick actions
  and both Metro paths, Simulate's battery, appearance, layout, locale, network
  and proxy, and Connection's live Wi-Fi and IP with the pairing and Private DNS
  sections it shares with their standalone screens. With these the sidebar
  matches the Mac's.
- **Logcat can follow one app.** Pick it in Apps or press "App on screen", and
  the log narrows to that process — filtered on the device with
  `adb logcat --pid`, so the buffer holds only that app's lines instead of
  hiding the rest after the fact. It waits for an app that has not launched
  yet, and follows it when it relaunches under a new process id.
- **Install App is in the sidebar.** It had a working screen and was missing
  from the list, along with four others the daemon was reporting as not built.

### Fixed

- **The mirror's codec check is now a real decode.** Linux needs
  `gstreamer1.0-libav` for H.264, which the `.deb` pulls in by default; without
  it the mirror says which package to install rather than showing a black
  rectangle. That is now verified by decoding an actual frame rather than
  asking the webview whether it thinks it could.

### macOS

- **This is a rebuild, not a Mac release.** The Mac app is identical to v3.9.2
  and is offered only to installs that opted into beta updates in Settings ▸
  General. The stable channel is untouched: the download button and
  `/releases/latest/download/` keep serving v3.9.2.

### Install

**Windows** — download the `-setup.exe` and run it, clicking through the
SmartScreen warning. The `.msi` is there for anyone deploying it centrally.

**Linux** — `sudo apt install ./Droidective-0.0.2-beta.1-linux-x86_64.deb`, or
make the `.AppImage` executable and run it. Both need `adb` on `PATH`; the
`.deb` declares it as a dependency, along with `libcurl4` and a recommendation
of `gstreamer1.0-libav` for the mirror.

**macOS** — download the DMG and drag Droidective to Applications. Existing
installs on the beta channel update themselves.

## Droidective v3.10.0-beta.1

The first Windows and Linux build of the app itself. Until now a beta carried
only `droidectived`, the headless daemon; this one carries the desktop app that
runs on top of it — an NSIS installer and an MSI for Windows, a `.deb` and an
`.AppImage` for Linux. It is an early build and the version says so: Windows and
Linux start their own version line at `0.0.1-beta.1` rather than inheriting the
Mac's.

### Windows and Linux

- **The desktop app, for the first time.** 23 screens have a real pane: Terminal,
  Apps, Logcat, Device Info, File Explorer, Crash Catcher, Bug Report,
  Performance, Root Status, Developer Settings, System Restrictions, Wi-Fi,
  Private DNS, Network Speed, Emulators, Install App, App Info, Permissions,
  Memory Usage, Sandbox Browser, Manage App, Deep Links and Reactotron — plus
  the catalog and About. Another 19 features run as actions from the palette
  without a screen of their own.
- **It is meant to be the same app.** Where a control exists on both, it has the
  Mac's wording, icon, confirmation shape and gesture. Two deliberate
  exceptions, and they are the only ones: a shortcut whose modifier has no
  equivalent here (⌘\ is Ctrl+\, and the split is Ctrl+\ rather than Ctrl+D
  because Ctrl+D ends input in every Linux shell), and a label that names a
  platform.
- **`droidectived` still ships too**, for macOS, Linux and Windows. It is useful
  on its own — CI, scripting, adb over loopback — and the app talks to it rather
  than to adb directly.

### What is not there yet

- **17 of the 61 features have not been started**, and the 42 counted as partial
  are each missing something the Mac version offers. Read the state as *nothing
  is finished* rather than *most of it is done*; `docs/desktop-parity.md` tracks
  it feature by feature.
- **The mirror, screen recording, the video editor, multi-window, Quick Actions,
  the tour and notifications are not ported.** They are porting jobs with
  entries in the backlog, not decisions.
- **`ios-logs` and `push-notification` will not come.** They drive `xcrun
  simctl` against an iOS Simulator, which is a macOS toolchain rather than
  anything about a device.
- **No automatic updates.** The app does not update itself on Windows or Linux;
  a new beta is a new download.

### Two version lines

- **Windows and Linux are versioned separately from the Mac.** This build is
  `0.0.1-beta.1` on those platforms and `3.10.0-beta.1` on macOS. The Mac
  carries the product's own history — 61 features across three major versions —
  and the ports do not, so numbering a first Windows build in the threes would
  claim a maturity it has not got. The two lines move independently from here.

### Unsigned, and what that means

- **Windows will warn.** The installer is not Authenticode-signed, so
  SmartScreen shows "Windows protected your PC" — More info, then Run anyway.
  Code-signing is a deliberate deferral, not an oversight: an OV certificate is
  a recurring cost and a multi-week identity check, and reputation accrues per
  certificate over download volume a beta will not generate.
- **Linux bundles are unsigned too**, which is normal for the ecosystem.
- **Every unsigned artifact is checksummed.** `SHA256SUMS` on the release page
  covers the installers, the bundles and all three daemon archives. The macOS
  DMG is Developer ID-signed and notarized as always.

### macOS

- **This is a rebuild, not a Mac release.** The Mac app is identical to v3.9.2 —
  a beta that exists to ship a Windows and Linux build still rebuilds the Mac
  app, and it is offered only to installs that opted into beta updates in
  Settings ▸ General. The stable channel is untouched: the download button and
  `/releases/latest/download/` keep serving v3.9.2.

### Install

**Windows** — download the `-setup.exe` and run it, clicking through the
SmartScreen warning above. The `.msi` is there for anyone deploying it centrally.

**Linux** — `sudo apt install ./Droidective-0.0.1-beta.1-linux-x86_64.deb`, or
make the `.AppImage` executable and run it. Both need `adb` on `PATH`; the `.deb`
declares it as a dependency.

**macOS** — download the DMG and drag Droidective to Applications. Existing
installs on the beta channel update themselves.
## Droidective v3.9.2

Pulling events out of a busy log. Rows in the Reactotron timeline and the JS
Console can be selected — ⌘-click one, ⇧-click a range, drag across them — and
copied whole, payload included. An API call's status code also reads off its
collapsed row, and the empty "Screen Mirror" window that could appear at launch
is gone.

### Reactotron and JS Console

- **Select rows and copy them whole.** Pulling a few events out of a busy
  timeline meant right-clicking them one at a time. ⌘-click toggles a row,
  ⇧-click takes the range from the last one picked, and dragging across rows
  sweeps a range; the toolbar shows how many are picked, with a copy menu, and
  ⌘C copies them. A copy carries the whole event rather than the line already on
  screen — the row's summary followed by the complete payload: an API call's
  request body, headers and response, an action's or saga's arguments. Copy as
  JSON gives the same events in the export's wire form.
- **A selection can't copy what the feed no longer has.** Rows that were
  cleared, filtered out, or trimmed while the selection stood are dropped from
  it, so a copy never contains events nobody can see.
- **The gestures stay out of each other's way.** Only a row's header carries the
  drag, so dragging through an expanded payload still selects that text, and ⌘C
  is bound only while rows are picked — it never shadows copying text out of the
  search field or an open payload.

### Reactotron

- **An API event's status code sits on its collapsed row.** Reading a timeline is
  mostly looking for the one call that didn't return 200, and that meant
  expanding rows one at a time. The code now sits between the API badge and the
  method — green for 2xx, orange for a client error, red for a server error,
  neutral for a redirect. Only the code is tinted, so the timeline's own badge
  colours still read. A request that never got a response reports status 0 on the
  wire, so it reads `ERR`.

### Mirror

- **No empty "Screen Mirror" window at launch.** A 420×850 window with a title
  bar and nothing in it could appear on its own at launch — and in the worst case
  it was the only window the app had. The pop-out mirror's window group persists
  the device it was presented with and re-presents it at the next launch, before
  any workspace exists for it to attach to, so it rendered nothing and no main
  window was created either. A pop-out now has to have been asked for in this
  session; anything else closes itself once a real window is up.

### Install

Download the DMG, drag Droidective to Applications, and open it. Existing
installs update themselves.

## Droidective v3.9.1

A bug-fix release. The pop-out mirror window from 3.9.0 could hang the app —
including at launch, before anything was open — and Reactotron's timeline showed
stringified payloads as a wall of escaped text instead of the object they are.
A mirror screenshot can also be copied straight to the clipboard now.

### Mirror

- **A pop-out mirror window no longer hangs the app.** The window re-registered
  itself on every view update, and each registration wrote state the app's own
  window list reads — so the write ran the update and the update ran the write.
  The app beach-balled for as long as one of those windows was open, with no way
  out. Registration now happens once per window.
- **Those windows are no longer restored at launch.** macOS was reopening them
  from its own saved state before the app had a workspace to own them, which
  started a mirror session on a device nobody had asked about and made the hang
  reproducible from launch — and immune to reinstalling the app, since saved
  state lives outside the bundle.
- **A mirror screenshot can be copied to the clipboard.** The capture sheet on
  Mirror Screen and the Mirror Wall offered Discard / Save / Edit, so getting the
  image into a chat or a ticket meant opening the editor first. Copy sits beside
  them and leaves the sheet up, so a copy can still be followed by Save or Edit.

### Reactotron

- **A stringified payload shows as an object.** An API request's `data` field
  arrives as the app's own `JSON.stringify` output, so an expanded event showed
  escaped text where the body should be. It now renders as a real tree, with a
  raw toggle per row for the payloads that only read in their escaped form. A
  logged string that is itself JSON gets the same treatment.
- **Find agrees with what the tree shows.** Searching `storeId` in a payload
  rendered as an object returned the whole 4 KB escaped blob on the `data` row
  instead of the leaf two rows below it. The search now walks a string's parsed
  form, and clicking a result reveals the row it actually lives on.
- **A long API URL opens in place instead of over the rows below it.** A signed
  URL several hundred characters long drew all of its lines across the status
  rows and the tab strip, because the layout had reserved three. The line is now
  cut to the measured width and a click opens it whole at its real height.
- **A parsed payload stays with the tab it belongs to.** An API event's four tabs
  are one tree, so switching tabs could render the previous tab's object on this
  tab's row, under a chevron that claimed to be open.

### APK signing

- **A keystore password file that can't be written says why.** Signing reported
  only "Couldn't write the keystore password file"; the failure now carries the
  path and the underlying reason, and creating the file is reported separately
  from restricting it to its owner.

### Install

Download the DMG, drag Droidective to Applications, and open it. Existing
installs update themselves.

## Droidective v3.9.0

Mirroring several devices at once. The Mirror Wall shows up to six connected
devices side by side in one pane, each one live and controllable, and Full View
hands the whole display to whatever screen you are on. Mirror sessions also stop
leaking their adb tunnel when the app quits — which affected the single mirror
too.

### Mirror Wall

- **Up to six devices, side by side.** The 61st tool mirrors several connected
  devices in one pane. Every tile is the same session the full mirror runs, so
  clicking a tile taps that device and typing goes to it — one wall for a whole
  bench of phones instead of one window per device.
- **The wall picks its own devices.** A Devices menu lists the connected
  Android devices with a checkbox each, capped at six; the picked set and the
  order they sit in are remembered per window. Opening the wall for the first
  time shows what is connected.
- **Automatic or fixed layout.** Auto derives the column count from the pane
  width and drops a column rather than shrinking tiles into uselessness; 1, 2
  or 3 columns is a fixed choice that stands. Tiles rearrange by dragging a
  tile's caption strip — the strip, not the video, so a swipe on the device
  stays a swipe.
- **Any tile can become its own window.** Open one device in its own window, or
  every tile at once, and Arrange Mirror Windows tiles them across the screen.
  Bring Back closes the window and the tile picks the device up again. A pop-out
  mirror window is now pinned to the device it was opened for rather than
  following the device bar, which is what lets several stand side by side.
- **Six encoders is a real cost, so the wall spends less per tile.** The
  resolution and frame rate each tile asks the device for step down as tiles are
  added (one tile is exactly the full mirror), tiles pause individually, audio
  streams from the focused tile only and is off by default, and the whole wall
  stops after two minutes behind another tab — or behind another window, or
  minimised.
- **One device, one mirror.** A device already showing in its own window, in the
  Mirror Screen tab, or in another workspace window says so on its tile with a
  way to reach it, instead of putting a second encoder on the device.

### Full View

- **View ▸ Full View (⇧⌘F) gives a screen the whole display.** The sidebar,
  device bar and tab strip go away and the window enters full screen — six
  mirror tiles want every pixel. The feature's own controls stay, so the wall
  keeps the row with its Devices menu, layout picker and the way back out.

### Fixes

- **Mirror sessions released their adb tunnel on quit.** Each live mirror opens
  an `adb forward` tunnel that its teardown removes, but at quit the app exited
  before the teardown ran, leaving the tunnel registered in the adb server —
  one per session, every quit, until `adb kill-server`. Quit now waits for the
  sessions to close. This affected the single mirror and the pop-out window, not
  just the wall.
- **Reconnecting a mirror tile showed a black screen.** The tile kept drawing
  the stopped session's video layer, so input worked while no frame ever
  arrived.

### Install

Download the DMG, drag Droidective to Applications, and launch it. The app is
Developer ID-signed and notarized, and updates arrive through Sparkle — no
Homebrew, no separate scrcpy or ffmpeg install.

## Droidective v3.8.2

Fixes for the JS Console in a split pane. The feed left blank space that grew
every time the pane changed width, and the console refused to shrink to the
pane it was given — which read as the tab beside it covering the log.

### JS Console

- **The feed fills its pane again.** A row's height was measured against a
  baseline that was still moving, so a message wrapped onto several lines drew
  past the height its row had reported. One row is invisible; a feed of them
  leaves gaps that shift on every resize. It only showed in a narrow pane,
  because that is where rows wrap at all.
- **The console shrinks to the pane it is given.** The connection bar held its
  target label at full width — `com.myapp.features · Pixel 7 - 17 - API 37`
  is most of a split pane — and that became the minimum for everything below
  it, so rows were laid out wider than the pane and cut off at its edge. The
  target and the status line now truncate. This also brings back the filter
  row's level, find, export and clear controls, and each row's timestamp, at
  the narrowest split.
- **A `console.table` no longer sizes the whole feed.** Its grid scrolls
  inside its own row instead of making every row as wide as itself.
- **Where a log came from is an icon**, in the row's hover controls beside the
  two copy buttons. Written out it cost more width than the message beside it
  could spare. The file, line, function and full path are in its tooltip, and
  clicking it still opens the whole stack.

### Install

Download the DMG, drag Droidective to Applications, and open it. Existing
installs update themselves.

## Droidective v3.8.1

The JS Console now reads like Chrome DevTools' console. Log arguments sit on
one line with their objects inline, every row says which line of your source
made the call, and `console.group` and `console.table` render the way they do
in Chrome. Copying a log takes the object with it, and clicking inside an
expanded value no longer folds it back up.

### JS Console — Chrome parity

- **A log is one line** — the message and its objects sit together, each object
  an inline disclosure, instead of one object stacked per line. Strings logged
  at the top level print bare the way Chrome prints them (`console.log('hi')`
  shows `hi`, not `"hi"`), nested strings use single quotes, arrays lead with
  their length, and a nested object shows `{…}` rather than the word "Object".
- **Every row says where it came from** — `StreamScreen.tsx:142` at the right
  edge, resolved through Metro's symbolication, so it names the file you wrote
  rather than a line in the bundle. Clicking it opens the whole stack, with
  framework and `node_modules` frames dimmed the way Chrome greys the frames it
  ignore-lists.
- **`console.group` blocks indent and fold** — with a rule down their left, and
  `console.groupCollapsed` starts folded. `console.groupEnd` no longer leaves a
  blank row behind it.
- **`console.table` draws a table** — an index column, one column per key across
  the rows, and the value's own disclosure below it.
- **Collapsed values show what's in them** — a nested object previews its first
  few properties (`{at: '2026-08-07', session: {…}, tags: Array(3)}`) instead of
  a key count, so most values can be read without opening them.
- **Terminal colours are rendered, not printed** — React Native's own dev-server
  notices arrive coloured for a terminal, and the escape codes were burying the
  message.
- Log rows no longer carry a level glyph; Chrome marks only errors and warnings,
  and the column of identical icons was noise.

### JS Console — fixes

- **Copying a log takes the object with it.** The row shows an object as `{…}`,
  which is exactly the part a pasted log can't be used for — the copy now
  resolves it to real JSON. A second button beside it copies just the object,
  for pasting somewhere that wants JSON alone.
- **Clicking inside an expanded object keeps it open.** Clicking a nested value
  — or any blank space on the row — used to fold the whole thing back up.
- **Expanding a logged `Error` shows its stack** instead of an empty box.
- The find field inside an expanded value appears only when the value is big
  enough to need one.

### Install

Download the DMG, drag Droidective to Applications, and open it. Existing
installs update themselves.

## Droidective v3.8.0

API Testing arrives as the 60th tool — a full HTTP client with Postman import
and export, collections, environments, assertions, and code generation.
Recordings can now capture microphone audio alongside the device, the Terminal
scrolls properly in full-screen and streaming programs, and four main-thread
hangs reported from v3.7.1 are fixed.

### API Testing — the 60th feature

- **A real HTTP client, in the palette** — all seven methods, six body kinds
  (JSON, form-urlencoded, multipart, raw, GraphQL, binary), and five auth
  kinds (bearer, basic, API key in header or query, OAuth 2). It needs no
  device, so it works with nothing plugged in.
- **Postman import and export** — bring collections and environments across,
  and send them back. Import and export failures now report a reason instead
  of failing silently.
- **Collections, folders, and environments** — a searchable sidebar with
  nested folders and per-item move, duplicate, and delete; `{{variables}}`
  resolve from environment and global scopes, and unresolved ones are flagged
  before a request goes out rather than being sent literally.
- **Assertions and a collection runner** — assert on status code, response
  time, body size, body text, any header, or a JSON path, and run a whole
  collection in one sheet.
- **Generated code** — every request exports as cURL, HTTPie, `fetch`, axios,
  Python `requests`, or Swift `URLSession`. Pasting a cURL command parses it
  back into a request, including `-u` credentials.
- **A response pane that shows the response** — pretty and raw body, image
  preview, headers, cookies, a timing breakdown, the redirect chain, and
  save-to-file. JSON keeps the server's key order; the earlier printer sorted
  keys, which misrepresents the payload you are inspecting.

### Screen recording

- **Microphone audio** — a recording can capture the device's audio, the Mac's
  microphone, both, or neither. The device side is playback *or* the device's
  own microphone, never both — scrcpy carries one device stream per session —
  so those two options are mutually exclusive and say so.
- **Set it up before you hit record** — the chevron beside the mirror's record
  button opens a sheet with the three controls and a live level meter; the
  Screen Record screen shows the same controls inline. Mid-take, each source
  gets a mute control.
- **One audio track, not two** — both sources are mixed onto a single track,
  because players (QuickTime, browsers, chat apps) play only the first audio
  track and silently drop the rest. Muting writes silence rather than dropping
  samples, so the timeline stays continuous and unmuting is instant.

### Terminal

- **The wheel now scrolls full-screen programs** — an agent CLI, `htop`,
  `less --mouse`, or vim with `mouse=a` could not be scrolled at all: those
  programs take the mouse over and run on the alternate screen, where there is
  no viewport to move. The wheel is now reported to the program, or sent as
  cursor keys when the program hasn't taken the mouse (xterm alternate
  scroll), following the scroll's own distance rather than flinging a pager
  pages at a time.
- **Scrolling one no longer corrupts the screen** — the alternate screen's
  right margin was left at 0, so a scroll region copied a single column per
  row and left the rest stale, leaving two frames interleaved on screen. The
  margin is repaired when the alternate screen activates, leaving a program's
  own margins alone.
- **Scrollback stays put while output streams** — scrolling back through a
  running command snapped to the newest line on every line written. The view
  now holds where you left it; typing returns to the live output.

### Fixes

- **Launch hang on a cold font registry** — enumerating installed fonts ran on
  the main thread during launch and could block past the 2-second hang
  threshold. It now runs off the main actor through Core Text (13 ms against
  the previous 91 ms warm, same 245 families).
- **Log tail stalls** — scrolling the log to the bottom forced the text system
  to typeset the entire buffer, so a filter change, an order flip, or a large
  append could freeze the app. The view scrolls to the document height
  instead, with non-contiguous layout enabled.
- **Opening Settings ▸ General stalled** — it read the launch-at-login status
  with a synchronous launchd round-trip on the main thread.
- **Beachball when resizing with a heavyweight tab open** — every mounted tab
  re-laid out on each tick of a divider drag, including hidden ones; a Crash
  Catcher trace of a few thousand lines turned that into a multi-second hang.
  Hidden tabs now pin to their last resting size mid-resize and re-wrap once
  at rest.
- **ffmpeg errors were hidden by its own progress output** — ffmpeg separates
  progress updates with carriage returns, so the export and segment-stitching
  error dialogs showed the progress blob instead of the actual error. Both now
  split on all newline forms.
- **Stale results from cancelled loads** — navigating away from a view while it
  was still fetching could write the old result into the new state.

### Under the hood

- **Windows and Linux groundwork** — ADBKit, the layer holding all of
  Droidective's logic, now compiles and runs its test suite on Linux and
  Windows as well as macOS, with a guard test that fails the build on new
  Apple-only code outside an explicit gate. Nothing changes for macOS users;
  this is the foundation for the Windows and Linux builds, which will ship on
  the beta channel (`docs/release-channels.md`).

### Install

Download `Droidective-v3.8.0.dmg` below. Existing installs update in place
via Sparkle.

---

## Droidective v3.7.1

A new Developer Settings panel drives Android's Developer Options over adb,
the mirror gains a Show touches option, emulators wipe and relaunch as
separate actions, and the Terminal's collapsed rail keeps every tab
reachable — with dropped files typing their paths into the shell. Plus
fixes for a welcome-tour crash, an update pill that could spin forever, and
JS Console hangs on chatty Metro streams.

### Developer Settings — the 59th feature

- **Android's Developer Options over adb** — show taps, pointer location,
  layout bounds, GPU overdraw, GPU profile bars, strict-mode flash, don't
  keep activities, and the three animation scales, all in one panel. Values
  load from the device so the panel shows ground truth, and overlay toggles
  repaint running apps immediately — no app restart.

### Terminal

- **Collapsed rail keeps tabs reachable** — the thin rail now lists every
  open shell as a two-letter badge: click to switch, hover for the full
  name, right-click for the tab menu.
- **Dropping files types their paths** — drop Finder files on a shell and
  their paths are typed in (quoted only when needed, trailing space), with
  that pane focused — like dropping onto Terminal.app.

### Screen Mirror

- **Show touches** — a new ⋯ options menu (audio lives there too) toggles
  Android's touch dot for the session: it flips instantly, works
  mid-recording, and the device's own setting is restored when the session
  ends. The dot draws only for physical touches on the device — taps
  injected by clicking the mirror don't render it.

### Emulators

- **Wipe without launching** — "Wipe Data…" on a stopped AVD wipes in place
  (user data, caches, snapshots — the same set Android Studio removes)
  instead of booting the emulator to do it.
- **Relaunch** — running AVDs gain a Relaunch button: graceful stop, wait
  for the console port to free, boot the same AVD.

### Fixes

- **Welcome tour crash** — double-activating Next or Back (Return
  auto-repeat, or a double-click racing the render) could step past the
  last page and crash mid-onboarding. Paging is now clamped to the range.
- **Update pill no longer sticks** — cancelling the quit confirmation or an
  interrupted install left the sidebar pill on "Installing update…"
  forever; it now returns to a clickable "Relaunch to update" (or a
  retryable error state).
- **JS Console hangs on chatty streams** — a busy Metro feed drove up to 60
  full feed re-renders a second and re-ran link detection on every visible
  row; flushes are now paced and link detection cached, ending the app
  hangs reported with the console open.

### Install

Download `Droidective-v3.7.1.dmg` below. Existing installs update in place
via Sparkle.

---

## Droidective v3.7.0

The app goes universal — Intel Macs run it natively at last — and the
Reactotron relay learns to serve its data to AI agents over MCP. The
Terminal resumes your working directories across quits, both debug consoles
gain a clear-data restart, split Reactotron panes order themselves
independently, and a hidden mirror stops reconnecting on every tab flip.

### Runs natively on Intel Macs

- **A universal app** — the DMG now carries arm64 and x86_64 slices of both
  the app and the bundled ffmpeg, so Intel Macs run natively (previous
  releases were Apple Silicon-only). The packaging step now refuses to ship
  a DMG that lost a slice.

### Reactotron MCP — your app's timeline for AI agents

- **An opt-in MCP server** (Settings ▸ MCP) exposes the Reactotron relay's
  timeline, state, and network data to Claude Code, Cursor, or VS Code over
  localhost HTTP — the same tool and resource contract as the official
  Reactotron desktop, so the upstream setup line works verbatim:
  `claude mcp add --transport http reactotron http://127.0.0.1:4567/mcp`.
- **Private by default** — it binds 127.0.0.1 only, validates Origin,
  supports a bearer token, and redacts sensitive values at the MCP boundary
  with upstream's default rules. An in-feature guide walks through
  connecting an agent and trying the tools.

### Terminal

- **Sessions resume where you left off** — quitting the app, closing the
  Terminal tab, or closing the window remembers each shell's working
  directory; the next open starts one shell per directory, in order. A tab
  you close yourself (⌘W, the ×, or `exit`) is forgotten — closing a tab
  means you're done with it.

### Reactotron & JS Console

- **Independent pane order** — each split timeline pane keeps its own
  newest-first / chronological toggle instead of both flipping together.
- **Clear data and restart** — both consoles' Restart button gains a
  full-data-clear variant behind a confirmation (it signs you out), next to
  the existing cache clear; Reactotron's plain Restart becomes the same
  split button the JS Console has.

### Screen Mirror

- **No more reconnect flash** — switching tabs keeps the mirror session
  alive for a two-minute grace window, so flipping away and back resumes
  instantly. Returning re-targets if you switched devices meanwhile, a
  session that died while hidden reconnects, and a recording always stays
  on its device.

### Polish

- **What's New sheet redesigned** — the release notes render in the app's
  own colors and text size (no more black-on-dark when the app and OS
  themes differ), with a version pill and a link to the full changelog.
- **A gentler GitHub-star nudge** — it recurs every ten launches instead of
  firing once, stops for good after five asks (or one star), and quitting
  with the prompt open no longer replays it every launch.

### Install

Download `Droidective-v3.7.0.dmg` below. Existing installs update in place
via Sparkle.

---

## Droidective v3.6.1

A resize-performance fix: dragging a split divider or resizing the window
with Mirror Screen and streaming log tabs open no longer slows to a crawl.

### Fixes

- **Resizing is smooth with logs streaming** — the log view re-wrapped its
  entire buffer on every tick of a drag, pinning a CPU core; it now re-wraps
  once, when the drag rests. Log feeds also coalesce their updates a little
  more (three refreshes per second instead of eight), which cuts idle CPU
  with a busy logcat tab roughly in half.

### Install

Download `Droidective-v3.6.1.dmg` below. Existing installs update in place
via Sparkle.

---

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
