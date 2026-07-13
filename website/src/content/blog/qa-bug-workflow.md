# Reproduce, Capture, Report: A QA Tester's Bug Workflow in One macOS App

*Fake the device state, record the repro, mark up the screenshot, and attach a full bug report — without typing a single adb command.*

![Droidective demo — palette, device bar, and features in action](/blog-media/demo.mp4)
*The whole QA loop — simulate, capture, report — lives behind one searchable palette.*

A good bug report needs four things: the steps, the evidence, the logs, and the device context. Collecting them usually means a screenshot app, a screen recorder, a developer who can "just pull the logs real quick", and a template you fill in by hand. By the fifth bug of the day, the collecting takes longer than the finding.

**Droidective** is a free, open-source macOS app that puts the entire Android testing toolkit behind a searchable command palette (⌘T). Here's the QA workflow it enables — no terminal, no adb knowledge required.

## Step 1: Put the device in the state you need

The **Simulate** hub fakes device state and — critically — tracks every override so you can reset it:

* **Fake Battery** — set 15% and unplugged, verify the low-battery UI.
* **Dark Mode** — flip the system theme in one click.
* **Change Locale** — switch the device language for i18n passes; watch for truncated German and unmirrored RTL layouts.
* **Font & Density** — override font scale and display density, the accessibility test everyone skips because the Settings path is buried.
* **Animation Scale** — turn animations off for stable screenshots (or back on to spot missing transitions).
* **Network Toggles & HTTP Proxy** — airplane mode, Wi-Fi, mobile data, or route the device through Charles to test slow/failing networks.
* **Demo Mode** — a clean status bar (full battery, no notifications) for screenshots that go in front of stakeholders.

Every override is reset-tracked, so the test device doesn't spend the afternoon stuck at a fake 15% battery.

## Step 2: Capture the evidence

**Screenshot** doesn't just capture — it opens an annotation editor: pen, highlighter, shapes, arrows, text labels, and **redaction** (solid or blur — blur actually blurs the pixels, so customer data in a screenshot stays gone). Crop, undo/redo, save or copy straight to the clipboard for Slack.

**Screen Record** records with no time limit, with audio, through the bundled scrcpy — and a mid-capture cable disconnect doesn't eat your recording. The built-in **Video Editor** trims the recording down to just the repro, crops it, and compresses it small enough for Jira's attachment limit. ffmpeg ships inside the app; nothing to install.

**Mirror Screen** puts the live device on your Mac — control it with your mouse and keyboard, and use **Send Text** to type long test strings and URLs instead of thumbing them in.

## Step 3: Get the logs without a developer

![Live logcat with level, app, tag and text filters](/blog-media/screenshot-logcat.png)
*Logcat filtered to the app under test — no grep required.*

* **Logcat** streams live, filtered by app, level, or text — and follows the app across restarts, which is exactly when the interesting bugs happen.
* **Crash Catcher** shows crashes only, with a copy-last-crash button that formats the stack trace ready to paste into the ticket. This is the feature that turns "it crashed, idk" into an actionable report.
* **Bug Report** zips a screenshot, the logs, device info, and the app version into one file. Attach it, done.

## Step 4: The extras that find bugs for you

* **Monkey Test** fires thousands of random taps, swipes, and system events at the app to shake out crashes (it confirms before unleashing chaos).
* **Performance Monitor** charts live FPS and jank while you scroll — "the list feels janky" becomes a recorded session with numbers, exportable to CSV:

![The performance monitor charting live](/blog-media/screenshot-performance.png)
*"Feels slow" → a chart the developer can't argue with.*

* **Install App** installs a dragged-in APK — on one device or *every connected device at once*, which is the fastest way to roll a release candidate onto the test rack.
* **Apps** explorer: force-stop, clear data (the classic "fresh install" state), and check versions and permissions per app:

![The apps explorer with per-app controls](/blog-media/screenshot-apps.png)
*Clear data, force-stop, verify the version — the pre-test ritual, GUI'd.*

* **Device Info** answers "which device was this on?" with RAM, storage, battery health, OS and build details in one searchable screen.

And the **Quick Actions panel** floats all of it over whatever you're doing on a global hotkey — fake the battery or clear app data without switching windows:

![The Quick Actions panel summoned over another app](/blog-media/tour-quick-actions.mp4)
*Per-action device targeting, or ⌘⏎ to run on every connected device.*

## Try it

Droidective is free, MIT-licensed, and open source — signed and notarized, macOS 14+. It needs only `adb`, and offers a one-click install if it's missing.

* Download: **[droidective.com](https://droidective.com)** — click "Download for macOS" (signed & notarized DMG)
* This guide on the web: [droidective.com/for-qa-and-testers.html](https://droidective.com/for-qa-and-testers.html)
* Source: [github.com/Droidective/Droidective](https://github.com/Droidective/Droidective)

Your next bug report: reproduced in a faked state, recorded, trimmed, annotated, and attached with logs — in minutes.

