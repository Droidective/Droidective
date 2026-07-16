# I Got Tired of Memorizing adb Flags, So I Built a Command Palette for My Android Device

*Droidective is a free, open-source macOS app that puts all 56 Android debugging tools behind one searchable keystroke — logcat, screen mirroring, performance graphs, a built-in Reactotron, APK tooling, and more.*

![Droidective demo — the command palette, device bar, and feature screens in action](/blog-media/demo.mp4)
*Droidective in 27 seconds: search a tool, run it, move on.*

Every Android developer has the same folder of shame: a notes file full of adb incantations. `adb shell dumpsys battery set level 15`. `adb reverse tcp:8081 tcp:8081`. That one `logcat` filter you always have to look up. The commands work — but stitching your debugging loop out of six terminal tabs and a search engine is friction you pay every single day.

I built **Droidective** to delete that friction. It's a native macOS app (Swift + SwiftUI, MIT-licensed, no account, no paywall) that wraps everything you do with adb into a Raycast-style command palette. Hit **⌘T**, type what you want — "logcat", "battery", "mirror", "wifi" — and run it. The full command that executed is always logged, so you're never wondering what happened under the hood.

This post is the grand tour. If you want the version tailored to your job, I've also written role-specific deep dives — for [Android developers](/blog/adb-workflow-without-the-terminal/), [React Native developers](/blog/react-native-debugging-on-mac/), [iOS developers](/blog/ios-simulator-companion/), [QA testers](/blog/qa-bug-workflow/), [support teams](/blog/android-support-diagnostics/), and [security testers](/blog/android-pentest-toolkit/).

## One keystroke to everything

![The ⌘T command palette filtering all features for a query](/blog-media/screenshot-palette.webp)
*⌘T from any screen fuzzy-searches all 56 tools.*

The palette is the spine of the app. Every tool — from a one-shot action like *Copy Device IP* to a full screen like the *File Explorer* — is searchable by name and by the words you'd actually think of ("fps" finds the Performance Monitor, "force stop" finds Apps). Pin your favorites, bind a global hotkey to any feature, and stop looking up flags.

A persistent **device bar** follows you everywhere. Plug in two phones and an emulator, and every command targets the device you've selected — or fans out to all of them at once for things like installing an APK.

![The Home screen with a multi-tab strip across the top](/blog-media/screenshot-tabs.webp)
*Your most-used tools live in tabs, each one keystroke away.*

## A workspace, not a single window

![Opening features in tabs and splitting the window into two panes](/blog-media/tour-tabs.mp4)
*Tabs keep running in the background; drag one across the divider to split the window.*

Features open in tabs (⌃1–9 to jump between them) and keep running while hidden. Split the window in two and you can tail logcat next to a live screen mirror, or watch the performance graphs next to the app they're profiling.

And when you don't want to leave whatever you're working in, there's the **Quick Actions panel** — a global-hotkey, non-activating panel (it never steals focus) that runs any adb action, manages apps, boots emulators, or installs an APK from right on top of your editor or browser:

![The Quick Actions panel summoned over another app](/blog-media/tour-quick-actions.mp4)
*Debug without switching windows — with per-action device targeting, or ⌘⏎ to run on every device.*

## Logs and diagnostics that don't fight you

![Live logcat streaming color-coded lines with level, app, tag and text filters](/blog-media/screenshot-logcat.webp)
*Logcat with the filters you actually reach for.*

**Logcat** streams live with filters by level, app, tag, or text — and it can follow an app across restarts, so a crash-reboot loop doesn't lose you the trail. The **Crash Catcher** watches for crashes and formats the last one ready to paste into Slack or Jira. **Bug Report** zips a screenshot, logs, device info, and the app version into one attachable file.

## Performance you can see

![The performance monitor charting per-core CPU, RAM and network throughput live](/blog-media/screenshot-performance.webp)
*Per-core CPU, RAM, FPS & jank, and network throughput — charted live.*

The **Performance Monitor** graphs per-core CPU, system RAM, app FPS and jank, and per-process usage as they happen. Record a session and export it to JSON or CSV. A separate **Network Speed** tool charts live upload/download throughput straight from the device.

## Screen: mirror, record, annotate

Droidective bundles **scrcpy and ffmpeg inside the app** — no `brew install` required. Mirror and control your device in a window (or pop it out beside your workspace), record the screen with no time limit, and trim/crop/convert recordings in a built-in video editor.

