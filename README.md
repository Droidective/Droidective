<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/icon.png">
    <source media="(prefers-color-scheme: light)" srcset="docs/icon-light.png">
    <img src="docs/icon.png" width="120" alt="Droidective app icon">
  </picture>
</p>

<h1 align="center">Droidective</h1>

<p align="center">
  <em>A native desktop companion for Android and React Native debugging.<br>
  61 adb-powered tools in a Raycast-style command palette — no terminal required.</em>
</p>

<p align="center">
  <a href="https://github.com/Droidective/Droidective/actions/workflows/ci.yml"><img src="https://github.com/Droidective/Droidective/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/Droidective/Droidective/releases/latest"><img src="https://img.shields.io/github/v/release/Droidective/Droidective?label=release" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Windows%20%C2%B7%20Linux-beta-orange" alt="Windows and Linux in beta">
  <img src="https://img.shields.io/badge/Swift-6-orange" alt="Swift 6">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT license"></a>
</p>

<p align="center">
  <a href="https://droidective.com/assets/demo.mp4">
    <img src="docs/demo.gif" width="760" alt="Droidective demo">
  </a>
  <br>
  <em>▶ <a href="https://droidective.com/assets/demo.mp4">Full-resolution video</a></em>
</p>

<p align="center">
  <a href="https://droidective.com/">Website</a> ·
  <a href="https://github.com/Droidective/Droidective/releases/latest/download/Droidective.dmg">Download for macOS</a> ·
  <a href="https://github.com/Droidective/Droidective/releases">All releases</a> ·
  <a href="RELEASE_NOTES.md">Release notes</a> ·
  <a href="docs/README.md">Engineering docs</a>
</p>

---

## Contents

