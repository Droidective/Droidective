# See the Device, Pull the Diagnostics, Close the Ticket: Android Support Without adb Knowledge

*Droidective gives support and triage teams a point-and-click window into any Android device — screen mirroring, health checks, and one-file diagnostics.*

![Device info showing RAM, storage, battery health and CPU](/blog-media/screenshot-device.png)
*Every triage call starts with "what device is this?" — here's the whole answer, searchable.*

Support tickets for Android apps have a familiar arc: the customer describes something vague, an engineer gets pulled in to "just grab the logs," and twenty minutes of Slack later someone finally types the right adb command. The bottleneck isn't skill — it's that the diagnostic tools live in a terminal that most support folks reasonably don't use.

**Droidective** is a free, open-source macOS app that turns that terminal workflow into buttons. Plug in the device (or connect to it over Wi-Fi), and everything below is point-and-click. No adb commands to learn — though the app logs the exact command behind every action, so your engineers can see precisely what was run.

## Identify the device

**Device Info** shows RAM, storage, battery health, CPU, OS version, build details, and every device property in one searchable screen. When engineering asks "what security patch is that on?", you answer in seconds instead of escalating.

Quick checks live alongside it:

* **Root Status** — is this device rooted, and how? (The first question for "app refuses to run" tickets.)
* **System Restrictions** — developer toggles that can break app behavior.
* **Copy Device IP** — the device's Wi-Fi IP, copied.

## Get it connected

![The connection hub — live Wi-Fi network and IP, wireless ADB, pairing](/blog-media/screenshot-connection.png)
*The device's live Wi-Fi network and IP, one-click reverse port, and wireless debugging.*

The **Connection** hub shows the device's live Wi-Fi network and IP and sets up **Wireless ADB** — including Android 11+ pairing — so a device across the desk doesn't need to stay tethered. **Wi-Fi** shows connection details and toggles, and **Network Speed** charts live throughput when the complaint is "it's slow" and you suspect the network, not the app.

## See what the customer sees

**Mirror Screen** puts the device's live screen in a window on your Mac — and you can control it with your mouse and keyboard. scrcpy is bundled inside the app, so there's nothing to install. Walk through the customer's steps yourself, watch the issue happen, and **Screenshot** it with built-in annotation (arrows, text, blur for personal data) for the ticket.

## Check the app

![The apps explorer with a selected app's info and controls](/blog-media/screenshot-apps.png)
*Version, permissions, force-stop, clear cache — the classic support moves.*

The **Apps** explorer lists everything installed. Select the app in question and you can verify the version (half of all tickets end here), check its permissions (the other half), force-stop it, or clear its cache — without knowing that the incantation is `pm clear`.

## Collect diagnostics engineering will thank you for

![Live logcat with filters](/blog-media/screenshot-logcat.png)
*Logs, filtered to the app — collected by support, not by an interrupted engineer.*

* **Logcat** streams the device log live, filtered by app or severity — and exports the buffer to a file.
* **Bug Report** is the one-button escalation: it zips a screenshot, logs, device info, and the app version into a single file. Attach it to the ticket and engineering has everything they'd have collected themselves.
* **Emulators** — boot an emulator to reproduce the issue on a clean device before deciding it's device-specific.

## The keystroke on top

![The ⌘T command palette](/blog-media/screenshot-palette.png)
*Don't memorize where tools live — ⌘T and type "battery", "logs", or "wifi".*

Everything is behind a searchable **⌘T** palette, and Droidective's first-launch role picker has a **Support / Triage** preset that curates the sidebar to exactly this workflow — diagnostics first, developer arcana hidden (but a search away).

## Try it

Free, MIT-licensed, open source. Signed and notarized by Apple, macOS 14+. The only requirement is `adb`, and the app offers a one-click install if it's missing.

* Download: **[droidective.com](https://droidective.com)** — click "Download for macOS" (signed & notarized DMG)
* This guide on the web: [droidective.com/for-support-teams.html](https://droidective.com/for-support-teams.html)
* Source: [github.com/Droidective/Droidective](https://github.com/Droidective/Droidective)

The next "can someone grab the logs?" doesn't need an engineer.

