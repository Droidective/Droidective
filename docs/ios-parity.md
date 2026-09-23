# iOS Parity — bringing the iOS side up to the Android side

Droidective is an adb tool with a simulator courtesy shelf. Of 61 features,
9 declare iOS Simulator support, every one of them a thin `simctl` wrapper, and
a physically connected iPhone never appears in the device bar. This document is
the end-to-end spec for closing that gap.

The measure of done is internal: **for every one of the 61 features, the iOS
answer is written down** — it works, it is scheduled, or the platform cannot do
it and the UI says so — plus the iOS-specific capabilities the Apple toolchains
expose and Android has no counterpart for. The full accounting is the table in
[What complete looks like](#what-complete-looks-like); a feature missing from
it is a bug in this document.

Everything mechanical below was verified against the installed toolchain
(Appendix A). Where a mechanism is *not* verified it is labelled a **spike**,
and a spike is a PR whose deliverable may be "this does not work" — that
outcome is recorded here, not worked around.

## Contents

- [What complete looks like](#what-complete-looks-like)
- [Decisions taken up front](#decisions-taken-up-front)
- [Architecture: the seams this opens](#architecture-the-seams-this-opens)
- [Phase 1 — the simctl sweep](#phase-1--the-simctl-sweep)
- [Phase 2 — physical iOS devices](#phase-2--physical-ios-devices)
- [Phase 3 — mirroring and the visual tools](#phase-3--mirroring-and-the-visual-tools)
- [Phase 4 — the agent surface](#phase-4--the-agent-surface)
- [Phase 5 — network](#phase-5--network)
- [Phase 6 — build analytics](#phase-6--build-analytics)
- [Test and gate strategy](#test-and-gate-strategy)
- [Risk register](#risk-register)
- [PR sequencing](#pr-sequencing)
- [Appendix A — verified command inventory](#appendix-a--verified-command-inventory)
- [Appendix B — mechanisms for what simctl cannot reach](#appendix-b--mechanisms-for-what-simctl-cannot-reach)

## What complete looks like

Every registry id, with its iOS Simulator and physical-device answer. "N/A"
means the platform has no equivalent and the feature shows its
platform-unsupported state; the note says why. Hub members are marked with
their hub, because their work lands inside the hub's screen rather than on a
standalone one.

| id | Kind | iOS Simulator | Physical iPhone | Where |
|---|---|---|---|---|
| `screenshot` | action | ✅ `io screenshot` + annotate editor | spike — `viewdevicescreen` capability exists, no CLI verb | done / P3 |
| `dark-mode` | toggle (simulate hub) | ✅ `ui appearance` | N/A — no toolchain route | done |
| `demo-mode` | toggle | ✅ 9:41 preset | N/A | done |
| `fake-battery` | form (simulate hub) | ✅ `status_bar --battery*` | N/A | done |
| `push-notification` | form (simulate hub) | ✅ `push` | N/A — APNS only | done |
| `deep-link` | view (react-native hub) | ✅ `openurl` | ✅ `process launch --payload-url` (launch-time only) | done / P2 |
| `emulators` | view | ✅ boot/shutdown; + create/clone/delete/erase/rename | — | done / P1 |
| `simulate` | hub | ✅ adapts per platform | adapts: every section N/A | done |
| `ios-logs` | view | ✅ unified log | N/A for now — `log stream` has no device flag; `process launch --console` is the app's stdout only | done |
| `reactotron` | view (device-free) | ✅ works — sim shares loopback | ✅ over Wi-Fi/USB as any RN client | done |
| `js-console` | view (device-free) | ✅ works — Metro target on localhost | ✅ same | done |
| `api-client` `terminal` `custom-commands` `video-editor` | device-free | ✅ | ✅ | done |
| `apps` | view | `listapps` `appinfo` `launch` `terminate` `uninstall` | `device info apps` (verify) · `process launch` · `uninstall app` | P1 / P2 |
| `app-management` | apps hub | launch / terminate / uninstall / relaunch | launch / terminate / uninstall | P1 / P2 |
| `app-info` | apps hub | `appinfo` | `device info apps` (verify) | P1 / P2 |
| `permissions` | apps hub | `privacy grant\|revoke\|reset` — 12 services | N/A | P1 |
| `install-app` | view | `install` (`.app`; `.ipa` → `Payload/*.app`) | `device install app` (`.ipa`) | P1 / P2 |
| `sandbox-browser` | view | `get_app_container app\|data\|groups` | `device copy from --domain-type appDataContainer\|appGroupDataContainer` | P1 / P2 |
| `device-info` | view | `list -j` metadata, `getenv` | `device info details\|hardware\|lockState` | P1 / P2 |
| `crash-catcher` | view | `~/Library/Logs/DiagnosticReports` + `diagnose` | `device copy from --domain-type systemCrashLogs` | P1 / P2 |
| `bug-report` | view | `simctl diagnose` | `device sysdiagnose` | P1 / P2 |
| `screen-record` | view | `io recordVideo` to a file — a recording, finalized on SIGINT, **no live preview** | spike — same `viewdevicescreen` question as screenshot | P1 / P3 |
| `process-death` | action (react-native hub) | `terminate` + `launch` | `process` signal + `launch` | P1 / P2 |
| `locale` | form (simulate hub) | per-launch `-AppleLanguages` / `-AppleLocale` launch args | same via `process launch` (verify) | P1 / P2 |
| `layout-overrides` | form (simulate hub) | font scale → `ui content_size`; density N/A | N/A | P1 |
| `send-text` | form | `pbcopy` is the only route (no `input text`); HID typing arrives with P3b | N/A | P1 (pasteboard) / P3b |
| `animation-scale` | toggle (simulate hub) | spike — Simulator.app's Slow Animations is an app pref, not simctl | N/A | P3c spike |
| `open-dev-menu` `reload-js` | actions (react-native hub) | need HID (⌘D / R) — arrive with P3b | N/A | P3b |
| `performance` `meminfo` | view | spike — simulator apps are Mac processes, so host-side `proc_pid_rusage` sampling is possible | N/A | P1 spike |
| `scrcpy` `mirror-wall` | view | P3 — a new capture subsystem, not a transport swap | spike | P3 |
| `file-explorer` | view | **N/A** — iOS has no arbitrary-path filesystem access; the container browser is the answer | N/A | — |
| `logcat` | view | counterpart is `ios-logs` | counterpart is `ios-logs` | done |
| `network-speed` | view | N/A — reads `/proc/net/dev` | N/A | — |
| `network-toggles` `http-proxy` | forms (simulate hub) | P5b conditioning; a sim inherits the Mac's proxy | N/A | P5 |
| `current-activity` `foreground-package` | actions | N/A — no exposed activity stack | N/A | — |
| `monkey` | form | N/A now; could ride P4's action surface later | N/A | — |
| `dev-settings` `system-restrictions` `root-status` `private-dns` `wifi` | views | N/A — Android system surfaces | N/A | — |
| `reverse-port` `wireless-adb` `get-ip` `rn-dev-host` | connection / RN hub | N/A — a sim shares the Mac's loopback and IP; nothing to tunnel or point | N/A | — |
| `frida-console` | view | N/A for now (frida-server has a simulator build; out of scope) | N/A | — |
| `apk-studio` + `apk-inspector` `apk-decompile` `apk-sign` `aab-convert` | Android artifact tools | N/A — Android package formats, device-free | N/A | — |
| `connection` `react-native` | hubs | adapt per platform (members above) | adapt | ongoing |
| **new** `location` | view | `location set\|run\|start\|clear` | N/A on this toolchain — no location capability reported | P1 |
| **new** `accessibility` | view | `ui increase_contrast`, `ui content_size` verified; the other eight overrides are a **spike** | N/A | P1 |
| **new** `status-bar` | view | full `status_bar override` editor (keeps `demo-mode` as the one-click toggle) | N/A | P1 |
| **new** `user-defaults` | view | container plists, standard + app groups | N/A | P1 |
| **new** `sim-keychain` | actions (simulate hub) | `keychain reset\|add-cert\|add-root-cert` | N/A | P1 |
| **new** `pasteboard` | actions | `pbcopy\|pbpaste\|pbsync` | N/A | P1 |

Two things run the other way, where iOS is ahead and the work is to keep it
that way: **iOS Logs** is the best log viewer in the app, and the **MCP
server** built for Reactotron is infrastructure phase 4 reuses.

The engineering consequence worth internalising: almost nothing in the "P3"
and "P5" rows comes from `simctl` or `devicectl`. Framebuffer streaming, HID
input, accessibility reads, network interception and conditioning each need a
different mechanism, and each mechanism is a project. Appendix B surveys them
and what each costs; the phases are ordered so we pay for them one at a time,
as late as possible — and so that a mechanism that turns out not to exist
costs a spike, not a phase.

## Decisions taken up front

These were open questions. They are now decided, with the reasoning recorded so
a reviewer can disagree with the reason rather than the outcome.

### 1. Three platforms, not two

`DevicePlatform` gains `.iosDevice` alongside `.android` and `.iosSimulator`.
A simulator and a physical iPhone differ in toolchain (`simctl` vs `devicectl`),
in capability, and in failure modes; collapsing them into one "iOS" case would
push a platform check into every runner.

The compile-error property holds only for exhaustive switches, and there are
nine of those. There are also **twenty** equality and default-value sites that
compile clean and misroute a third platform to Android — `AppCore.platform(for:)`
falls back to `?? .android`, three `FeatureEngine` entry points take
`platform: DevicePlatform = .android` as a default parameter, `SimulateView`
branches on a binary `isSimulator`, and the Mirror Wall and pop-out window
`filter { $0.platform == .android }`. PR 1's actual work is converting those
sites, and **removing the three default parameters** so the compiler forces
every caller to decide. The seams table lists them.

### 2. Capability comes from the device, not from an Xcode version string

`devicectl device info details` returns a `capabilities` array on every device
— 36 entries on the connected iPhone 15 Pro Max, including
`com.apple.coredevice.feature.installapp`, `.launchapplication`, `.listFiles`,
`.transferFiles`, `.rebootdevice`, `.capturesysdiagnose`, `.getlockstate`,
`.viewdevicescreen` and `com.apple.dt.customer.postdarwinnotification`. Absent
from the list: anything for orientation, opening a URL on a running app, or
location simulation.

So `DeviceCapability` (ADBKit, pure) is a function of that `Set<String>`,
keyed by `info.jsonVersion` (3 today), with the toolchain version at most a
secondary input. A feature that a device does not report says so with the
capability it needs — the same shape as the Doctor pointing at an install
source instead of installing anything. When Apple adds a capability, it lights
up with a table entry, not a release.

### 3. Mirroring is a new subsystem, and the first PR is a spike

The obvious shortcut — `simctl io recordVideo` written to a FIFO and decoded
live — **does not exist**. It was probed (Appendix A): without `--force`
simctl refuses a path that exists; with `--force` it unlinks the FIFO; `file://`
URLs and `/dev/stdout` both fail. And even to a plain file nothing is written
until the take ends — there is no file descriptor on the output path during
recording, and the finished file is `moov` before `mdat`, which can only be
produced by buffering the whole recording. `recordVideo` is a recorder, not a
stream.

The existing consumer could not have eaten it anyway. `ScrcpyStreamDecoder`
parses scrcpy's own 12-byte packet framing (config flag, keyframe flag, 61-bit
PTS, then the payload), `MirrorSession.handle` takes PTS and SPS/PPS from
those headers, and the session holds a *concrete* `MirrorTransport` built from
an `AdbClient` — there is no source protocol to swap behind.

So phase 3 opens with **PR 6, a spike with three candidate capture sources**,
and its deliverable is a decision:

- **ScreenCaptureKit on the Simulator.app window.** Public API, real frame
  rate, needs Screen Recording permission, and captures the window chrome
  unless cropped. The only public route to live frames.
- **The private CoreSimulator framebuffer client** — what the open-source
  simulator-automation stacks use. Fast and chrome-free; private, so it can
  break on any Xcode release.
- **`simctl io screenshot` polling.** Public, trivially reliable, a few frames
  a second at best. The floor, not the goal.

Whichever wins, the session work is the same: extract a `MirrorSource`
protocol from the scrcpy-coupled `MirrorSession`, give the decoder path a
non-scrcpy entry that takes raw sample buffers, and keep `MirrorRenderer` and
the display layer as they are. Input is a second spike with its own two
candidates (private Indigo HID, or synthesised `CGEvent`s into the Simulator
window), gated and degrading to read-only when neither resolves. **This is the
largest item in the plan**, and the PR table now says so.

### 4. Network conditioning: spike `dnctl`/`pfctl` before committing to a system extension

A per-app `NEFilter` content-filter system extension is a signing project
before it is a feature: it needs the NetworkExtension entitlement, a
provisioning profile, hardened runtime **on**, and notarization — against an app
that is currently ad-hoc signed with hardened runtime off and no entitlements
file. Worse for development, `systemextensionsctl developer` refuses to run
while SIP is enabled, and the dev machine has no Developer ID Application
identity in its keychain (it exists only as CI secrets).

macOS still ships `dnctl` and `pfctl` — the dummynet machinery behind Apple's
own Network Link Conditioner. Whether a pf anchor can be scoped to the
simulator's traffic (pf matches hosts and ports, not processes) is exactly what
the spike answers. If it can, conditioning costs zero signing work. If not, the
system extension is the fallback, with its own signing sub-project.

### 5. The agent surface covers both platforms, and ships as CLI *and* MCP

Two exposures, because they are good at different things. A single CLI binary
means a host like Claude Code approves it once and stops prompting — a real
ergonomic win an MCP server does not get. MCP, in return, is typed,
discoverable, and already proven here. `droidectived` already exists with a
documented protocol, and `ReactotronMCP` already proves out a declarative
10-tool MCP surface. So: one protocol core in ADBKit, exposed twice.

The perception/action model is defined for **Android as well as iOS** from
day one. `uiautomator` dumps and `input` events fit the same
snapshot-then-act shape, and building it iOS-first then retrofitting is how it
ends up permanently iOS-shaped.

### 6. Every iOS feature is Mac-only, and the tooling has to be taught that

`simctl`, `devicectl` and the simulator frameworks are macOS toolchains. Two
honest notes about what "Mac-only" means in this codebase:

- **`PortabilityGuardTests` will not catch most of it.** It scans for sixteen
  Apple-only *imports* and six named corelibs traps. A `simctl` or `devicectl`
  service is pure Foundation — it compiles on Linux and is simply
  non-functional there, which is the precedent the existing `Simctl*` files
  already set (none carries an `#if` gate). `dlopen`/`dlsym` of a private
  framework trips nothing either. Only genuinely Apple-framework code
  (ScreenCaptureKit, VideoToolbox, the dlopen'd simulator frameworks) needs a
  `#if canImport` gate, and those files get one.
- **The parity tracker cannot be regenerated into correctness.**
  `scripts/generate-parity-tracker.py` carries a hardcoded two-entry `GATED`
  dict (`ios-logs`, `push-notification`); every new iOS-only id falls through
  to "⬜ todo — not started on Windows/Linux" and is reported as port backlog.
  PR 1 replaces the dict with a derivation from the registry — an id whose
  `platforms` excludes `.android` is Mac-only by construction — and adds a test
  that no such id is ever emitted as todo.

## Architecture: the seams this opens

| Seam | Change |
|---|---|
| `DevicePlatform` | Third case `.iosDevice`. Nine exhaustive switches become compile errors. Twenty non-exhaustive sites do not, and are PR 1's work: `AppCore.swift:848` (`?? .android`), `FeatureEngine.swift:157,166,179` (three `= .android` default parameters — **removed**, not extended), `SimulateView.swift:28,46,90` (binary `isSimulator`), `MirrorWallView.swift:356` + `MirrorWindowView.swift:105` (`== .android` filters), `SimulatorLogsView.swift:111`, `AppCore.swift:787`, and the icon sites in `DeviceBarView:347`, `QuickActionsView:805,1156,1167`. |
| Exec clients | `DevicectlClient` joins `AdbClient` and `SimctlClient`. **Trap:** devicectl's only stable machine interface is `--json-output <path>` *to a file* — stdout prints a human table that looks stable and is documented as not. The client writes a temp file and reads it back; the parser is pure over `{info:{jsonVersion,outcome,…}, result:{…}}` and asserts `jsonVersion == 3`. |
| Discovery | `CoreDeviceMonitor` joins `DeviceMonitor` and `SimulatorMonitor`; `AppCore` merges three lists. **`list devices` returns paired-but-absent devices and every device type** — the dev machine shows an Apple Watch — so the monitor filters on `connectionProperties`/`deviceProperties.bootState`/`hardwareProperties.deviceType`, or a Watch lands in the device bar. |
| Capability | `DeviceCapability` (pure) over the per-device `capabilities` set (decision 2). |
| Tool requirements | `needsScrcpy` on `scrcpy`, `screen-record`, `mirror-wall` is a hard gate today; it becomes platform-scoped so an iOS path is not blocked on a tool it does not use. |
| Feature registry | `platforms` sets gain `.iosDevice`. `hasAll61Features` becomes a moving count — bump per phase. Six new ids in phase 1. `permissions` is an `apps` hub member, so its iOS work lands in the Apps explorer's detail pane; `demo-mode` stays a toggle and the editor is the new `status-bar` view, because changing a feature's `kind` moves it between invariant tests and Quick Actions renderers. |
| Daemon | `droidectived` **string-parses** platform in `ActionRoutes.swift:65–66` (`"android"`, `"iosSimulator"`, `default: nil`) and hardcodes the error text in `DaemonProtocol.swift:244` — no compile error on a third case, a silent `unknown_platform` instead. PR 1 derives the parse from `DevicePlatform.rawValue`, updates the message, updates `docs/droidectived-protocol.md`, and the 408 daemon tests run. |
| Drop routing | `FileDropRouter` has **no notion of platform**: `defaultDestination = "/sdcard/Download"` is hardcoded, `DeviceDropPlan` is `{installs, bundles, copies, destination}`, and classification via `AppPackageFormat.detect` sends a `.ipa` to "copy to /sdcard/Download". The change is a platform input, a third route kind (import-to-library, no destination path), `.ipa` in `AppPackageFormat`, and an iOS transfer service beside the adb-specific `DeviceTransferService`. Every full-pane URL zone inherits it via `featureFileDrop`. |
| Portability | Apple-framework files get `#if canImport` gates; pure-Foundation toolchain services do not need them and get none (decision 6). |
| Parity tracker | `GATED` derived from the registry, with a test (decision 6). |
| Naming | Complete iOS support makes "Droidective" a misnomer. Flagged as a product decision, not an engineering one — no rename is in scope here. |

---

## Phase 1 — the simctl sweep

**No new dependencies, no private API, no signing work.** Every command is in
Appendix A. Two rows are spikes and say so.

| # | Feature | id | Kind | Command |
|---|---|---|---|---|
| 1 | App lifecycle on sims | extend `apps` (+ hub members `app-management`, `app-info`) | view | `listapps`, `appinfo`, `launch` (+`--terminate-running-process`, `SIMCTL_CHILD_*` env, argv), `terminate`, `uninstall` |
| 2 | Per-launch locale | extend `locale` (simulate hub) | form | `launch <bundle> -AppleLanguages "(ja)" -AppleLocale ja_JP` — Apple's documented launch arguments |
| 3 | Install on sims | extend `install-app` | view | `install` (`.app`; `.ipa` unpacked to `Payload/*.app`) — `.ipa` joins `AppPackageFormat` |
| 4 | Privacy & permissions | extend `permissions` (apps hub → Apps detail pane) | hub member | `privacy <dev> grant\|revoke\|reset <service> [bundle]` — 12 services + `all` |
| 5 | Location simulation | `location` (new) | view | `location set <lat,lon>`, `run <scenario>`, `start --speed --distance\|--interval <waypoints…>`, `clear`, `list` |
| 6 | Accessibility | `accessibility` (new) | view | **Verified:** `ui increase_contrast`, `ui content_size` (12 categories + increment/decrement). **Spike:** invert colours / grayscale / reduce motion exist as keys in the sim's `com.apple.Accessibility.plist`; reduce transparency, bold text, button shapes, differentiate-without-colour and on/off labels do **not**; and no mechanism to make a booted sim re-read the plist is known — it runs its own `cfprefsd`, and simctl has no notification verb. The spike's deliverable may be "two toggles". |
| 7 | Status bar editor | `status-bar` (new; `demo-mode` stays the toggle) | view | `status_bar override` — `--time`, `--dataNetwork` (10 values), `--wifiMode`/`--wifiBars`, `--cellularMode`/`--cellularBars`, `--operatorName`, `--batteryState`/`--batteryLevel`; `list` for read-back |
| 8 | User Defaults editor | `user-defaults` (new) | view | `get_app_container <bundle> data\|groups` → `Library/Preferences/*.plist`. **Note:** a running app caches its defaults; edits take effect on relaunch, and the UI says so. |
| 9 | App container browsing | extend `sandbox-browser` | view | `get_app_container <bundle> app\|data\|groups` |
| 10 | Screen recording on sims | extend `screen-record` (gate made platform-aware) | view | `io recordVideo --codec h264\|hevc --mask --display <file>`; `Recording started` on stderr is readiness, SIGINT stops, the file appears only on finalize. **No live preview** — the Android recorder previews through the mirror session, which does not exist for sims until phase 3. |
| 11 | Keychain actions | `sim-keychain` (new, simulate hub) | actions | `keychain reset`, `add-cert`, `add-root-cert` |
| 12 | Media & contacts import | drop-routed | — | `addmedia` — a new import route kind in `FileDropRouter` |
| 13 | Pasteboard sync | `pasteboard` (new) | actions | `pbcopy`, `pbpaste`, `pbsync`; also the only route for `send-text` on a simulator, and its empty state says so |
| 14 | Simulator lifecycle | extend `emulators` | view | `create`, `clone`, `delete`, `rename`, `erase` (confirmed), `upgrade`, `runtime` |
| 15 | Crash reports & bug report | extend `crash-catcher`, `bug-report` | view | host `~/Library/Logs/DiagnosticReports` + `simctl diagnose` |
| 16 | Device info on sims | extend `device-info` | view | `getenv`, `appinfo`, runtime/device-type metadata from `list -j` |
| 17 | Process death | extend `process-death` (react-native hub) | action | `terminate` then `launch` |
| 18 | Performance on sims | extend `performance`, `meminfo` | **spike** | simulator apps are Mac processes under `launchd_sim`; host-side `proc_pid_rusage`/`ps` sampling may cover CPU and memory. Deliverable may be "not worth it". |

**Services added:** `SimulatorAppService`, `SimulatorPrivacyService`,
`SimulatorLocationService`, `SimulatorAccessibilityService`,
`StatusBarOverrideBuilder` (pure), `UserDefaultsContainerService`,
`SimulatorLifecycleService`, `SimulatorKeychainService`, `SimulatorMediaService`,
`SimulatorPasteboardService`, `SimulatorDiagnosticsService`.

**Notes worth writing down now:**

- `simctl privacy`'s real service list is **12 + `all`**: calendar,
  contacts-limited, contacts, location, location-always, photos-add, photos,
  media-library, microphone, motion, reminders, siri. Camera, notifications and
  health are *not* simctl privacy services — do not spec them.
- `simctl ui` has exactly three options: `appearance`, `increase_contrast`,
  `content_size`. Nothing else, whatever a UI elsewhere implies.
- `simctl` takes no `-s`; the UDID is positional. `SimctlClient` already
  handles this and callers pass full argument vectors.
- Every path/URL/free-text value going through `simctl spawn … sh -c` needs
  `shellQuote()`, same security boundary as adb. Argument-vector `simctl`
  calls (the common case) need no quoting — assert the exact vector in tests.

**Deliverable:** iOS goes from 9 → ~24 declared ids, plus hub members.
Registry count bumped. **The existing simctl invariant covers only the action
kinds** — 11 of these rows are `.view` features and get no guard from it — so
this phase adds `everyIOSCapableViewHasASimulatorPath` (AppTests, beside
`FeatureDetailRouteTests`): a view id annotated `.iosSimulator` must render
something other than `PlatformUnsupportedView`. Parity script derivation lands
in PR 1 so these ids never appear as port backlog.

---

## Phase 2 — physical iOS devices

A third platform. Two iPhones are connected to the dev machine and `devicectl`
518.31 is present, so this is verifiable end to end today.

**Works on this toolchain, per the device's own `capabilities`:**

| Capability | Command | Feature |
|---|---|---|
| Discovery, pairing, boot state | `list devices --json-output` (filtered — see seams) | device bar |
| Device info | `device info details \| hardware \| lockState` | `device-info` |
| Installed apps | `device info apps` (**verify** in PR 5) | `apps`, `app-info` |
| Install / uninstall | `device install app`, `device uninstall app` (`.ipa`) | `install-app`, `app-management` |
| Launch / terminate | `device process launch` (+`--console` for the app's stdout), `process list`, signal | `app-management`, `process-death` |
| **Deep links** | `process launch --payload-url <url>` — **works today**, launch-time only, not to a running app | `deep-link` |
| App container | `device copy from --domain-type appDataContainer \| appGroupDataContainer` | `sandbox-browser` |
| Crash logs | `device copy from --domain-type systemCrashLogs` | `crash-catcher` |
| Diagnostics | `device sysdiagnose` | `bug-report` |
| Reboot | `device reboot` | device-bar action |
| Darwin notifications | `device notification post \| observe` | dev tooling |

**`device copy` is not a filesystem.** `--domain-type` is required and drawn
from exactly four values: `temporary`, `appDataContainer`,
`appGroupDataContainer`, `systemCrashLogs`. There is no arbitrary-path access
and therefore no `file-explorer` on iOS hardware — its unsupported state says
so.

**Not on this toolchain, and no capability advertises it:** orientation (the
subcommand exists but no `com.apple.coredevice.feature.*` entry backs it on
either iPhone — verify before shipping), location and time-zone simulation,
URL delivery to an already-running app. These are gated by `DeviceCapability`
and light up if a device ever reports them.

**Not available on hardware at all, and the UI says so plainly:** push
notifications, privacy and keychain writes, User Defaults editing, status bar
overrides, appearance, network monitoring and conditioning, and — for now —
live unified logs: `log stream` has no device flag on this macOS (verified:
zero mentions in `--help`), and `process launch --console` carries only the
launched app's stdout. `SimulatorLogsView.swift:111` hard-requires
`.iosSimulator`; it stays that way until a mechanism exists.

**New invariant test:** `everyIOSDeviceCapableActionResolvesToADevicectlRunner`,
mirroring the simctl and adb versions. **New parser tests:** the
`--json-output` envelope (`jsonVersion`, `outcome`), the device list filter
(the fixture includes a paired-absent device and a Watch), and the
`capabilities` → `DeviceCapability` mapping.

---

## Phase 3 — mirroring and the visual tools

### 3a — the capture spike, then a read-only mirror (PR 6)

Per decision 3: extract `MirrorSource` from the scrcpy-coupled session, spike
the three capture candidates (ScreenCaptureKit on the Simulator window, the
private framebuffer client, screenshot polling), pick one, and ship a
read-only mirror on it. Measure latency and frame rate for each and record the
numbers here. If only polling survives, the mirror ships as "preview" and the
doc says so.

Consequences once a source exists: simulators can appear in the **Mirror
Wall** — after `MirrorWallView.swift:356` and `MirrorWindowView.swift:105`
stop filtering to `.android`, which is PR 1's work — the pop-out mirror works
per-UDID, and `MirrorSessions`' awaited quit-teardown covers them.

**Traps carried over from the Android mirror, all documented in CLAUDE.md and
all applicable here:** a view-model swap must adopt the new display layer in
`updateNSView`; a moved tab keeps its session via `FeatureStateStore`; the
device claim is released in `stopBackgroundWork`, not `onDisappear`.

### 3b — interaction (spike, gated)

Two candidates: the private Indigo HID path via `dlopen` of
`CoreSimulator.framework` + Xcode's `SimulatorKit.framework` (both present),
or synthesised `CGEvent`s into the Simulator.app window (public; needs
Accessibility permission; fragile against window geometry). Either resolves
behind a probe; when neither does, the mirror stays read-only and says why.
`send-text`, `open-dev-menu` and `reload-js` on simulators ride whichever
lands. Private simulator API can change with any Xcode release — design for
the degradation, not against it.

### 3c — the overlay suite

Once a mirror surface exists these are cheap: **design comparison** (image
overlay with opacity plus a slide/curtain compare), **grids**, **rulers**
(coordinates in points), **magnifier**, **colour picker** emitting
SwiftUI/`NSColor`/`UIColor` code (Droidective's rule is RGBA literals, so emit
those), **slow animations** (spike — Simulator.app's own toggle is an app
preference, not a simctl verb). The **VoiceOver reading-order overlay** needs
phase 4's accessibility snapshot and lands **after PR 9**, not with this PR.

### 3d — capture polish

Device **bezels** (a full set runs to well over a hundred assets, so start with
a small curated set), touch indicators, GIF export (we bundle ffmpeg), and a
post-capture editor — which we already have twice over in the screenshot
annotator and the video editor.

---

## Phase 4 — the agent surface

The differentiator. One protocol core in ADBKit, two exposures, both platforms.

**Perception.** A snapshot is `{elements, screen}` where each element carries an
**ephemeral id** valid only within that snapshot, and the snapshot carries a
short **screen hash**. An action targeting a stale hash fails with a typed
`snapshot_changed` error rather than tapping the wrong thing — the single most
important property in the design, because every other failure mode is
recoverable and that one silently corrupts the run. Three verbosity modes
(`nav`, `act`, `debug`), compact delimited rows, a `since <hash>` read that
returns an empty body when nothing moved, and metadata rows for ambiguous
labels, sparse web views and omitted zero-area elements.

**Backends:** iOS Simulator via the accessibility bridge (spike: the private
`SimulatorKit` accessibility path versus an XCUITest-hosted runner — the latter
survives private-API churn, the former needs no app install; the spike picks
one and records why). Android via `uiautomator` dumps.

**Actions:** tap (coordinate *and* element), swipe, scroll, long-press with
multi-touch, type, hardware buttons, biometric match and non-match,
accessibility press, focus.

**Control flow:** `wait` predicates (screen-changed, element-appeared,
keyboard-state), a batched multi-step command that re-snapshots between steps,
and a typed error taxonomy where every code carries a recovery suggestion.

**Exposures:** a `droidective` CLI over `droidectived`, and MCP tools over the
same core following the `McpToolRegistry` declarative-table pattern. Plus a
skill file installed into `~/.claude/skills`.

**Annotated screenshots:** numbered badges over the framebuffer, croppable by
label, type, ids, or rect. Needs a phase 3a source.

---

## Phase 5 — network

### 5a — Network Monitor

Inject a dylib into the app under debug at launch — via a hook in
`~/.lldbinit`, which Xcode's debugger sources — and intercept URLSession from
inside the process, reporting over a local socket. Requires no changes to the
user's app. **Spike first:** confirm the hook fires under a hardened-runtime
app, and note it cannot reach a device without a development-signed build.

The receiving half exists in shape: a localhost listener ingesting an app's
traffic is the Reactotron relay, and the viewer is the API Testing response
pane. What is new is a shipped dylib and a write into the user's home
directory — **explicitly opt-in**, installed and uninstalled from Settings,
with the hook's boundaries marked and removable.

### 5b — Network conditioning

Spike `dnctl`/`pfctl` dummynet (decision 4). Profiles: offline, 2G/Edge, 3G,
Wi-Fi, a mixed "very bad" profile, total packet loss, plus latency and
bandwidth as first-class knobs. If pf cannot be scoped usefully, the fallback
is a signed `NEFilter` system extension — its own sub-project.

---

## Phase 6 — build analytics

Xcode build-time analytics: parse `xcactivitylog`, track build durations,
compare across a team. Sequenced last because it is the only item here that is
not device tooling. **Recommendation: build phases 1–5, then decide.**

---

## Test and gate strategy

- **A parser is pure and static, and gets a test in the same change.** Split
  output on `.newlines`, never `"\n"`.
- **Every runner gets an argument-vector test** through `MockProcessRunner` —
  and the `shellQuote`d form for anything that reaches a device shell.
- **A cross-feature rule is a loop over `FeatureRegistry.all`.** New
  invariants: `everyIOSCapableViewHasASimulatorPath` (P1),
  `everyIOSDeviceCapableActionResolvesToADevicectlRunner` (P2), the parity
  derivation test (PR 1: no id whose `platforms` excludes `.android` is ever
  emitted as todo), and a daemon test that every `DevicePlatform` case
  round-trips through the protocol's platform field (PR 1).
- **`FixtureProcessRunner`**: record real `simctl`/`devicectl` output once via
  the harness and replay it in CI. Redaction scrubs UDIDs and device names.
  The `devicectl list` fixture must include a paired-absent device and a
  non-phone device type.
- **`PortabilityGuardTests`** stays green with an empty allowlist — noting it
  does not guard the pure-Foundation toolchain services (decision 6).
- **`make verify`** unchanged; `make test-emulator` gains a simulator
  equivalent gated on a booted sim so CI skips cleanly.
- **Manual verification** for physical devices, mirroring and network, in
  `docs/manual-verification.md`.

## Risk register

| Risk | Likelihood | Mitigation |
|---|---|---|
| No acceptable public capture source for the simulator mirror | **High** — `recordVideo` is not one, and ScreenCaptureKit captures a window, not a device | PR 6 is a spike with three candidates and an explicit "ship as preview" floor; nothing downstream assumes 60 fps |
| Private simulator API changes across Xcode releases | High — inherent to any private path | Probe and degrade; keep the XCUITest-runner fallback designed for AX; never make a private path the only route to a shipped feature |
| Accessibility overrides beyond the two `simctl ui` verbs turn out impossible | Medium | Row 6 is a spike; the feature ships with two toggles if so |
| pf cannot scope to one process's traffic | High — pf matches hosts/ports | Spike first; the system extension is the costed fallback |
| `devicectl` capabilities never include orientation/location on shipping devices | Medium | `DeviceCapability` gates them; they are not promised in any UI |
| Registry count churn | Certain, harmless | Bump per phase in the same PR |
| Phase 1 views built as binary sim/Android before PR 1 lands | High if PRs 2–4 go first | PRs 2–4 depend on PR 1 (sequencing) |
| Scope: six phases on one branch | High | Each phase is its own PR; the dependency graph is below and is honest |
| The name stops matching the product | Certain | Product decision, out of scope |

## PR sequencing

Each row is one PR onto this integration branch, green build and tests,
warning-free. The branch merges to `main` per phase or as a whole.

| PR | Contents | Depends on |
|---|---|---|
| 1 | `DevicePlatform.iosDevice`; the 20 non-exhaustive sites converted and the three `= .android` defaults removed; daemon platform parse + protocol doc; `DeviceCapability` over the capabilities set; `DevicectlClient` skeleton + envelope/list/capability parsers + fixtures; parity script derives `GATED` from the registry + test; `needsScrcpy` made platform-scoped. No user-visible change. | — |
| 2 | Phase 1a: app lifecycle + hub members, locale, install (`.ipa`), container/sandbox, device info, process death | **PR 1** |
| 3 | Phase 1b: privacy (Apps pane), location, accessibility (verified pair + spike), status-bar editor | **PR 1** |
| 4 | Phase 1c: User Defaults, keychain, pasteboard (+ send-text note), addmedia routing, sim lifecycle, screen recording, crash/bug report, performance spike | **PR 1** |
| 5 | Phase 2: `CoreDeviceMonitor` + filter, every capability-backed feature, `--payload-url` deep links | PR 1 |
| 6 | Phase 3a: `MirrorSource` extraction + the capture spike + read-only mirror on the winner. **Largest PR in the plan.** | PR 1 |
| 7 | Phase 3b: input spike, probed and degrading; `send-text`/dev-menu/reload on sims | PR 6 |
| 8 | Phase 3c/3d minus VoiceOver: overlays, bezels, GIF, touch indicators | PR 6 |
| 9 | Phase 4: protocol core + CLI + MCP + skill, both platforms | PR 6 for badges |
| 10 | VoiceOver reading-order overlay | PR 8, PR 9 |
| 11 | Phase 5a: network monitor (after its hardened-runtime spike) | — |
| 12 | Phase 5b: conditioning (after the pf spike) | — |

---

## Appendix A — verified command inventory

Everything below was run against Xcode 26.5 (17F42) / `devicectl` 518.31 /
macOS 26.6.2 on the dev machine. This is the source of truth for the specs
above; a mechanism not listed here is a spike until it is.

**`simctl` subcommands:** `addmedia · appinfo · boot · clone · create · delete ·
diagnose · erase · get_app_container · getenv · icloud_sync · install ·
install_app_data · io · keychain · launch · list · listapps · location ·
logverbose · openurl · pair · pair_activate · personalization · privacy · push ·
rename · runtime · shutdown · spawn · status_bar · terminate · ui · uninstall ·
unpair · upgrade`

**`simctl privacy`** — actions `grant | revoke | reset`; services `all ·
calendar · contacts-limited · contacts · location · location-always ·
photos-add · photos · media-library · microphone · motion · reminders · siri`.
`grant`/`revoke` require a bundle id; `reset` does not. Some changes terminate
the running app.

**`simctl location`** — `list`, `clear`, `set <lat,lon>`, `run <scenario>`,
`start [--speed=<m/s>] [--distance=<m>|--interval=<s>] <lat,lon> …` (≥2
waypoints, `-` reads stdin).

**`simctl ui`** — exactly three options: `appearance [light|dark]`,
`increase_contrast [enabled|disabled]`, `content_size
[increment|decrement|<size>]` with twelve named sizes (extra-small … 
accessibility-extra-extra-extra-large). All three read state when called
bare.

**`simctl status_bar`** — `list | clear | override` with `--time`,
`--dataNetwork hide|wifi|3g|4g|lte|lte-a|lte+|5g|5g+|5g-uwb|5g-uc`,
`--wifiMode searching|failed|active`, `--wifiBars 0-3`, `--cellularMode
notSupported|searching|failed|active`, `--cellularBars 0-4`, `--operatorName`,
`--batteryState charging|charged|discharging`, `--batteryLevel <int>`.

**`simctl io`** — `enumerate`, `poll`, `screenshot` (accepts `-` for stdout),
`recordVideo [--codec=h264|hevc] [--display] [--mask=ignored|black] [--force]
<file or url>`, `screenConfig`. **`recordVideo` probe, iPhone 13 mini, iOS
26.5:** to a FIFO without `--force` → "cannot save recorded video output into
a file that already exists"; with `--force` → the FIFO is **unlinked**;
`file:///…` → `NSURLErrorDomain -3000 Cannot create file`; `/dev/stdout` →
exit 209, 0 bytes; `-` is not accepted. To a plain path: no fd on the output
during the take, `Recording completed. Writing to disk.` on SIGINT, and the
result is `ftyp · moov · wide · mdat` — moov first. It is a recorder.

**`simctl launch`** — `[-w] [-a arch] [--console|--console-pty]
[--stdout=<path>] [--stderr=<path>] [--terminate-running-process]
[--checked-allocations] <device> <bundle> [argv…]`. Env via `SIMCTL_CHILD_`
prefix. Apple's documented locale arguments `-AppleLanguages "(xx)"`
`-AppleLocale xx_YY` ride in argv.

**`simctl keychain`** — `add-root-cert <path>`, `add-cert <path>`, `reset`.

**Simulator accessibility plist** (`…/data/Library/Preferences/
com.apple.Accessibility.plist` on the 13 mini): keys present —
`GrayscaleDisplay`, `InvertColorsEnabled`, `ReduceMotionEnabled`,
`AXSSystemUIProcessAppSmartInvertEnabledPreference`. Absent: anything for
reduce transparency, bold text, button shapes, differentiate without colour,
on/off labels.

**`log stream`** — **no `--device` or `--device-name` option** on macOS 26.6.2
(`--help` has zero occurrences of "device").

**`devicectl`** — top level `device · diagnose · list · manage`. `device`:
`copy · info · install · notification · orientation · process · reboot ·
sysdiagnose · uninstall`. `--json-output <path>` is the only supported
programmatic interface; the stdout table is human-only.
- `list devices --json-output` → `{info:{jsonVersion:3, outcome, version,
  commandType, arguments}, result:{devices:[{identifier, capabilities,
  connectionProperties, deviceProperties, hardwareProperties, tags,
  visibilityClass}]}}`. Returns paired-but-absent devices and all device types.
- `device info details` → `capabilities: [String]`, 36 on the iPhone 15 Pro
  Max, including `com.apple.coredevice.feature.{installapp, launchapplication,
  listFiles, transferFiles, rebootdevice, capturesysdiagnose, getlockstate,
  viewdevicescreen}` and `com.apple.dt.customer.postdarwinnotification`. None
  for orientation, openurl, or location.
- `device process launch --payload-url <url>` — present.
- `device copy from --domain-type <temporary|appDataContainer|
  appGroupDataContainer|systemCrashLogs>` — **required**, closed set.

**Environment as audited:** Xcode 26.5, Swift 6.3.2, iOS 26.5 runtime, 4
available simulators (iPhone 13 mini `76C16930-…` used for probes), **two
connected iPhones** (16 Plus, 15 Pro Max) and one paired Apple Watch,
`xcodegen`/`adb`/`scrcpy`/`ffmpeg`/`gh`/`node 22` on PATH,
`CoreSimulator.framework` and Xcode's `SimulatorKit.framework` present.

## Appendix B — mechanisms for what simctl cannot reach

**Live framebuffer.** `recordVideo` is not a stream (Appendix A). Three real
routes: **ScreenCaptureKit** capturing the Simulator.app window — public,
needs Screen Recording permission, includes chrome until cropped; the
**private CoreSimulator framebuffer client** that Meta's open-source `idb`
(`FBSimulatorControl`/`FBControlCore`) wraps — fast, chrome-free, breakable
per Xcode release; **`simctl io screenshot` polling** — public, a few fps.
Decision 3 spikes all three. On hardware, the `viewdevicescreen` capability is
advertised but no `devicectl` verb exposes it.

**HID input.** No public route to a simulator. Private Indigo messages via
`dlopen` of CoreSimulator/SimulatorKit, or synthesised `CGEvent`s into the
Simulator window (public, fragile). `PortabilityGuardTests` catches neither —
`dlopen` is not an import — so the gate is a `#if canImport` on the file plus
a runtime probe, by convention rather than by test.

**Accessibility reads.** The private SimulatorKit path, or an XCUITest runner
hosted in the simulator — slower to start and needs a build, but public and
durable. Phase 4's spike.

**Physical device control.** Apple's `devicectl` (CoreDevice). Fully
supported, no private API; its constraints are the JSON-to-a-file interface
and the four-domain `copy` surface noted above.

**Per-app network conditioning.** A `NEFilter` content-filter system
extension is the only per-process route; `dnctl`/`pfctl` dummynet matches
hosts and ports and is the cheaper approximation. Decision 4 spikes pf first.

**Network request monitoring.** A dylib injected at launch via an
`~/.lldbinit` hook, intercepting URLSession in-process. No app changes; writes
to the user's home directory and ships executable code into their debug
sessions — hence opt-in. Untested under hardened runtime; phase 5a's spike.
