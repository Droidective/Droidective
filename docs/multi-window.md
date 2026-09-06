# Multi-device windows

One window per device, in parallel. Each window is a **workspace**: its own
selected device, tabs, split panes, terminals and JS console. What can only
exist once — the `adb devices` poll, the tool caches, the feature curation, the
Reactotron and MCP listeners — is shared.

## Why it needed so little plumbing

No feature view knows what a device is. All ~40 read the selection through the
environment:

```swift
@Environment(AppState.self) private var state
.task(id: state.targetSerials.first) { await load(state.targetSerials) }
```

So giving a window its own `AppState` makes every feature in it device-scoped
for free. `AppState` kept its whole public API — everything that moved to
`AppCore` is forwarded — so the change touched 14 files, and only four feature
views among them (the three that own cross-window sessions, plus the collision
banner).

## The split

| `AppCore` (one) | `AppState` (one per window) |
| --- | --- |
| `AppEnvironment` — **one** `adb devices` poll however many windows | `selectedSerial`, `runOnAll`, `selectedBundleId` |
| device / AVD / simulator lists, `deviceDetails`, `adbStatus` | `workspace` (tabs + split panes) |
| `layout` — feature curation, favorites, role, per-window records | `terminals`, `jsConsoleSession` |
| `bundles`, `usageStats` | toasts, notifications, exit guards, recordings |
| `reactotronSession` (port 9090), `mcp` (4567) | sidebar, font zoom, `nsWindow` |
| the workspace registry + window routing | `apkStudio`, `apkOpen` |

`@Observable` registers the read inside a forwarding getter, so `state.devices`
re-renders every window when the core's list changes.

## Window lifecycle — the part that took the work

SwiftUI's `WindowGroup(for:)` is *not* a reliable source of window identity.
Three separate behaviors each produced a duplicate or blank workspace, and the
final design exists to be immune to all of them:

1. **AppKit restores windows** from its saved state, with stale ids, before the
   layout has loaded. → `window.isRestorable = false` at bind. Droidective
   restores its own windows from `LayoutState.windows`; two restorers fight.
2. **SwiftUI persists presented values** across launches, asks for content for
   windows it never shows, and re-presents a stale value *into an existing
   window*. → The `WindowGroup` carries **no value type** at all; each host
   holds a `WorkspaceToken` in its own `@State`, which SwiftUI can neither
   persist nor re-present. On top of that, a workspace handed to a view is
   **provisional** — no registry entry, no restore, nothing written to disk —
   and becomes real only when an `NSWindow` binds to it.
3. **A closing window still re-renders**, which asks for content again. → The
   closing window's identifier is remembered and `bind` refuses it.

The invariant that falls out: **one `NSWindow`, one workspace.** `bind` enforces
it — if the window was showing another workspace, that one is released first,
and the adoption below hands it straight back.

```
                    ┌──────────────────────────────────────┐
  SwiftUI asks for  │  workspace(claiming: hostToken)      │
  content ─────────►│  → memoized, else a PROVISIONAL      │
                    │    (owns nothing)                    │
                    └──────────────┬───────────────────────┘
                                   │  an NSWindow appears
                                   ▼
                    ┌──────────────────────────────────────┐
                    │  bind(window, to: state)             │
                    │   · refuse a closing window          │
                    │   · release any other workspace      │
                    │     holding this window              │
                    │   · ADOPT a workspace with no window │
                    │     (launch restore / parked), or    │
                    │     PROMOTE the provisional          │
                    │   · restore, register, persist       │
                    └──────────────────────────────────────┘
```

**Adoption** is what makes restore and background-mode reopen the same
mechanism: a window that comes up unasked steps into a workspace that is
waiting for one. Only ⇧⌘N / "New Window for Device" mark a window explicitly
fresh so it starts a new workspace instead.

