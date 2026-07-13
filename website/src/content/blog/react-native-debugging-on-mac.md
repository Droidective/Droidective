# React Native Debugging on a Mac: Reactotron With No Desktop App, a Hermes Console, and Metro in One Click

*Droidective bundles the whole RN-on-Android debugging stack into one free macOS app — including a built-in Reactotron server and a JS console over the Hermes debugger.*

![The React Native hub — reload JS, dev menu, process death, Metro port and dev-server host](/blog-media/screenshot-react.png)
*The RN essentials in one hub — no more remembering which adb incantation reloads the bundle.*

React Native debugging on Android is a tab-juggling act: Metro in one terminal, `adb reverse` in another, Reactotron as a separate Electron app, logcat somewhere behind them, and the dev menu a physical shake away. Each piece is fine; the pile is not.

**Droidective** is a free, open-source macOS app that collapses that pile into one window. It's a general Android toolbox (56 tools behind a ⌘T command palette), but React Native is a first-class citizen — I use it daily on RN apps, and this post covers the RN loop specifically.

## The React Native hub

One screen with described action cards for the things you do twenty times a day:

* **Reload JS** — the double-tap-R, as a button (or a hotkey).
* **Open Dev Menu** — no shaking the device.
* **Simulate Process Death** — background the app, kill it, and test state restoration honestly.
* **Reverse the Metro port** — `adb reverse tcp:8081` in a click, with a port field for non-default setups.
* **Set Dev Server Host** — point a physical device at any Metro instance (it writes `debug_http_host`, so it works on real hardware, not just emulators).
* **Deep Links** — launch and *save* deep links per app, so your test URLs stop living in a notes file.

## Reactotron, with no Reactotron app

![The built-in Reactotron timeline split into two panes with different filters](/blog-media/tour-reactotron.mp4)
*Droidective is the Reactotron server — a live timeline of logs, actions, and network requests.*

This is the feature that surprises people: **Droidective runs the Reactotron server itself.** Keep the standard `reactotron-react-native` client in your app, point it at your Mac, and the timeline streams straight into Droidective — logs, Redux/state events, API calls, custom commands, and a REPL. There is no separate desktop app to install, update, or keep open.

The timeline splits into panes, each with its own filter — network traffic on the left (filterable by HTTP method and status class), logs on the right. API calls copy out as cURL. When a client disconnects, the timeline says so, with the app's name — no silent dead sessions.

## A real JS console over Hermes

The **JS Console** connects to Metro's debugger endpoint and gives you a live Hermes REPL: run expressions inside your running app, inspect objects, and watch `console.*` output stream in — with Reload JS and Restart App buttons right there. It's the "just let me poke at the state" tool, without opening Chrome DevTools.

Under the hood it speaks the Chrome DevTools Protocol directly to Hermes; the device only needs the Metro port reversed, which the app handles.

## The rest of the loop

RN debugging is still Android debugging, so the whole toolbox is one ⌘T away:

![Live logcat with per-app filtering](/blog-media/screenshot-logcat.png)
*Native crash? Logcat with per-app scoping and a crash catcher that formats the stack for Slack.*

* **Logcat** filtered to your app, following it across restarts — for everything that happens below the JS layer.
* **Crash Catcher** — copy the last native crash, formatted for a ticket.
* **Performance Monitor** — live FPS and jank next to per-core CPU and RAM, recordable and exportable:

![The performance monitor charting live](/blog-media/screenshot-performance.png)
*Catch the dropped frames while you scroll the list that's janking.*

* **Network Speed** — live device throughput when you're testing on bad networks.
* **Mirror Screen** — scrcpy is bundled inside the app (no `brew install scrcpy`); mirror and control the device beside your editor, or pop the mirror into its own window.
* **HTTP Proxy** — route the device through Charles or Proxyman in one click, and reset it just as fast.
* **Install App, Apps explorer, File Explorer, Device Info** — the standard Android chores, GUI'd.

Open the RN hub, Reactotron, and logcat in **tabs**, split the window, and you have Metro's output, the event timeline, and the native logs on one screen:

![Opening features in tabs and splitting the window](/blog-media/tour-tabs.mp4)
*Tabs keep running while hidden; drag one across the divider to split.*

## Try it

Free and MIT-licensed, signed and notarized, macOS 14+. The only requirement is `adb` — scrcpy and ffmpeg ship inside the app.

* Download: **[droidective.com](https://droidective.com)** — click "Download for macOS" (signed & notarized DMG)
* This guide on the web: [droidective.com/react-native-debugger.html](https://droidective.com/react-native-debugger.html)
* Source: [github.com/Droidective/Droidective](https://github.com/Droidective/Droidective)

Close the Electron Reactotron, keep the insight. 🕵️

