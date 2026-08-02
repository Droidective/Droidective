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
| `src/lib/logbuffer.ts` | the log feed's ring buffer and its gap markers |
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

Device picker, the action palette (search, forms, toggles, destructive
confirmation), and live logcat with visible gap markers.

Not yet: the full-screen view features (file explorer, apps, crash catcher,
performance…), which are `kind: "view"` in the registry and need whole panels
rather than a form. They are filtered out of the palette rather than shown as
dead rows. Hub members *are* listed standalone — this app has no hub screens,
and they are most of the runnable surface.

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
- Exact dependency versions, no `^`. A desktop app that builds differently next
  month is a support problem.