**Closing** a window destroys its workspace when others remain, and *parks* it
when it was the last — the app stays resident (menu bar, hotkeys, Quick
Actions) and reopening comes back to the same tabs, exactly as background mode
always behaved. The park-or-destroy test counts windows on screen, not
workspaces, so a provisional can't tip it.

## Persistence

`LayoutState.windows: [WindowState]` — id, serial, bundle, tab groups, focused
pane, terminal-resume directories. The legacy single-workspace fields
(`tabGroups` / `focusedGroup` / `terminalResumeDirs`) are read once by
`adoptWindows(serial:bundleId:)`, folded into one window, and cleared. Ids are
re-minted per session; claiming a persisted entry removes it, so the array
can't grow by one window per launch.

Everything app-wide (enabled set, sidebar order, role, favorites) stays on
`LayoutState` itself and is shared by every window.

## Tear-off — a tab into a window of its own

Any tab can leave its window: right-click ▸ **Open in New Window**, Tab ▸ **Move
Tab to New Window** (⌃⌘N), **Move to Window ▸** for one that is already open, or
by dragging the chip out of the app and letting go — the window appears where it
was dropped.

**A torn-off tab becomes an ordinary workspace window.** Not a bespoke host: the
pop-out mirror is what that costs — ~200 lines of window plumbing for one
feature that can still only mirror. Because no feature view knows what a device
is, a real workspace window gives all 32 of them tear-off for free, along with
persistence, restore, the quit walk, background parking and the ⌘W monitor.

What the new window inherits, and why:

| | |
| --- | --- |
| Device + app bundle | **inherited from the source.** Every other route to a new window deliberately picks a device *no other window holds* (`firstFreeSerial`); for a moved tab that would swap the device out from under it — you tore off one phone's logcat and got another's. |
| `runOnAll` | inherited, so the tab keeps running against the same set |
| Tabs | exactly the moved one. Home is not seeded — the strip's house button is one click away |
| Sidebar | hidden, and not persisted: a tear-off means "watch this one thing". ⌘B brings it back |
| Frame | the source window's size, positioned so the chip lands back under the cursor, clamped onto the drop screen (`TearOffFrame`) |
| Full View | **not** inherited — it is per window and transient |

### The pieces

| | |
| --- | --- |
| `Workspace.canDetach` / `canDetachToNewWindow` / `detach` | ADBKit. Two rules, differing on one case: a window's *last* tab may move to another open window (consolidating two windows, leaving Home behind) but not to a window of its own, which would just be this window moving. |
| `TabHandoff.seed` | ADBKit. The receiving window's opening state — and it is a `WindowState`, the same record a window persists, so the receiver restores through the path a relaunch already uses. No second restore path to drift. |
| `TabDropRouter` | ADBKit. The one table deciding what a dropped tab does, the tab-drag twin of `FileDropRouter`. |
| `TearOffFrame` | ADBKit, pure geometry. Screen coordinates are y-up, strip insets y-down; the two conventions meeting is why it is worth testing rather than inlining. |
| `AppState.beginHandoff` | The single entry point for every route, so the confirmations are handled once. |
| `AppCore.completeHandoff` | Performs it. |
| `TabDragSource` / `TabDetachPolicy` | App. The AppKit dragging session and the release decision. |

### Ordering is the whole correctness story

The source releases the tab **before** the destination asks for it. Both writes
land on one main-actor turn through `persistTabs` → `noteOpenFeatures`, so an
exclusive feature (`scrcpy`, `js-console`) is never registered in two windows at
once and the destination never comes up on the collision banner for a session
that has already gone. Verified live: moving a live mirror between windows keeps
`adb forward --list` at exactly one `scrcpy_*` entry — the old tunnel removed,
one new one added.

Two consequences fall out of a moved tab keeping its device:

- **Two windows on one device is now the normal case**, not the unusual one.
  The registry already tolerated it; `owner(ofDevice:)` answers with the first,
  and `unclaimed(from:)` still treats it as taken so ⇧⌘N prefers a free device.
