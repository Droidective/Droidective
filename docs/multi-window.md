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
2. **SwiftUI persists presented values** across launches and asks for content
   for windows it never shows, and it re-presents a stale value *into an
   existing window*. → A workspace handed to a view is **provisional**: no
   registry entry, no restore, nothing written to disk. It becomes real only
   when an `NSWindow` binds to it.
3. **A closing window still re-renders**, which asks for content again. → The
   closing window's identifier is remembered and `bind` refuses it.

The invariant that falls out: **one `NSWindow`, one workspace.** `bind` enforces
it — if the window was showing another workspace, that one is released first,
and the adoption below hands it straight back.

```
                    ┌──────────────────────────────────────┐
  SwiftUI asks for  │  workspace(claiming: presentedID)    │
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

It is drawn **centered**. macOS 26 lays a window title out leading, against the
traffic lights (confirmed at runtime: no toolbar, `titleVisibility == .visible`,
still left) — and the only placement the system centers is a toolbar's
principal item. So `CenteredWindowTitle` puts the title there and writes
`window.title` itself. Deliberately not `.navigationTitle`: on macOS 26 that
renders as *another* leading item, duplicating the centered one. On macOS 26 the
item carries the system's own glass capsule; removing that needs
`sharedBackgroundVisibility`, which is macOS 26-only and would not compile on
CI's macOS 15 SDK.

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
