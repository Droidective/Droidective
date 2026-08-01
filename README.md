<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/icon.png">
    <source media="(prefers-color-scheme: light)" srcset="docs/icon-light.png">
    <img src="docs/icon.png" width="120" alt="Droidective app icon">
  </picture>
</p>

# Droidective

A native macOS companion for Android and React Native debugging. One-click adb
actions in a Raycast-style command palette — no terminal required.

<p align="center">
  <a href="https://droidective.com/assets/demo.mp4">
    <img src="docs/demo.gif" width="760" alt="Droidective demo">
  </a>
  <br>
  <em>▶ <a href="https://droidective.com/assets/demo.mp4">Full-resolution video</a> · <a href="https://droidective.com/">droidective.com</a></em>
</p>

Built in Swift 6 + SwiftUI, with all logic in a platform-agnostic Swift package
(`ADBKit`) so the engine stays testable and a future cross-platform port only
needs a new UI layer.

> Requires macOS 14+ and the Android `adb` tool. Release builds are signed with a
> Developer ID and notarized; see [Building](#building) and
> [Install a release build](#install-a-release-build).

## Features

A searchable palette (`⌘T`) of 60 tools, organised by category and
gathered into focused hubs (React Native, Simulate, Connection, APK Studio) so
the sidebar stays short. Every action is on by default; hide the ones you don't want from
the in-app catalog.

- **Input & clipboard** — send text (Unicode via ADBKeyboard, auto-offered),
  copy the device's Wi-Fi IP.
- **Connection** — reverse ports, wireless ADB (tcpip + Android 11 pairing —
  guided from the device dropdown), disconnect, run-on-all fan-out, **emulator manager** (list / launch
  / cold-boot / wipe / stop your Android Studio AVDs), and a live **network
  speed** monitor (download/upload over time, per-interface, recorded + exported).
- **React Native** — dev menu, reload JS, saved deep links per app, simulate
  process death, set dev-server host.
- **Screen & capture** — scrcpy mirroring with common options (max size,
  bit-rate, FPS, record-to-file, view-only, turn screen off…), a screenshot
  editor (pen, shapes, text, blur/solid redaction, zoom, crop, undo/redo) that
  saves or copies on demand, screen recording with resolution / bit-rate /
  time-limit / rotate options and optional GIF, demo mode.
- **Device state** — searchable device info (RAM, storage, battery health &
  cycle count, CPU, app counts, every getprop), **file explorer** (browse,
  copy/cut/paste, delete, new folder, push from Mac, pull), fake battery, dark
  mode, font & density, animation scale, locale, network toggles, HTTP proxy —
  all tracked as resettable overrides.
- **App management** — **Apps explorer** (every user + system app, searchable by
  name/version/bundle, with live permission control), manage app
  (open/stop/clear/uninstall), permissions, app info + APK pull, current
  activity, foreground bundle id, live memory, run-as sandbox browser, monkey.
- **APK & security** — **APK Studio** (inspect a local APK's manifest /
  permissions / SDK / signing certs, decompile with jadx or apktool, recompile,
  and sign — including creating a keystore), an **AAB to APK converter**
  (bundletool universal APK with optional release-keystore signing —
  double-clicked `.aab`/`.apk` files open in the app with per-device install
  rows), and **Frida** setup (arch-matched frida-server / frida-gadget).
  bundletool and uber-apk-signer ship inside the app; jadx, apktool, and a
  Java runtime download on demand — all managed in Settings.
- **Logs & diagnostics** — live logcat (level/app/tag/text filters, a ⌘F find
  bar that highlights and steps through matches without hiding lines,
  follow-to-bottom, export), **iOS Logs** (the same pane streaming a booted
  iOS Simulator's unified log), a crash browser (Java / native / React
  Native / ANR crashes as a filterable list, with watch mode and Slack/Jira
  formatting),
  one-click bug-report zip, and a **performance monitor** (per-core CPU, RAM,
  FPS, network, and per-process usage charted live, recorded, and exported to
  JSON/CSV).
- **Tool UX** — a multi-tab **Terminal** (real PTY login shells with the
  selected device exported as `ANDROID_SERIAL`), custom command macros with
  `{bundleId}`/`{serial}` placeholders (typed as full command lines — even
  multi-line — with `adb` lines run safely as argument vectors and the rest
  through `zsh`; output silently, in the in-app Terminal, or in your Mac's
  default terminal), feature catalog with pinned items,
  per-feature + global hotkeys, menu-bar quick actions.

Every feature has an inline how-it-works description (toggleable from
Settings ▸ Appearance), and Settings keeps a **Command Log** of the exact adb
commands your actions ran, with output. A **Home** screen and first-launch tour
explain the basics; the sidebar adds drag-to-reorder, `⌘1`–`⌘0` quick-select,
and `⌘=`/`⌘-` font zoom. Files pulled from the device always ask where to save (default
`~/Downloads/Droidective`).

## Requirements

- macOS 14 (Sonoma) or later
- [Android platform-tools](https://developer.android.com/tools/releases/platform-tools)
  (`adb`) — found automatically via `ANDROID_HOME`, `~/Library/Android/sdk`, or
  the standard install prefixes; if it's missing the app links to the download.
- Optional: the Android SDK `emulator` (AVD management). The `scrcpy` server
  payload and a static `ffmpeg` ship **inside the app** — no separate install needed.

## Building

```sh
brew install xcodegen     # one-time
make test                 # ADBKit unit tests — no device needed
make build                # generate the Xcode project + build
make run                  # build and launch
```

`make` targets wrap XcodeGen + xcodebuild. The `.xcodeproj` is generated from
`project.yml` and is gitignored — run `make generate` (or `xcodegen generate`)
after a fresh clone if you want to open it in Xcode.

The app runs **without the App Sandbox** (it must spawn `adb`, the bundled
`ffmpeg`, and the `emulator`). Local builds are ad-hoc signed; release
builds are signed with a Developer ID and notarized (see [`RELEASING.md`](RELEASING.md)).

## Install a release build

Each [GitHub release](../../releases) ships a `Droidective-<version>.dmg`.
Open it and drag **Droidective** into **Applications**.

The app is signed with a Developer ID and notarized by Apple, so it opens
normally — no Gatekeeper warning, no `xattr` workaround. It keeps itself current
through Sparkle.

## Architecture

```
ADBKit/   Swift package — all logic, zero UI dependencies (swift test)
  Exec/         adb process execution, tool location, scoped command log
  Devices/      discovery (2s polling), getprop, hardware/usage overview
  Features/     declarative 60-feature registry + runners + how-to notes
  Services/     logcat streaming, overrides, file/apps explorers, capture,
                screen record, crash, bug report, wireless, emulators,
                performance + network monitors, APK inspect/sign/decompile,
                Frida, scrcpy/screenrecord options…
  Tools/        managed-tool downloads (jadx, apktool, uber-apk-signer, Java,
                frida) from GitHub releases + the APK toolchain resolver
  Persistence/  JSON stores in ~/Library/Application Support/Droidective
App/      SwiftUI macOS app — command palette, device bar, feature views,
          Home + tour, multi-tab terminal, settings, menu-bar extra,
          ⌘K search window
```

The split is strict: `ADBKit` imports no UI frameworks (feature icons are SF
Symbol *name strings*), so the whole engine is unit-tested without a device or
Xcode. See [`CLAUDE.md`](CLAUDE.md) for the full design notes and conventions.

## Contributing

Issues and PRs welcome — see [`CONTRIBUTING.md`](CONTRIBUTING.md).

## License

[MIT](LICENSE) © 2026 Rohindh R.

scrcpy, ffmpeg, adb, and the Android emulator are separate tools with their own
licenses. The app bundles the scrcpy server payload and a static ffmpeg (GPLv3);
adb and the emulator are used from your Android SDK. See
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