- [What it is](#what-it-is)
- [Install](#install)
- [Requirements](#requirements)
- [Features](#features)
- [The workspace](#the-workspace)
- [Reactotron, and an MCP server for AI agents](#reactotron-and-an-mcp-server-for-ai-agents)
- [Platforms](#platforms)
- [Repository layout](#repository-layout)
- [Architecture](#architecture)
- [Building from source](#building-from-source)
- [Testing](#testing)
- [Releases and channels](#releases-and-channels)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)

---

## What it is

Everything you normally do to an Android device from a terminal — `adb shell`,
`dumpsys`, `pm`, `logcat`, `scrcpy`, `bundletool`, `jadx` — with a searchable UI
in front of it, on the device you have selected, with the output rendered rather
than printed.

Hit `⌘T`, type "battery", press ⏎ — the device is at 15%. Type "logcat" and the
stream opens filtered to your app. Drag an APK onto the mirrored screen and it
installs on that phone. There is no adb syntax to remember and no serial to
paste, because the device bar already knows which device you meant.

Three things make it more than a button wrapper:

- **It is a workspace, not a launcher.** Tabs, split panes, one window per
  device, real PTY terminals, and full-screen panels for the things that need
  them — a file explorer, an app browser, a crash browser, a live performance
  chart, an HTTP client, a mirror wall of six devices at once.
- **The logic is a testable Swift package**, not view code. `ADBKit` has no UI
  imports and 2,000+ tests that run without a device, an emulator, or Xcode —
  which is also what let it be ported to Windows and Linux without rewriting
  anything.
- **It is honest about what it ran.** Settings ▸ Command Log keeps the exact adb
  command behind every action you took, with its output, ready to paste into a
  bug report.

**Status.** macOS is the shipping app and is feature-complete: v3.11.0, 61
features, Developer ID-signed and notarized, self-updating through Sparkle.
Windows and Linux ship on the **beta** channel from the same `main` — 29 of the
32 full-screen views are ported, the mirror and the Terminal included, and the
seven remaining catalog features are actions that run from the palette. They are
not signed and not yet at parity inside those screens. See
[Platforms](#platforms).

---

## Install

### macOS (stable)

Download `Droidective.dmg` from [the latest release][latest], open it, and drag
**Droidective** to **Applications**.

The app is Developer ID-signed and notarized by Apple, so it opens normally — no
Gatekeeper warning, no `xattr` workaround. Builds are universal (Apple silicon
and Intel), and the app keeps itself current: updates download and stage in the
background, and a "Relaunch to update" pill appears in the sidebar when one is
ready. Opt into pre-releases in **Settings ▸ General ▸ Updates ▸ Receive beta
updates**.

[latest]: https://github.com/Droidective/Droidective/releases/latest

### Windows and Linux (beta)

Published on **beta releases only** (`vX.Y.Z-beta.N`) — look for a pre-release
on the [releases page](https://github.com/Droidective/Droidective/releases).
They carry the ports' own version line (currently `0.0.5-beta.1`), not the Mac's:

| Platform | Artifacts |
| --- | --- |
| Windows x86\_64 | `Droidective-<port-version>-windows-x86_64-setup.exe` (NSIS), `…-windows-x86_64.msi` |
| Linux x86\_64 | `Droidective-<port-version>-linux-x86_64.deb`, `…-linux-x86_64.AppImage` |
| Daemon only | `droidectived-<port-version>-{macos-universal,linux-x86_64,windows-x86_64}` |

These are not signed or notarized, and they are early — read
[Platforms](#platforms) before installing one. Linux needs `webkit2gtk-4.1` and
GTK 3 (the `.deb` declares them).

---

## Requirements

|   | Needed for |
| --- | --- |
| **macOS 14 (Sonoma)+**, or Windows 10+/a modern Linux desktop for the beta ports | running the app |
| **[Android platform-tools][pt]** (`adb`) | everything device-related |
| Android SDK **`emulator`** *(optional)* | listing, launching, wiping AVDs |
| **Java** *(optional)* | `.apks` installs via bundletool, APK signing — a system JDK is used if present, otherwise a Temurin JRE is downloaded on demand |

[pt]: https://developer.android.com/tools/releases/platform-tools

`adb` is found automatically via `ANDROID_HOME`, `~/Library/Android/sdk`,
`~/Android/Sdk`, `%LOCALAPPDATA%\Android\Sdk`, the standard install prefixes, and
finally your login shell's `PATH`. **Settings ▸ Doctor** reports what it found
and links to the download when something is missing — the app never installs
tools behind your back.

**Nothing else to install.** The scrcpy server payload, a static universal
`ffmpeg`, `bundletool`, and `uber-apk-signer` ship *inside* the app bundle. jadx,
apktool, frida-server/-gadget and the Temurin JRE download on first use from
their GitHub releases, with their asset digests verified, into
`~/Library/Application Support/Droidective/tools` — sized and removable in
**Settings ▸ Tools**.

---

## Features

61 features, searchable from the palette (`⌘T`). Related actions are gathered
into **hub** screens — React Native, Simulate, Connection, Apps, APK Studio — so
the sidebar stays short while the members remain searchable and hotkey-able; the
catalog therefore manages 39 entries. Every feature is enabled by default; the
catalog (`⌘.`) is for turning *off* what you don't want.

### Logs and diagnostics

- **Logcat** — live stream in aligned columns: level chips, hashed tag colours,
  process names resolved from a `ps` snapshot, level/app/tag/text filters, a `⌘F`
  find bar that highlights and steps through matches *without* hiding lines,
  click-to-hold-tail, and export.
- **Crash Catcher** — a multi-crash browser, not a log dump: Java, native, React
  Native and ANR crashes split into a filterable list, watch mode, and
  Slack/Jira-ready formatting.
- **Performance Monitor** — per-core CPU, RAM, FPS, network and per-process usage
  charted live, recorded, and exported to JSON/CSV.
- **Bug Report** — one click to a `bugreport` zip.
- **Root Status** — what su/root actually looks like on this device.
- **iOS Logs** — the same pane over a booted iOS Simulator's unified log
  (`simctl spawn log stream`), app-scoped, with freeze-on-scroll and an
  "N new" pill.

All four streaming feeds pace themselves by whether anyone can see them and by
how busy the app already is — four times a second on screen and in front, once a
second behind another app, every five seconds hidden behind another tab. Hidden
is a *pace*, not a pause: nothing is dropped, and returning flushes immediately.

### Screen and capture

- **Mirror Screen** — scrcpy-quality mirroring built in (the bundled scrcpy
  server, decoded and rendered natively — no desktop scrcpy install): max size,
  bit-rate, FPS, view-only, turn screen off, show touches. Pop it out into its
  own window per device (`⌃⌘M`), and tile the open ones from the Window menu.
- **Mirror Wall** — up to six devices side by side in one pane, each fully
  interactive, each its own session at a quality that steps down as tiles are
  added. Reorder by dragging a tile's caption strip; break any tile out into its
  own window.
- **Drop a file on any mirror** — an app package installs on *that* device (with
  a prompt naming the version it is moving from and to, and an
  Uninstall & Install recovery for a signature mismatch); anything else copies to
  `/sdcard/Download` and is handed to the media library, with a real percentage
  and a cancel.
- **Screenshot** — capture straight to disk from the sidebar, a hotkey or the
  menu bar, or open the capture in an annotation editor (pen, highlighter,
  shapes, arrows, text, solid or blurred redaction, zoom, crop, undo/redo) that
  writes nothing until you Save or Copy.
- **Screen Record** — max size, bit-rate, FPS and time limit, recorded through a
  headless mirror session rather than the desktop scrcpy, plus **audio**: the
  device's playback *or* its own microphone, alongside the Mac's microphone,
  mixed into one AAC track with a level meter and per-source mute (mute writes
  silence, so the timeline stays continuous and unmuting is instant).
- **Video Editor** — trim, crop and export through the bundled ffmpeg to MP4,
  MOV, MKV, WebM or GIF; opens 15 input containers, and probes the file's actual
  codec rather than its extension.
- **Demo Mode** — a clean status bar for screenshots.

### React Native

- **Reactotron** — the relay built in: a filterable timeline of every command
  your app sends, JSON payload trees with find-in-object, per-pane sort and
  filters, filter-aware export, an automatic `adb reverse` with retries that
  re-applies itself across an app restart, and Restart App with an optional
  bounded cache clear. Rows select with ⌘-click / ⇧-click / drag, and `⌘C`
  copies whole events — summary plus complete payload.
- **JS Console** — a Hermes Chrome-DevTools-Protocol console over Metro: Chrome's
  own value formatting, `console.group` nesting, `console.table` grids, ANSI
  colours from the dev server, and Metro symbolication back to your own source
  file. Survives sleep, app relaunch and Metro restarts.
- **The hub** — dev menu, Reload JS, saved deep links per app, simulate process
  death, set dev-server host.

### App management

- **Apps** — every user and system app, searchable by name, version or bundle id,
  with live permission control and the per-app verbs (open, restart, force stop,
  clear cache/data, disable, uninstall) in the detail pane.
- **Install App** — every Android package format: `.apk`, `.apks` (via
  bundletool), `.xapk` and `.apkm` (unpacked, narrowed to this device's ABI,
  density and languages, installed as one `install-multiple` transaction, with
  OBB expansions pushed). Double-clicked `.apk`/`.aab` files open in the app.
- **App Info · Permissions · Memory Usage · Sandbox Browser** — manifest and APK
  pull, runtime permission toggles, live `meminfo`, and a `run-as` browser of the
  app's private data directory.
- **Copy Current Activity · Copy Foreground Bundle ID · Monkey Test.**

### APK and security

- **APK Studio** — one workspace over a loaded APK: **Inspect** (manifest,
  permissions, SDK levels, signing certificates via aapt2 + apksigner),
  **Decompile** (jadx and apktool, with a browsable source tree and search),
  **Recompile** (`apktool b`), and **Sign** (including creating a keystore — the
  password goes through a 0600 temp file, never argv).
- **AAB to APK** — bundletool universal APK with optional release-keystore
  signing.
- **Frida** — ABI-matched frida-server / frida-gadget setup.

### Device state

- **File Explorer** — browse, copy/cut/paste, delete, new folder, push from the
  Mac, pull to it (with a real progress percentage against the source size).
- **Device Info** — searchable: RAM, storage, battery health and cycle count,
  CPU, app counts, and every `getprop`.
- **Simulate** hub — fake battery, dark mode, font & density, animation scale,
  locale, network toggles, HTTP proxy, and iOS push notifications. Every write is
  tracked as a **resettable override**, so you can put the device back.
- **Developer Settings** and **System Restrictions** — the Developer Options
  toggles adb can actually reach, in one table.
- **Wi-Fi** and **Private DNS** panels.

### Connection

- **Wireless ADB** — guided from the device dropdown: **pair by QR code** (show
  the code, point the phone at it, done — no random pairing port to find and no
  six-digit code to beat the clock), pair with a typed code, connect to an
  `ip:port`, or bootstrap USB → Wi-Fi with one click. A successful pair
  auto-connects over the endpoint the device then advertises via mDNS.
- **Emulators & Simulators** — list, launch, cold-boot, wipe data, relaunch and
  stop your Android Studio AVDs; booted iOS Simulators appear in the same device
  bar.
- **Network Speed** — download/upload over time, per interface, recorded and
  exported.
- **Reverse Port · Copy Device IP · Disconnect · Run on all devices.**

### Input

- **Send Text** — type text, URLs or symbols on the device, including Unicode and
  emoji via ADBKeyboard (offered and installed for you when the text needs it).
  Reusable snippets with `{clipboard}` and `{ip}` placeholders, ranked by recency.

### Tools

- **Terminal** — real PTY login shells in tabs, with the selected device exported
  as `ANDROID_SERIAL` so adb inside needs no `-s`. Tabs split into panes
  (`⌘D`/`⇧⌘D`), a new shell inherits the focused shell's working directory, drops
  of files type their quoted paths, and an implicit teardown (quit, tab close)
  snapshots each tab's cwd so the next open resumes there. The tab list sits on
  the left rail or as a Chrome-style top strip.
- **API Testing** — a device-free HTTP client: seven methods, six body kinds,
  five auth kinds, nested folders, Postman collections and environments in and
  out, `{{variable}}` scopes with unresolved ones flagged before sending,
  assertions on status/timing/body/header/JSON-path, a collection runner, code
  generation to six targets, and cURL paste-to-parse. Response pane with
  pretty/raw body, image preview, cookies, timing breakdown and redirect chain.
- **Custom Commands** — one free-typed (even multi-line) command line. A leading
  `adb` token infers the adb kind and runs as a tokenized argument vector, never
  a shell; anything else goes through your login shell so aliases resolve.
  `{bundleId}` / `{serial}` / `{clipboard}` / `{ip}` placeholders, output shown
  inline, in the in-app Terminal, or in your Mac's default terminal.

### iOS Simulators

Booted iOS Simulators sit in the same device bar, driven by `simctl`.
Screenshot, dark mode, demo mode, fake battery, deep links and the emulator
manager work against both platforms; push notifications and iOS Logs are
Simulator-only. Anything Android-only says so, with a switch-device button.

---

## The workspace

- **Command palette** (`⌘T`) over every feature, ranked, with keyword matching
  that also surfaces the hub a folded-in action lives on — searching "battery" or
  "force stop" finds the Simulate and Apps hubs.
- **Multi-window** — one window per device (`⇧⌘N`, or New Window for Device).
  Each window has its own device, tabs and terminals; app-wide state (the device
  poll, tool caches, feature curation, the Reactotron and MCP listeners) is
  shared. A feature that cannot run twice on one device — the mirror, screen
  record, the JS console, Frida — shows a Focus / Take Over banner instead of
  racing.
- **Tabs and split panes** — Home leads the strip permanently, `⌃1`–`⌃9` selects,
  tabs drag to reorder or onto a pane edge to split, the divider clamps to
  30–70%.
- **Full View** (`⇧⌘F`) hides the sidebar, device bar and tab strip and takes the
  window full screen.
- **Sidebar** — grouped by category, drag to reorder features or whole groups,
  pinned favourites, `⌘1`–`⌘0` quick-select, and a Dock-style auto-hide mode
  (`⌘B`).
- **Roles** — pick Android Developer, React Native Developer, iOS Developer,
  QA / Tester, Support / Triage or Security / Pentest on first launch for a
  curated, ordered starting set. Manage it any time from the catalog (`⌘.`).
- **Hotkeys** — a per-feature shortcut for anything in the registry, recorded
  live in Settings ▸ Hotkeys, plus global hotkeys that work while the app is in
  the background.
- **Quick Actions panel** — a non-activating Raycast-style mini app on a global
  hotkey: every enabled instant/toggle/form action, saved custom commands,
  Manage Apps, Emulators and Install APK. With more than one device connected,
  a device-scoped action pushes a pick-device screen first, where `⌘⏎` runs on
  all of them for the features that fan out.
- **Background mode** — closing the main window keeps Droidective resident in the
  menu bar for the hotkeys and the panel, stops the kept-alive sessions, and
  drops the Dock icon. `⌘Q` still quits.
- **Appearance** — light/dark/auto, a custom accent, a custom window background,
  `⌘=`/`⌘-` font zoom, and a translucent window (opacity, blur and film grain
  sliders) that every pane, card, bar and terminal respects.
- **Command Log** — Settings keeps the exact adb command behind each action you
  took, with output. Background polling is deliberately excluded.
- **Notifications and toasts** — an in-app notification panel behind the device
  bar's bell, mirrored to macOS Notification Center.
- Every pull asks where to save, defaulting to `~/Downloads/Droidective`.

---

## Reactotron, and an MCP server for AI agents

Droidective embeds the Reactotron relay, so a React Native app configured for
Reactotron reports into it with no desktop Reactotron running. On top of that it
serves the same data to AI agents over a localhost **Streamable HTTP MCP
server** — the same 10-tool / 8-resource contract as the official Reactotron
desktop's embedded server:

```sh
claude mcp add --transport http reactotron http://127.0.0.1:4567/mcp
```

Turn it on in **Settings ▸ MCP** (off by default). It binds to 127.0.0.1 only,
validates the `Origin`, optionally requires a static bearer token, and **redacts
by default** at the MCP boundary — the Reactotron UI itself is never redacted —
with upstream's two opt-out keys. It is strictly downstream of the relay: it
consumes an additive tap into its own ring buffer, and its failure can never take
the relay down.

The surface mirrors [`infinitered/reactotron`][rt]'s `lib/reactotron-mcp` at the
commit pinned in `scripts/reactotron-upstream.lock`;
`./scripts/check-reactotron-upstream.sh` diffs against it, and a golden-contract
test makes any change to the tool signatures show up as a reviewable diff. The
design analysis is in [`docs/reactotron-mcp-analysis.md`](docs/reactotron-mcp-analysis.md).

[rt]: https://github.com/infinitered/reactotron

---

## Platforms

|   | macOS | Windows / Linux |
| --- | --- | --- |
| App | native SwiftUI, links `ADBKit` directly | Tauri 2 + React over `droidectived` |
| Channel | **stable** (and beta) | **beta only** |
| Signing | Developer ID + notarized | unsigned |
| Maturity | feature-complete, 61 features | 29 of the 32 full-screen views ported; not yet at parity inside them |

**macOS never talks to the daemon.** That is a decision, not an accident: it
means no daemon or desktop work can reach the flow people use today.

### What the ports have

**The shell**, in full: a grouped sidebar that drags to reorder and auto-hides
Dock-style, feature tabs, split panes (`Ctrl+\`), the command palette,
per-feature and global hotkeys, UI zoom, the role picker, the catalog, toasts and
the notification panel, a system tray with background mode, the **Quick Actions**
panel, multiple windows, window translucency with the film grain, drag and drop,
and a **native** menu bar declared in Rust that owns its own accelerators so the
page's key handler can never answer them twice. Settings carries General,
Appearance, Privacy, Doctor, Tools and Hotkeys.

**The screens**: every full-screen view the Mac has except three (below),
including the ones that looked hardest — the **mirror** (scrcpy's own server
decoded by WebCodecs into a `<canvas>`, fully interactive, so it lays out like
any other element instead of being a native surface parked over one), the
**Mirror Wall**, **Screen Record** (the same stream piped into ffmpeg on the
daemon instead of into a decoder), **Reactotron**, the **JS Console**, **API
Testing**, **APK Studio** and its three tools, and the **Terminal** (real PTY
shells over the daemon's two-way `pty` topic, drawn by xterm.js). Action features
render straight from their registry field definitions, so most of the registry
works with no per-feature code.

### What they don't

Three screens: the **Video Editor**, **Frida**, and the **screenshot annotation
editor** (the capture itself works). Three pieces of chrome: the **Command Log**
sheet, the **welcome tour**, and an **auto-updater** — the ports are installed
and updated by hand. The **MCP server** is Apple-only, because `ReactotronMCP` is
a separate package that keeps swift-nio and the MCP SDK out of ADBKit's graph.
And screens that are present are not all at parity *inside* — screen record has
no audio and no live preview, and says so on the screen rather than quietly
missing them.

**Windows has no Terminal yet** — ConPTY is a different API from a pty, not a
variation of one, and the pane says so rather than failing.

Only two features are out of scope, and only because they drive an Apple
toolchain rather than a device: `ios-logs` and `push-notification` are `xcrun
simctl` against an iOS Simulator. [`docs/desktop-parity.md`](docs/desktop-parity.md)
is the feature-by-feature tracker; its per-feature half is generated from the
sources rather than written from memory.

### The Mac's UI *is* the ports' UI

Where a control exists on both, it looks and behaves the way `App/Sources/` makes
it behave — same wording, same icon, same confirmation shape, same gesture. A
nicer idea for Windows and Linux is still a difference someone has to relearn: if
it is genuinely better it goes into the Mac app *first*, and the port follows.
Two standing exceptions, named where they occur: a shortcut whose modifier has no
equivalent (the split is `Ctrl+\`, not `Ctrl+D`, which is end-of-input in every
Linux shell), and a label that names a platform.

### Verified, not assumed

The Linux app is **launched on every PR**, not merely compiled:
`desktop-linux-smoke` installs the built `.deb` into a bare `ubuntu:24.04`,
starts it under Xvfb, drives the palette to open a screen and photographs both
frames. Every check there is fatal, because the first run found the app unusable
three ways over. Windows gets a narrower version on beta tags
(`scripts/smoke-desktop-windows.ps1`); there is no Windows container.

---

## Repository layout

```
ADBKit/          SwiftPM package — ALL logic, zero UI imports. Runs on
                 macOS, Linux and Windows. 2,014 tests, no device needed.
App/             The macOS SwiftUI app. Thin shell over ADBKit.
ReactotronMCP/   Separate SwiftPM package — the MCP server over the
                 Reactotron relay (Apple-only; keeps swift-nio and the MCP
                 SDK out of ADBKit's graph, which is what lets it build on
                 Windows).
droidectived/    Separate SwiftPM package — the local daemon exposing ADBKit
                 over loopback HTTP + WebSocket for non-Swift UIs.
desktop/         The Windows/Linux app: Tauri 2 + React 19 + Vite + Tailwind
                 v4, shipping droidectived as a sidecar.
website/         The marketing site (React 19 + Vite 6 + Tailwind v4).
site/            Static passthrough for the site — CNAME, appcast.xml, SEO
                 subpages, screenshots. Vite's publicDir.
scripts/         Release, packaging, verification, smoke tests, tool updates.
docs/            Engineering docs — architecture, review standards, the port
                 strategy, the daemon protocol, the parity tracker.
```

---

## Architecture

**Two layers, strictly separated.**

```
┌─────────────────────────────────────────────────────────────────┐
│  App/  (macOS, SwiftUI)          desktop/  (Windows/Linux)      │
│  AppCore = the app               Tauri (Rust) + React webview   │
│  AppState = one window                       │                  │
└───────────────┬─────────────────────────────┼──────────────────┘
                │ links directly              │ HTTP + WebSocket
                │                             │ 127.0.0.1, bearer token
                │                    ┌────────▼────────┐
                │                    │  droidectived   │
                │                    └────────┬────────┘
        ┌───────▼──────────────────────────────▼────────┐
        │                   ADBKit                      │
        │  Exec · Devices · Features · Services ·       │
        │  Tools · Persistence · Support                │
        └───────────────────────────────────────────────┘
```

`ADBKit` imports no UI framework — feature icons are SF Symbol *name strings* —
so the whole engine is unit-tested without a device or Xcode. Actors for stateful
services, `Sendable` value types, Swift 6 complete strict concurrency.

| Group | What lives there |
| --- | --- |
| `Exec/` | `ProcessRunning` → `SystemProcessRunner` / `MockProcessRunner`, `AdbClient`, `SimctlClient`, `ToolLocator`, `CommandLog`, `HostArchive` |
| `Devices/` | `DeviceMonitor` (2s poll, `AsyncStream`), parsers, `DeviceProps`, `DeviceOverview`, the simctl twins |
| `Features/` | `FeatureRegistry` (61 declarative `FeatureDef`s), `FeatureEngine` (runner dispatch), and the pure UI models — palette search, tabs, split trees, sidebar ordering, workspace registry, feed cadence, window effects |
| `Services/` | One per domain — logcat, overrides, file/apps explorers, capture, recording, crash, bug report, wireless, emulators, performance, the mirror stack, Reactotron, the JS console, the API client, app bundles |
| `Tools/` | Managed-tool downloads (jadx, apktool, uber-apk-signer, frida, Temurin) with digest verification, plus the APK toolchain resolver |
| `Persistence/` | `JSONStore` (actor, atomic writes, corrupt files set aside) under `~/Library/Application Support/Droidective` |

**The rules that keep it that way** (the full set is in
[`CLAUDE.md`](CLAUDE.md) and [`docs/README.md`](docs/README.md)):

- **Never `Process` or `adb` in a view.** A new capability is an ADBKit service
  plus a pure, static, tested parser; the view renders and calls it.
- **Every value that reaches `adb shell` goes through `shellQuote()`.** That is
  the security boundary — not caller-side validation — and each one gets an
  argument-vector test asserting the quoted form.
- **Split adb output on `.newlines`, never `"\n"`.** `"\r\n"` is one Swift
  `Character`, so a `"\n"` split fails silently on CRLF.
- **Registry invariants are tests, not folklore.** A cross-feature rule becomes a
  loop over `FeatureRegistry.all` that fails the build when it is broken.
- **Portability is enforced.** `PortabilityGuardTests` scans ADBKit and fails on
  an Apple-only import or a corelibs trap outside a matching `#if canImport(…)`
  gate. Its allowlist is empty, and a companion test fails on a stale entry.

### The port

`ADBKit` compiles and runs its whole suite on Linux and Windows in CI. Apple-only
subsystems — the mirror media stack, the Network.framework listeners,
`NSDataDetector`, `proc_pid_rusage` — are compile-gated out rather than stubbed;
the portable seams (`HostArchive`, `FileHandleLines`, per-OS `ToolLocator`,
swift-crypto digests off-Apple) carry the rest. `droidectived` exposes ADBKit
over loopback HTTP for request/response and one WebSocket for streams, token-gated
and loopback-only; `desktop/` drives it, with the webview reaching the daemon only
through Rust commands so the bearer token never enters the page.

Full strategy: [`docs/cross-platform.md`](docs/cross-platform.md).
Protocol: [`docs/droidectived-protocol.md`](docs/droidectived-protocol.md).

---

## Building from source

### Prerequisites

```sh
brew install xcodegen        # macOS app only
# Node 22 for website/ and desktop/; Rust (rustup) for desktop/
```

The `.xcodeproj` is generated from `project.yml` and gitignored — run
`make generate` after a fresh clone if you want to open it in Xcode.

### The macOS app

```sh
make test        # ADBKit + ReactotronMCP + droidectived suites — no device, no Xcode
make test-app    # the AppTests logic bundle
make verify      # the gate: warnings-as-errors compile + all four test bundles
make build       # xcodegen generate + xcodebuild Debug
make run         # build and launch
make dmg         # Release build + packaged DMG
```

Output lands at `DerivedData/Build/Products/Debug/Droidective.app`. The app runs
**without the App Sandbox** — it has to spawn `adb`, the bundled `ffmpeg`, the
APK toolchain and the `emulator`. Local builds are ad-hoc signed and universal;
release builds are Developer ID-signed and notarized (see
[`RELEASING.md`](RELEASING.md)).

Warnings are errors, in CI and on the App target. A build with warnings does not
pass.

### The Windows/Linux app

```sh
make desktop-dev     # build the daemon sidecar, then `tauri dev`
make desktop-test    # typecheck + oxlint + vitest + cargo fmt/clippy/test
make desktop-build   # a release bundle for the host platform
```

The daemon is a **sidecar**: `scripts/build-daemon-sidecar.sh` builds it with
`swift build` and installs it as `desktop/src-tauri/binaries/droidectived-<triple>`,
the name Tauri's `externalBin` resolves. It is gitignored — build it, don't commit
it. Tauri resolves it at *build* time, so a missing daemon fails the Rust build.

### The marketing site

```sh
make site-dev      # website/ dev server
make site-build    # emits the full deployable Pages site into website/dist
```

`site/` is Vite's `publicDir`, so one build produces the React landing page plus
the static passthrough (CNAME, `appcast.xml`, SEO subpages, screenshots).

---

## Testing

Tests come with the change. The suite exists so bugs fail at compile or test
time, not in review.

| Suite | Count | Command |
| --- | --- | --- |
| ADBKit | 2,014 in 240 suites | `cd ADBKit && swift test` |
| droidectived | 406 in 35 suites | `cd droidectived && swift test` |
| ReactotronMCP | 99 in 6 suites | `cd ReactotronMCP && swift test` |
| AppTests (macOS logic bundle) | 118 in 18 suites | `make test-app` |
| desktop (vitest) | 1,223 in 89 files | `cd desktop && npm test` |
| desktop shell (cargo) | 54 | `cd desktop/src-tauri && cargo test` |

### The tiers

```
make verify-fast    tier 0-1, ADBKit only — the edit loop
make verify         tier 0-1 — warnings-as-errors compile + all four Swift bundles
make test-linux     the same ADBKit suite on Linux (the port gate)
make test-emulator  tier 3 — the device-dependent suites against a real emulator
make test-smoke     tier 4a — launch the built app and confirm it comes up
make test-mutation  tier 6 — break real code, assert the suite catches it
make verify-self    test the verification guards themselves
```

The Swift bundles are swift-testing-only, so `xcodebuild test` reports them
through XCTest as "Executed 0 tests … TEST SUCCEEDED" — a suite that discovers
nothing would otherwise look green. Every tier therefore asserts a non-zero count
from swift-testing's own summary, and `verify-self` tests those assertions.

### How things are tested

- **Behaviour, not implementation** — assert observable output and the exact adb
  argument vector through `MockProcessRunner`; never private state.
- **Edges and errors** — empty input, CRLF, malformed and partial output,
  non-zero exit, the failure branch. Mock only the boundary.
- **Real device output is a fixture, not a guess.** `RecordingProcessRunner`
  captures genuine adb output once (`scripts/emulator-harness.sh --record`),
  redacting IPs, MACs, serials and the host home directory at record time;
  `FixtureProcessRunner` replays it with no device, so parsers face real
  `getprop`, `ls -la` and threadtime `logcat` in CI.
- **Canaries guard the highest-risk seams** — a 16-concurrent-process starvation
  test, the feature-dispatch consistency tests, the registry invariants, the
  portability guard.
- Device-dependent checks are gated on `MIRROR_LIVE_TEST=1` so they skip cleanly
  in CI.

### CI

Every PR runs: the three Swift suites plus the release-channel tests on macOS;
the ADBKit and daemon suites on Linux in a `swift:6.2-noble` container, plus a
release daemon build; the ADBKit suite and a release daemon build on Windows; the
macOS app build and AppTests; `desktop-web` (typecheck, oxlint, vitest, a
production frontend build); `desktop-native` (the Swift sidecar, then
`cargo fmt`/`clippy`/`test`); and `desktop-linux-smoke`, which installs the built
`.deb` and actually launches the app. Every Swift suite runs with
`-Xswiftc -warnings-as-errors`.

---

## Releases and channels

Two channels from one `main`, decided by the tag.

|   | **stable** | **beta** |
| --- | --- | --- |
| Tag | `vX.Y.Z` | `vX.Y.Z-beta.N` |
| macOS | ✅ signed, notarized DMG | ✅ same DMG |
| Windows | ❌ | ✅ NSIS + MSI + `droidectived` |
| Linux | ❌ | ✅ `.deb` + `.AppImage` + `droidectived` |
| Update feed | `appcast.xml`, untagged item | beta item + `updates/beta/latest.json` |
| Who gets it | every install | opt-in, and Windows/Linux users |

A hyphen in the tag means pre-release. This is a standing arrangement, not a
pre-release cycle: **the stable channel is macOS-only** until a non-Apple
platform is good enough to graduate.

**Two version lines.** The tag carries the Mac's version; the root `PORT_VERSION`
file carries the ports'. One beta tag is `3.11.0-beta.1` on macOS and
`0.0.5-beta.1` on Windows and Linux. `scripts/release-channel.sh` is the single
resolver — channel, version and the exact artifact set — and
`scripts/test-release-channel.sh` runs on every PR, notably to prove a stable
release can never attach a Windows or Linux artifact.

Full policy: [`docs/release-channels.md`](docs/release-channels.md).
Cutting one: [`RELEASING.md`](RELEASING.md).

---

## Documentation

| Doc | What it covers |
| --- | --- |
| [`CLAUDE.md`](CLAUDE.md) | The architecture rules, key types, and every convention learned the hard way |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | The short on-ramp |
| [`docs/README.md`](docs/README.md) | Index of the engineering docs |
| [`docs/PULL_REQUESTS.md`](docs/PULL_REQUESTS.md) | Scoping, branching, commits, PR descriptions |
| [`docs/CODE_REVIEW.md`](docs/CODE_REVIEW.md) | The review process and its topic standards |
| [`docs/cross-platform.md`](docs/cross-platform.md) | The Windows/Linux port strategy and its phases |
| [`docs/droidectived-protocol.md`](docs/droidectived-protocol.md) | The daemon's transport, routes, error and stream contracts |
| [`docs/desktop-parity.md`](docs/desktop-parity.md) | Feature-by-feature parity tracker for the ports |
| [`docs/multi-window.md`](docs/multi-window.md) | The workspace/window model |
| [`docs/reactotron-mcp-analysis.md`](docs/reactotron-mcp-analysis.md) | The MCP surface, upstream ground truth, and the sync recipe |
| [`docs/release-channels.md`](docs/release-channels.md) | The channel policy and artifact matrix |
| [`docs/manual-verification.md`](docs/manual-verification.md) | What a human still has to check before tagging |
| [`RELEASE_NOTES.md`](RELEASE_NOTES.md) | Per-version notes (the release pipeline extracts by tag) |

---

## Contributing

Issues and PRs are welcome — start with [`CONTRIBUTING.md`](CONTRIBUTING.md).

The bar for a change: it ships with tests, it leaves the build warning-free, and
it keeps the ADBKit/App boundary intact. Work on a feature branch and open a PR
to `main`. Adding a feature has a checklist in [`CLAUDE.md`](CLAUDE.md) — a
feature's string `id` is a contract spread across several files, and most
omissions fail *silently* (a "Coming Soon" screen) rather than loudly.

---

## License

[MIT](LICENSE) © 2026 Rohindh R.

adb, scrcpy, ffmpeg, bundletool, jadx, apktool, uber-apk-signer, frida and the
Android emulator are separate tools with their own licenses. The app bundles the
scrcpy server payload, a static ffmpeg (GPLv3), and the Apache-2.0 bundletool and
uber-apk-signer jars; adb and the emulator come from your Android SDK, and the
rest download on demand. See
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
