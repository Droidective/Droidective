# Droidective for Windows and Linux

The Tauri 2 + React UI over [`droidectived`](../droidectived) — phase 3 of the
port (see [`docs/cross-platform.md`](../docs/cross-platform.md)).

macOS keeps its native SwiftUI app and never talks to the daemon. This is a
second UI over the same ADBKit logic, not a replacement.

## Shape

```
Tauri (Rust)  ──spawns──▶  droidectived --port 0 --token-file … --parent-pid …
    │  HTTP + WebSocket, 127.0.0.1 only, bearer token
    ▼
webview (React)  ──invoke()──▶  Rust commands
```

**The webview never talks to the daemon directly, by design.** The daemon
refuses any request whose `Origin` is not loopback and sends no CORS headers,
so a webview origin (`tauri://localhost`, `http://tauri.localhost`) is a 403 —
which is the guard working, not a bug to route around. Everything goes through
a Rust command, so the bearer token stays in the Rust process and the
capability file grants the webview no shell, filesystem, or HTTP permission of
its own.

| | |
| --- | --- |
| `src/lib/wire.ts` | the daemon's JSON shapes, mirrored |
| `src/lib/daemon.ts` | the typed `invoke()` surface — the only way to reach the daemon |
| `src/lib/palette.ts` | search ranking, ported from ADBKit's `PaletteSearch` |
| `src/lib/sidebar.ts` | which features the sidebar lists, grouped and ordered |
| `src/lib/tabs.ts` | the open tabs and what gets focus on close — ADBKit's `TabState` |
| `src/lib/workspace.ts` | one or two panes and the rules between them — ADBKit's `Workspace` |
| `src/lib/panes.ts` | the split's clamp and divider geometry — ADBKit's `PaneSplit` |
| `src/lib/terminal.ts` | terminal panes — ADBKit's `TerminalSplitTree` — plus the pty's base64 |
| `src/lib/menuKeys.ts` | which keystrokes the native menu owns, so the page defers |
| `src/lib/ordering.ts` | drag-reorder math — ADBKit's `SidebarOrdering` |
| `src/lib/layout.ts` | what the window remembers between launches |
| `src/lib/icons.ts` | one lucide glyph per registry id — the wire carries none |
| `src/lib/logbuffer.ts` | the log feed's ring buffer and its gap markers |
| `src/lib/files.ts` | the File Explorer's rules — paths, selection, batches |
| `src/lib/crashes.ts` | the Crash Catcher's rules — filters, the clear watermark |
| `src/lib/fields.ts` | form values → run parameters |
| `src/lib/targets.ts` | who an action runs on — ADBKit's `targetSerials` and its guards |
| `src/lib/runner.ts` | running one feature across one or many devices, as one answer |
| `src/lib/hotkeys.ts` | recording, matching and formatting a shortcut |
| `src/lib/sidebarMode.ts` | pinned or Dock-style — ADBKit's `SidebarVisibility` |
| `src/lib/zoom.ts` | the ⌘=/⌘- steps, the Mac's own |
| `src/lib/endpoint.ts` | when a wireless button lights up (the daemon owns the real answer) |
| `src/lib/deeplinks.ts` | editing one app's saved links, and how a launch reads |
| `src/lib/doctor.ts` | which tools the Doctor checks, and what a report adds up to |
| `src-tauri/src/daemon/` | spawning, the HTTP client, and the stream socket |

The pure modules are where the logic lives and where the tests are, mirroring
the ADBKit/App split: components render, they do not decide.

## Running it