- **They tint differently.** The tint tells *windows* apart, not devices, and
  `tintIndex(ofWindow:paletteSize:)` guarantees no two collide. The title
  carries the device name.

### Guards

Moving a tab unmounts its view exactly as closing it does, so the same two
confirmations apply, checked in the order `closeTab` checks them:

- a live recording or unsaved edit → `PendingExit.handoff`, which reuses the
  guard the feature registered ("Recording in progress — leaving will stop the
  screen recording. Save it first, or discard it.") with its usual Stop & Save /
  Discard / Keep Recording. The wording is the *guard's*, not the destination's,
  and stays accurate because a move is a kind of leaving — the guard describes
  the work at risk, which is the same whichever way the tab goes;
- open terminal shells → `TerminalClosePrompt.handoff` ("…closes 3 shells. They
  reopen in the same directories."). Not silent, because killing someone's
  running `npm start` should not be — and the directories ride into the seed via
  `TabHandoff.Carry`, so the new window comes back where it was.

The **Reactotron relay is deliberately not stopped** for a moving tab. It is one
app-wide listener; stopping it would drop every connected client for a tab that
is about to reopen. `stopBackgroundWork(for:reason:)` skips it on `.handoff`,
and `AppCore.reconcileSharedSessions` is the other half of the bargain — if the
move somehow did not land, the relay stops there rather than running on with no
window to reach it.

### The drag

SwiftUI's `.onDrag` cannot answer either question a tear-off needs — was the
drop accepted, and where did it land — and there is no callback that reports
them. So the chip's drag is a real `NSDraggingSource`, started from a SwiftUI
`DragGesture`. The item on the pasteboard is unchanged, so every existing
`.onDrop(of: [.workspaceTab])` target accepts it exactly as before; only the
source half changed. A `DragGesture` is safe inside the strip's `ScrollView`
because trackpad scrolling arrives as `scrollWheel` events, which are not
gestures.

Four things that are easy to get wrong, and are not:

1. **Escape reads exactly like a refused drop**, at wherever the cursor sits —
   so a cancel out over the desktop would open a window the user was busy *not*
   asking for. Detected twice over: a local key monitor, and
   `CGEventSource.keyState` for the key still being held when the session
   reports back.
2. **A refused drop *inside* the app is a miss, not a request.** Released on the
   dead chrome beside the tabs, the tab snaps back.
3. **`WindowGroup` keeps one frame autosave for the whole group**
   (`main-AppWindow-1`, re-stamped over the `droidective-main-N` name `RootView`
   sets — which is why no such frame is ever written), and restores it *after*
   the accessor runs. A torn-off window's frame is therefore re-asserted on the
   next runloop turn, or it lands wherever the last window sat.
4. **The chip's view is gone by the time an accepted drop reports back** — the
   tab moved to another window and its chip was torn down. The source window's
   frame and the chip's position are captured at drag *start*; reading them in
   `endedAt` behind a `guard let window` swallowed the callback entirely.

A tab drag is **app-wide** (`AppCore.tabDrag`), because it can end in another
window. `AppState.draggingTabID` still means "a tab from *this* window", which
is what every existing caller asks. Three places had to widen, and they are the
drop-routing traps CLAUDE.md already documents: every window's drop targets
validate on the app-wide drag, every window's `EditorPane` shield overlay is
live during any tab drag (or dragging into a window whose active tab is APK
Studio silently does nothing), and the hidden-tab file-drop gate reads it too.
`tabDrag` is written twice per drag and never per move — `AppCore` is
`@Observable` and `RootView.body` reads it, so a per-move write would re-render
every open window on every mouse move. The window frames the release decision
needs are captured once per session for the same reason.

## Conflict rules

`WorkspaceRegistry` (ADBKit, pure, 24 tests) mirrors each window's device and
open tabs, and answers three questions: who owns a device, who runs an
exclusive feature on it, and what a window is called.

**Safe to duplicate** — logcat, apps, file explorer, performance, every
instant/toggle/form action. Two `adb logcat`s on one device is normal.

**Exclusive per device** (`exclusiveFeatureIDs`, guarded by a test that every id
is a real feature):

| Feature | What breaks with two |
| --- | --- |
| `scrcpy`, `scrcpy-window`, `screen-record` | two scrcpy sessions = two H.264 encoders on the device |
| `js-console` | the RN inspector proxy hands the target to the newest client and silently kills the previous one |
| `frida-console` | one `frida-server`, one port |

Opening one where another window owns it shows a banner with **Focus Window N**
and **Take Over Here**; take-over closes the tab in the owning window first, so
there is never a moment with two live sessions.

**App-wide** — the Reactotron relay is one listener shared by every window (both
show the same timeline), so closing one window's tab only stops it when no
other window still has it open.

**Selecting** a device another window holds focuses that window instead of
duplicating it; ⌥-click opens it here anyway.

## Routing

`AppCore.frontmost` (last key window) is where the menu bar, global hotkeys,
Finder `.apk`/`.aab` opens, update toasts and Settings act. Windows report
themselves via `NSWindow.didBecomeKeyNotification`. App activation for the poll
rate comes from `NSApplication`, not per-window `scenePhase` — with several
windows those fire independently and one going inactive would widen polling
while another is in use.

Quit walks the windows: the first with losable work is brought forward and
prompted, and each resolution moves to the next; when all are clear the shared
listeners stop, every window's terminal directories are snapshotted, and the
layout is flushed before termination proceeds.

`WindowMinSizeGuard` and `ResizeActivity` were single-window singletons that
replaced their observers on each attach — every window but the newest lost its
size floor and its resize-freeze. Both now observe app-wide and track a set.

## Look

The window title is the active tab, prefixed with the device once more than one
window is open ("Medium Tablet — Logcat"), which is what names them in the
Window menu and Mission Control.

The title placement is the system's — a plain `.navigationTitle`, exactly as
before multi-window.

> **If it looks left-aligned in your dev build, that's the SDK, not the app.**
> macOS 26 moves window titles beside the traffic lights for apps *linked
> against the macOS 26 SDK*. Xcode 26 links local builds that way; CI's
> `macos-15` runner links against the 15.x SDK, so shipped builds keep the
> centered title. Verified with `otool -l`: released v3.8 is `sdk 15.5`, a local
> debug build is `sdk 26.2`, same source. Don't "fix" this in app code — the
> routes all end badly (`.navigationTitle` renders a second leading item, a
> toolbar principal item gets macOS 26's glass capsule with no
> macOS 15-compilable way to remove it, and content drawn into the titlebar via
> `.fullSizeContentView` or an `NSTitlebarAccessoryViewController` is collapsed
> or clipped).

**Only the extra windows are tinted.** The app has one accent, so the first
window's device icon is always `.brandAccent` — a single-window session looks
exactly as it did before multi-window, and opening a second window never
repaints the first. Each additional window takes a color from `DeviceTint`'s
palette (slot by window position via
`WorkspaceRegistry.tintIndex(ofWindow:paletteSize:)`, so two can't collide), and
only on the device-status icon — never the rest of the interface.

## Verified live

Against two Android emulators: two windows on two devices with independent
tabs; restore across relaunch; close one window (entry dropped) and the last
(parked, reopens to the same tabs); device disconnect retargeting to a free
device; the mirror collision banner and take-over; the chained quit prompt with
shells in both windows; per-window terminal resume; the device picker's
"in Window 1" row focusing rather than stealing.

## Known limits

- `tabSplitFraction` and `sidebarWidth` are shared `@AppStorage`, so the split
  ratio and sidebar width are app-wide rather than per window.
- `runOnAll` is per-window in memory but persists to one shared pref, so the
  last window to change it wins on the next launch.
