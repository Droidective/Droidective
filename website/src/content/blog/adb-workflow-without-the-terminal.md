# The Android Developer's adb Workflow, Without the Terminal

*How I replaced six terminal tabs of adb commands with one macOS app — live logcat, performance graphs, a device file explorer, and app control behind a single ⌘T.*

![Live logcat with level, app, tag and text filters](/blog-media/screenshot-logcat.webp)
*The daily loop starts here: logcat with filters you don't have to google.*

Here's my old debugging setup: one terminal tab tailing `adb logcat` through a grep pipe, one for `adb shell dumpsys` whenever something felt slow, one for pushing and pulling files, one for `pm` commands, and a browser tab open to the adb docs because nobody remembers the `cmd uimode` syntax.

It worked. It also meant that every context switch — new device, new package name, new filter — was thirty seconds of retyping. **Droidective** is my answer: a free, open-source macOS app that wraps the entire adb workflow into a native UI with a Raycast-style command palette. This post walks the tools an Android developer touches daily.

## Logcat that keeps up with you

The live logcat streams color-coded lines with instant search and filters by **level, app, tag, or free text**. Two details matter more than they sound:

* **Follow an app across restarts.** When your process dies and comes back, the filter re-attaches to the new PID. A crash-reboot loop no longer loses you the trail.
* **Export the buffer** to a file when you need to attach it to a ticket.

Alongside it, the **Crash Catcher** filters the stream down to crashes only and has a copy-last-crash button that formats the stack trace ready for Slack or Jira. No more scroll-hunting for the `FATAL EXCEPTION` line.

## Watch performance while your build runs

![The performance monitor charting per-core CPU, RAM and network live](/blog-media/screenshot-performance.webp)
*Per-core CPU, RAM, FPS & jank — live, recordable, exportable.*

The **Performance Monitor** charts per-core CPU, system RAM, app FPS and jank, and per-process CPU/memory as they happen, with a hover crosshair and axes that track the live range. Hit record while you reproduce the jank, then export the session to JSON or CSV and diff it against your fix.

**Memory Usage** gives you a live per-app meminfo view when you're leak-hunting a single process, and **Network Speed** charts the device's real throughput.

## A real file explorer for the device

![The file explorer browsing device storage](/blog-media/screenshot-files.webp)
*Browse, copy, move, delete — and push/pull with a real progress bar.*

Browse shared storage like Finder: copy, move, delete, push, pull — with an actual progress bar computed from the on-disk size, not a spinner. On rooted devices it unlocks the whole filesystem and read-write remount.

For app data there's the **Sandbox Browser**: browse and pull files from a debuggable build's private data directory (`run-as` under the hood) — the fastest way to inspect your app's databases and shared prefs.

## App control without `pm` and `dumpsys`

![The apps explorer with a selected app's info, permissions, and controls](/blog-media/screenshot-apps.webp)
*Every installed and system app — info, permissions, force-stop, pull APK.*

The **Apps** explorer lists every installed and system app. Select yours and you get: open, force-stop, clear cache/data, disable/uninstall, grant or revoke runtime permissions, version and target SDK info, live meminfo, and pull-the-APK.

Small tools that earn their place in muscle memory:

* **Copy Current Activity** — the fully-qualified Activity on screen right now (goodbye, `dumpsys window | grep mCurrentFocus`).
* **Copy Foreground Bundle ID** — the package of whatever's on screen.
* **Send Text** — type text, URLs, or symbols on the device from your Mac keyboard.
* **Monkey Test** — fire random events at your app to hunt crashes (with a confirmation before it goes wild).

**Install App** takes a dragged-in APK and installs it — on one device, or every connected device at once. And when a build misbehaves deeper than that, **APK Studio** inspects the manifest, decompiles with jadx/apktool, and re-signs.

## Device info in one searchable screen

![Device info showing RAM, storage, battery health and CPU](/blog-media/screenshot-device.webp)
*RAM, storage, battery health, CPU, and every `getprop` — searchable.*

Build, ABI, RAM, storage, battery health, CPU, root status, and the full `getprop` dump in one place. When someone asks "what security patch level is that test device on?", the answer is a search box away.

## The palette that ties it together

![The ⌘T command palette](/blog-media/screenshot-palette.webp)
*⌘T, type, Enter. That's the whole workflow.*

Everything above — plus screen mirroring (scrcpy bundled in, no install), screenshots with an annotation editor, wireless ADB, and emulator management — sits behind **⌘T**. Fuzzy-search by what you'd naturally type: "fps", "perms", "wifi". Pin favorites. Bind global hotkeys. Every run is logged with the exact adb command it executed, so the app never hides what it's doing.

And when you genuinely want a shell, it's built in:

![The built-in terminal split into panes](/blog-media/screenshot-terminal.webp)
*Multi-tab login shells with the selected device already on `ANDROID_SERIAL`. ⌘D splits the pane.*

Your saved one-liners live in **Custom Commands** — they run through your login shell, so your aliases resolve.

## Try it

Droidective is MIT-licensed, signed and notarized, and needs only `adb` (one-click install if missing). macOS 14+, Apple Silicon and Intel.

* Download: **[droidective.com](https://droidective.com)** — click "Download for macOS" (signed & notarized DMG)
* This guide on the web: [droidective.com/for-android-developers.html](https://droidective.com/for-android-developers.html)
* Source: [github.com/Droidective/Droidective](https://github.com/Droidective/Droidective)

If your notes file of adb commands is longer than this post, I built this for you.