Needs [Rust](https://rustup.rs), Node 22, and a Swift toolchain for the daemon.

```
make desktop-dev     # builds the daemon sidecar, then `tauri dev`
make desktop-test    # typecheck + oxlint + vitest + cargo clippy + cargo test
make desktop-build   # a release bundle for the host platform
```

The daemon is a **sidecar**: `scripts/build-daemon-sidecar.sh` builds it with
`swift build` and installs it as
`src-tauri/binaries/droidectived-<target-triple>`, which is the name Tauri
resolves. It is gitignored — build it, do not commit it.

## What works so far

A device picker, a grouped sidebar over every feature the engine implements,
and a tab strip: clicking a feature opens it in its own tab, tabs drag to
reorder, and Home leads the strip permanently. An action feature renders from
its registry fields — forms, toggles, destructive confirmation — which is why
most of the registry works with no per-feature code. The screens built by hand
so far are the installed-app browser with its verbs, live logcat with visible
gap markers, every device property searchable, the file explorer, and the
crash catcher.

**Deep links share the Mac's file.** The daemon owns the store, under the same
support dir the Mac app uses, so a developer running both has one
`deep-links.json` rather than two. The Mac keys it by saved-bundle id and this
keys it by package id — the two sets sit side by side without merging, which is
the honest state of it until this app grows a bundle store of its own. An edit
writes the whole list for that one key, atomically, so neither app can lose the
other's entries in a swap.

**Wireless adb** goes over one route with the verb in the body, and the endpoint
travels as the phone displays it: `ConnectionService.parseEndpoint` is the
authority on what adb accepts — bracketed and bare IPv6, a truncated IPv4, a
port out of range — so it stays daemon-side and the two apps cannot disagree.
This side only decides when a button lights up, deliberately permissively
(`lib/endpoint.ts`); anything it lets through comes back as adb's own refusal,
which says more than a greyed-out button. Pairing insists on the explicit
pairing port, because that port is random per session and defaulting it would
target the wrong one; a successful pair carries the endpoint the device then
advertised over mDNS, so there is usually nothing left to type.

The file explorer is the first screen here that **writes** to a device.
Everything on it — a new folder, a delete, a copy or move, a pull — goes over
one of four `/v1/files/*` routes, and every path travels **verbatim**:
device-shell quoting happens once, in ADBKit's `FileExplorerService`, so a
path escaped on the way out would be quoted twice and address a different
file. Delete needs a second press, the rule the app verbs already use. A pull
lands in `~/Downloads/Droidective`, the folder `export_text` writes to, and
the reply says where so the result can offer Show in folder.

The crash catcher reads the same buffer the Mac does, and decides nothing about
it: `CrashExtractor` picks the buffer (falling back to `main` when `crash` is
empty) and `CrashParser` says where one crash ends, so the two apps can never
disagree about how many crashes a device has. Clear Buffer empties
`logcat -b crash` and then remembers a high-water mark, because the fallback
would otherwise resurface the same crashes on the very next fetch.

Open tabs stay mounted while they are in the background rather than
unmounting, so a backgrounded tab keeps its log stream and its loaded lists.
The sidebar arrangement and the open tabs are saved to `localStorage` and
restored on launch; a saved tab naming a feature this build no longer has is
dropped rather than restored as a blank pane.

The app chosen in **Apps** is the app other features act on: a `needsBundle`
feature (Monkey) is disabled until one is picked, and every other action gets
it as optional context — the rule `AppState.run` applies on the Mac. The
choice is owned by `App.tsx`, not the Apps pane, so switching tabs keeps it
and switching *device* drops it.

Hub members are listed standalone, unlike the Mac's sidebar: this app has no
hub screens, so hiding them would make them unreachable rather than merely
relocated.

Panes split with **Ctrl/⌘ + \\** (not ⌘D — Ctrl+D is end-of-input in a Linux
shell, and this is the binding VS Code already trained everyone on), by a tab's
right-click menu, or by dragging a tab onto the trailing edge of the pane. The
divider clamps to 30–70% and its position is saved.

The sidebar can be pinned or Dock-style: the device bar's leading button
switches, hovering the window's left edge peeks, and **Ctrl/⌘ + B** toggles.
**Ctrl/⌘ + = / −** zooms the whole UI through the Mac's own eight steps, with
Ctrl/⌘ + 0 for Actual Size.

**Per-feature shortcuts** are recorded in Settings ▸ Hotkeys or from a sidebar
row's right-click, with the Mac's rules — one of Ctrl/Alt/⌘ at minimum, Esc
cancels, Backspace clears, an instant action runs where anything else opens.
Two differences the recorder states outright: they fire while this window has
focus (the OS registration arrives with the Quick Actions panel) and a toggle
opens rather than running, because the Mac flips it from override state this app
does not track. Combinations the shell owns are refused *by name* — a window
shortcut cannot outrank the shell the way an OS-registered one does — and the
one list of them lives in `lib/hotkeys.ts` beside `useShellShortcuts`.

The device bar is the Mac's: a dropdown with the devices, the AVDs that are not
already running, wireless pair/connect, and Manage emulators; a disconnect
button beside a wireless device; and **Run on all**, which appears only with
more than one ready device *and* a focused feature the registry says fans out.

**The menu bar is native, and it owns its accelerators.** A webview has no menu
of its own, so `src-tauri/src/menu.rs` declares one — File / Edit / View / Tab /
Help / Go, mirroring `ADTApp.swift`'s `.commands` block — and forwards each click
to the page, which is where the state lives (`useMenuCommands`). The page
*defers* on the keys the menu binds (`lib/menuKeys.ts`), because both answering
Ctrl+W would close two tabs; `menuKeys.test.ts` reads the Rust table to keep the
two lists identical. The terminal's items grey out with no terminal open. Three
accelerators moved for platform reasons and `docs/desktop-parity.md` item 16 has
the table.

**The Terminal is real shells, not a log view.** `openTerminal` subscribes to
the daemon's `pty` topic and xterm.js draws it: a login shell per tab, panes
split from the ported `TerminalSplitTree`, the size sent on the open so nothing
re-wraps after the first prompt, and the selected device exported as
`ANDROID_SERIAL` so adb inside needs no `-s`. Bytes ride base64 both ways —
output because a pty read can stop mid-character, input because Ctrl-C is a byte
no JSON string carries. Hidden tabs stay mounted: unmounting one would hang up
its shell. Shortcuts are Ctrl+Shift+T/W/D/E, and the Shift is the platform's
doing — a bare Ctrl+letter belongs to the program in the terminal. Windows has
no pty yet (ConPTY is a different API) and the pane says so.

Not yet: most of the full-screen views (the mirror, Reactotron, the JS console…),
which are `kind: "view"` in the registry and need whole panels. They are listed
in the sidebar and open a tab that says so, rather than being hidden — a feature
the Mac has and this app does not is worth knowing about.
`docs/desktop-parity.md` is the tracker.

## Two platform requirements for drag and drop

Both are needed before HTML5 drag works at all, and both fail silently:

- **`"dragDropEnabled": false`** in `tauri.conf.json`. Tauri's native
  drag-and-drop handler is on by default and swallows the webview's own drag
  events. Turning it off means a future drop-an-APK-on-the-window feature has
  to handle the drop in the webview rather than in Rust.
- **`-webkit-user-drag: element`** on `[draggable="true"]` (`index.css`).
  The app sets `user-select: none` — it is a desktop chrome, not a document —
  and WebKit refuses to start a drag on unselectable content. Chromium
  (WebView2, Windows) does not care; WebKitGTK on Linux does.

## Parity with the Mac app

**The Mac's UI is this app's UI.** The Mac app is the proven one, and the point
of the port is that someone moving between the two does not have to relearn
anything. Where a control exists on both it looks and behaves the way
`App/Sources/` makes it behave: same wording, same icon, same confirmation
shape, same gesture. A double-click to open a folder stays a double-click even
though single-click is the better web idiom; a `confirmationDialog` stays a
dialog and does not become a button that arms itself. If an idea really is
better, it goes into the Mac app first and this one follows.

Two standing exceptions, both named where they occur: a keyboard shortcut whose
modifier has no equivalent here (the split is **Ctrl/⌘ + \\**, because Ctrl+D
is end-of-input in every Linux shell), and a label that names a platform.

`docs/desktop-parity.md` is the tracker: every registry feature, every window
and panel and menu the Mac has, what each actually offers, and how far this app
has got. **Everything is in scope** — Settings and its seven tabs, the
notification panel behind the device bar's bell, toasts, the Command Log, the
role picker, the Manage Features catalog, About & Feedback, the menu bar, drag
and drop. Only `ios-logs` and `push-notification` are out, and only because
`xcrun simctl` is a macOS toolchain rather than anything about a device.

The shell items come before the screens: porting a screen into a window with no
tabs means reworking it once the tabs arrive, and the same is true of a screen
that reports into an inline banner before the toasts exist.

## Conventions

- **Test the pure modules, not the components.** Same rule as ADBKit: if a
  component is making a decision worth testing, the decision belongs in
  `src/lib/`.
- **`src/lib/__fixtures__/features.json` is real daemon output**, captured from
  `POST /v1/features/list`, not hand-written. Regenerate it by running the
  daemon and re-capturing; do not edit it by hand.
- **No component library.** `clsx` + `tailwind-merge` and a handful of
  hand-written controls in `src/components/Controls.tsx`. Worth revisiting when
  the surface grows past a few forms.
- **Icons are lucide, one per registry id**, listed in `src/lib/icons.ts`. The
  daemon deliberately does not send `FeatureDef.icon` — SF Symbol names mean
  nothing off Apple — so the pairing is made here, and a test fails if a
  feature arrives without one rather than letting it inherit a category glyph.
- Exact dependency versions, no `^`. A desktop app that builds differently next
  month is a support problem.
