# A Simulator Companion for iOS Developers: Push Tests, Fake Battery, and Clean Screenshots Without `xcrun simctl`

*Droidective started as an Android debugging app — then booted iOS Simulators showed up in the same device bar. Here's the simctl workflow it replaces.*

![Droidective with an iPhone 16 Pro simulator selected in the device bar and the Simulate hub open — Battery, Dark mode, and an APNS Push notification form](/blog-media/screenshot-ios-simulate.webp)
*A booted iOS Simulator in the device bar, and the Simulate hub adapted to it — fake battery, dark mode, and a test push.*

`xcrun simctl` is a genuinely great CLI — and almost nobody remembers its syntax. Sending a test push means hand-writing an APNS JSON payload and finding the right `simctl push` arguments. A clean status bar for App Store screenshots means the `status_bar override` subcommand with half a dozen flags. Toggling dark mode is `simctl ui booted appearance dark`, which you will look up every single time.

**Droidective** is a free, open-source macOS app that puts those behind buttons. It began life as an Android/adb toolbox, but booted iOS Simulators now sit in the same persistent device bar as Android devices — select one, and the features adapt to it, running through `simctl` instead of adb.

## Simulators in the device bar

The **Emulators & Simulators** screen lists your simulators next to your Android emulators: boot, shut down, and select. Once a simulator is booted it appears in the device bar like any device, and every command you run targets it.

## The Simulate hub

![The Simulate hub on iOS — Battery level slider, Dark mode toggle, and the Push notification APNS form](/blog-media/screenshot-ios-simulate.webp)
*The hub detects the simulator and shows the iOS-relevant controls.*

One screen for faking device state, adapted to the platform you've selected:

* **Push Notification** — deliver a test APNS push to any app on the simulator. Write the payload (or start from a sensible default), pick the bundle ID, send. No JSON file on disk, no `simctl push` flags.
* **Fake Battery** — set the battery level and state shown in the status bar, for low-battery UI testing and screenshots.
* **Dark Mode** — toggle the system appearance in one click.
* **Demo Mode** — override the status bar to the classic clean look (full signal, full battery, 9:41) for App Store screenshots, and restore it after.

**Deep Links** are here too: launch a URL into the simulator via `simctl openurl`, and save the links you test repeatedly per app.

## Capture and polish

* **Screenshot** captures the simulator straight to your Mac — and opens in a full annotation editor: pen, shapes, arrows, text, blur/solid redaction, crop, undo/redo. Marketing shots and bug reports come out of the same tool.
* **Video Editor** trims, crops, rotates, converts, and compresses recordings — ffmpeg is bundled inside the app, so nothing to install.

## The keystroke workflow

![The ⌘T command palette](/blog-media/screenshot-palette.webp)
*⌘T fuzzy-searches every tool; the device bar decides where it runs.*

Everything is behind the **⌘T** palette, and every feature can get a global hotkey — so "toggle dark mode on the simulator" becomes a keystroke you press from inside Xcode. The **Quick Actions panel** goes further: a global-hotkey panel that floats over whatever app you're in, without stealing focus:

![The Quick Actions panel over another app](/blog-media/tour-quick-actions.mp4)
*Send a push, fake the battery, or toggle appearance without leaving Xcode.*

For everything the buttons don't cover, the built-in **Terminal** gives you multi-tab login shells with split panes — your `xcrun simctl` muscle memory still works, one tab away:

![The built-in terminal with split panes](/blog-media/screenshot-terminal.webp)
*A real shell when you want one — with your saved one-liners in Custom Commands.*

## And if you also ship Android…

This is the part where an iOS-only tool would stop, but the other 50-odd tools are the point: the same app does logcat, screen mirroring, performance graphs, APK installs, and React Native debugging for the Android half of your life. One device bar, both platforms.

## Try it

Free and MIT-licensed, signed and notarized, macOS 14+ (Apple Silicon and Intel). Simulator features need Xcode installed — which you have.

* Download: **[droidective.com](https://droidective.com)** — click "Download for macOS" (signed & notarized DMG)
* This guide on the web: [droidective.com/for-ios-developers.html](https://droidective.com/for-ios-developers.html)
* Source: [github.com/Droidective/Droidective](https://github.com/Droidective/Droidective)

