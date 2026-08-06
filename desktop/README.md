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
| `src/lib/ordering.ts` | drag-reorder math — ADBKit's `SidebarOrdering` |
| `src/lib/layout.ts` | what the window remembers between launches |
| `src/lib/icons.ts` | one lucide glyph per registry id — the wire carries none |
| `src/lib/logbuffer.ts` | the log feed's ring buffer and its gap markers |
| `src/lib/files.ts` | the File Explorer's rules — paths, selection, batches |
| `src/lib/fields.ts` | form values → run parameters |
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
gap markers, every device property searchable, and the file explorer.

The file explorer is the first screen here that **writes** to a device.
Everything on it — a new folder, a delete, a copy or move, a pull — goes over
one of four `/v1/files/*` routes, and every path travels **verbatim**:
device-shell quoting happens once, in ADBKit's `FileExplorerService`, so a
path escaped on the way out would be quoted twice and address a different
file. Delete needs a second press, the rule the app verbs already use. A pull
lands in `~/Downloads/Droidective`, the folder `export_text` writes to, and
the reply says where so the result can offer Show in folder.

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

Not yet: hotkeys, and most of the full-screen views (crash catcher,
performance…), which are `kind: "view"` in the registry and need whole panels.
They are listed in the sidebar and open a tab that says so, rather than being
hidden — a feature the Mac has and this app does not is worth knowing about.
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

`docs/desktop-parity.md` is the tracker: every registry feature, what its
macOS view actually offers, and how far this app has got. The shell items at
the top (tabs, split panes, sidebar, palette, hotkeys) come before the
screens — porting a screen into a window with no tabs means reworking it once
the tabs arrive.

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