Screenshots open in a full annotation editor: pen, shapes, arrows, text, blur or solid redaction, crop, undo/redo. Perfect for bug reports and store listings — there's even a **Demo Mode** that cleans the status bar for screenshots.

## Made for React Native too

![The React Native hub — reload JS, dev menu, Metro port forwarding, dev-server host](/blog-media/screenshot-react.webp)
*The RN essentials in one hub.*

There's a dedicated React Native hub — reload the JS bundle, open the dev menu, reverse the Metro port, simulate process death, save deep links per app. And two features I'm particularly proud of:

* **Reactotron, built in.** Droidective *is* the Reactotron server. Point your app's client at it and a live timeline of logs, actions, and network requests streams in — no separate Electron app to install or keep open.
* **JS Console** — a Hermes REPL over the Metro debugger, with live `console.*` output.

![The built-in Reactotron timeline split into two filtered panes](/blog-media/tour-reactotron.mp4)
*The built-in Reactotron timeline — split it and give each pane its own filter.*

## Files, apps, and the device itself

![The file explorer browsing device storage](/blog-media/screenshot-files.webp)
*Browse, push, and pull with a real progress bar.*

* **File Explorer** — browse shared storage (or the whole filesystem on rooted devices), copy, move, delete, push and pull.
* **Apps Explorer** — every installed and system app with info, runtime permissions, force-stop, clear data, pull APK, and a sandbox browser for debug builds.

![The apps explorer with a selected app's info, permissions, and controls](/blog-media/screenshot-apps.webp)
*Per-app management without a single `pm` command.*

* **Device Info** — RAM, storage, battery health, CPU, and every `getprop`, searchable.

![Device info showing RAM, storage, battery health and CPU](/blog-media/screenshot-device.webp)
*Everything `getprop` knows, without `adb shell` spelunking.*

## Simulate any state

Fake the battery level, force dark mode, switch the locale, scale fonts and display density, toggle airplane mode, or route the device through an HTTP proxy (Charles, Proxyman, Burp). Every override is tracked so you can reset it — no more devices stuck at a fake 15% battery.

## For the power users

![The built-in terminal split into panes, running adb against a device](/blog-media/screenshot-terminal.webp)
*When you do want a shell, it's built in — and already pointed at your device.*

A real **Terminal** lives inside the app: multi-tab PTY login shells with the selected device exported as `ANDROID_SERIAL`, split panes (⌘D), and a find bar. **Custom Commands** let you save your own adb one-liners, shell scripts, and presets — they run through your login shell, so your aliases work.

There's also a full **APK toolchain**: inspect a manifest, decompile with jadx or apktool, recompile, and sign — plus one-click Frida setup for instrumentation work.

![Global hotkey settings — a shortcut to summon the app and one per feature](/blog-media/screenshot-hotkeys.webp)
*Bind a global shortcut to summon the app, and one per feature.*

## Pick your role, get your tools

On first launch, Droidective asks what you do — Android developer, React Native developer, iOS developer (yes, booted iOS Simulators sit right in the device bar), QA, support, or security — and curates the sidebar around your actual workflow. Everything else stays a ⌘T away, and the full 56-tool catalog is there to toggle, reorder, and pin.

![The feature catalog listing all 56 tools with toggles](/blog-media/screenshot-catalog.webp)
*All 56 tools — turn off the ones you don't want.*

## Free, open source, and honest about your data

* **MIT-licensed and fully open source** — [github.com/Droidective/Droidective](https://github.com/Droidective/Droidective)
* **Signed and notarized** with an Apple Developer ID — opens with a normal double-click
* **No account, no paywall, no pro tier**
* Anonymous crash reports and usage analytics are disclosed on first launch and opt-out in Settings → Privacy; device serials, file paths, and command contents are never sent
* Only requirement: `adb` (with a one-click install if it's missing). scrcpy and ffmpeg ship inside the app.

## Get it

Download it from the website — **[droidective.com](https://droidective.com)** — and click "Download for macOS" for the signed, notarized DMG.

Pick the guide for your workflow on the site: [Android developers](https://droidective.com/for-android-developers.html) · [React Native](https://droidective.com/react-native-debugger.html) · [iOS developers](https://droidective.com/for-ios-developers.html) · [QA & testers](https://droidective.com/for-qa-and-testers.html) · [support teams](https://droidective.com/for-support-teams.html) · [security testers](https://droidective.com/for-security-testers.html).

macOS 14+, Apple Silicon and Intel. If it saves you a terminal tab, a star on [GitHub](https://github.com/Droidective/Droidective) goes a long way. 🕵️

