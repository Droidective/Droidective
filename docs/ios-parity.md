# iOS Parity — bringing the iOS side up to the Android side

Droidective is an adb tool with a simulator courtesy shelf. Of 61 features, 10
touch iOS at all, every one of them a thin `simctl` wrapper, and a physically
connected iPhone never appears in the device bar. This document is the
end-to-end spec for closing that gap.

The measure of done is internal, not external: **for every Android capability
the app already ships, the iOS equivalent exists or the UI explains why the
platform cannot do it** — plus the iOS-specific capabilities the Apple
toolchains expose and Android has no counterpart for. One window, both
platforms, neither one the afterthought.

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

Read down Droidective's own feature list and ask what the iOS answer is. That
exercise produces the whole plan, and it sorts itself into four groups.

**Already done (10).** Screenshot (with the annotation editor), dark mode, demo
mode, fake battery, push notifications, deep links, simulator boot/shutdown,
the Simulate hub's shared sections, live override read-back, and iOS Logs.
Reactotron and the JS Console also work against a simulator incidentally, since
both are device-free and a simulator shares the Mac's loopback.

**Has an Android feature with a straightforward iOS equivalent (phase 1).**
Apps explorer and app management, install app, app permissions, sandbox
browser, device info, crash catcher, screen record, and the emulator manager's
create/clone/wipe/rename lifecycle. Each of these already has a working
Android implementation, a view, and a place in the sidebar — what is missing is
a `simctl`-backed service behind the same UI.

**Has no Android counterpart, because the platform is different (phase 1).**
Location simulation, accessibility environment overrides and dynamic type, the
full status-bar editor, the User Defaults editor, keychain actions, pasteboard
sync, and media import. These are additions rather than ports; iOS exposes them
and Android either does not or does it another way.

**Needs machinery we do not have yet (phases 2–5).** A physically connected
iPhone or iPad as a first-class device. A live, interactive mirror — which on
Android is scrcpy and on iOS is not. The visual inspection tools that only make
sense once a mirror exists: design comparison, grids, rulers, magnifier, colour
picker, slowed animations, and a VoiceOver reading-order overlay. An interface
a coding agent can drive. Network request monitoring and per-app network
conditioning.

Two capabilities run the other way, where the iOS side is ahead and the work is
to keep it that way: **iOS Logs** is the best log viewer in the app, and the
**MCP server** built for Reactotron is infrastructure the agent surface in phase
4 gets to reuse.

The engineering consequence worth internalising before reading on: almost
nothing in that fourth group comes from `simctl`. Framebuffer streaming, HID
input, accessibility reads, physical-device control, network interception and
network conditioning each need a different mechanism, and each mechanism is a
project rather than a feature. Appendix B surveys the four that matter and what
each costs; the phases below are ordered so we pay for them one at a time, as
late as possible.

## Decisions taken up front

These were open questions. They are now decided, with the reasoning recorded so
a reviewer can disagree with the reason rather than the outcome.

### 1. Three platforms, not two

`DevicePlatform` gains `.iosDevice` alongside `.android` and `.iosSimulator`.
A simulator and a physical iPhone differ in toolchain (`simctl` vs `devicectl`),
in capability, and in failure modes; collapsing them into one "iOS" case would
push a platform check into every runner. Three cases means every `switch` over
the enum becomes a build error until it is handled, which is exactly the
property we want — the same reason `FeatureDetailRoute` is exhaustive.

### 2. A newer Xcode is a capability probe, never a hard requirement

Xcode 26.5 is what is installed, and some physical-device capabilities need a
newer toolchain. Nothing in this plan blocks on installing one.
`DeviceCapability` (ADBKit, pure over a probed version string) answers "can this
toolchain do X?", and a feature that cannot run says so along with the version
it needs — the same shape as the Doctor pointing at an install source instead of
installing anything itself. When a newer Xcode lands, those features light up
with no code change beyond the probe table.

### 3. Mirroring: public path first, private path second, and they are separate PRs

Display and input have completely different risk profiles, so they ship
separately:

- **Display is public API.** `simctl io <udid> recordVideo` writes H.264/HEVC
  "to the specified file *or url*". Pointed at a FIFO, that is a live encoded
  video stream — and we already own the consumer: the Mirror stack's
  VideoToolbox decoder and display-layer renderer, built for scrcpy. A
  read-only iOS mirror is therefore a transport swap, not a new subsystem, and
  it cannot break when Apple moves a private symbol.
- **Input is private API.** There is no public way to deliver a HID touch to a
  simulator. That means `dlopen` against `CoreSimulator.framework` and Xcode's
  `SimulatorKit.framework` (both present on this machine), behind a
  symbol-resolution probe that degrades to a read-only mirror when it fails.

The alternative was vendoring a third-party simulator-control framework
(Appendix B). We are not doing that: it is a large Objective-C codebase that
would dwarf ADBKit, sit awkwardly against the portability guard, and couple our
mirror to someone else's release cadence. Shipping display first means the
feature is useful and safe before we take on any private-API exposure at all.

### 4. Network conditioning: spike `dnctl`/`pfctl` before committing to a system extension

A per-app `NEFilter` content-filter system extension is a signing project
before it is a feature: it needs the NetworkExtension entitlement, a
provisioning profile, hardened runtime **on**, and notarization — against an app
that is currently ad-hoc signed with hardened runtime off and no entitlements
file. Worse for development, `systemextensionsctl developer` refuses to run
while SIP is enabled, and the dev machine has no Developer ID Application
identity in its keychain (it exists only as CI secrets).

macOS still ships `dnctl` and `pfctl` — the dummynet machinery behind Apple's
own Network Link Conditioner. If a pf anchor scoped to the simulator's traffic
can deliver useful profiles, we get conditioning with zero signing work. The
spike decides; the system extension stays on the table as the fallback, with
its own signing sub-project.

### 5. The agent surface covers both platforms, and ships as CLI *and* MCP

Two exposures, because they are good at different things. A single CLI binary
means a host like Claude Code approves it once and stops prompting — a real
ergonomic win an MCP server does not get. MCP, in return, is typed,
discoverable, and already proven here. We do not have to choose:
`droidectived` already exists with a documented protocol, and `ReactotronMCP`
already proves out a declarative 10-tool MCP surface. So: one protocol core in
ADBKit, exposed twice.

And the perception/action model is defined for **Android as well as iOS** from
day one. `uiautomator` dumps and `input` events fit the same
snapshot-then-act shape, and building it iOS-first then retrofitting is how it
ends up permanently iOS-shaped.

### 6. Every iOS feature is Mac-only, and the parity tracker says so

`simctl`, `devicectl` and the private simulator frameworks are macOS
toolchains. All of this is `#if canImport`-gated in ADBKit and marked
out-of-scope for the Windows/Linux port — the treatment `ios-logs` and
`push-notification` already get. `scripts/generate-parity-tracker.py` is
regenerated per phase, never hand-edited.

## Architecture: the seams this opens

| Seam | Change |
|---|---|
| `DevicePlatform` | Third case `.iosDevice`. Every switch site becomes a compile error until handled — that is the point. |
| Exec clients | `DevicectlClient` joins `AdbClient` and `SimctlClient`. **Trap:** devicectl's only stable machine interface is `--json-output <path>` *to a file* — stdout is explicitly not guaranteed. The client writes a temp file and reads it back; the parser is pure over that JSON. |
| Discovery | `CoreDeviceMonitor` joins `DeviceMonitor` and `SimulatorMonitor`; `AppCore` merges three lists instead of two. Poll cadence widens in background mode like the other two. |
| Capability | `DeviceCapability` (pure) maps a probed toolchain version to a feature set. Gates the newer-Xcode work. |
| Feature registry | `platforms` sets gain `.iosDevice`. `hasAll61Features` becomes a moving count — bump per phase. New invariant tests per phase (below). |
| Portability | Every new Apple-only import sits inside a `#if canImport(...)` gate or `PortabilityGuardTests` fails. Its allowlist stays empty. |
| Drop routing | `FileDropRouter` learns platform: an image dropped on a simulator is `simctl addmedia`, on Android it is push + `MediaScan`, on a physical iPhone it is `devicectl device copy`. One table, three destinations. |
| Parity tracker | Regenerated each phase; every new id marked Mac-only. |
| Naming | Complete iOS support makes "Droidective" a misnomer. Flagged as a product decision, not an engineering one — no rename is in scope here. |

---

## Phase 1 — the simctl sweep

**No new dependencies, no private API, no signing work.** Every item is the
same shape as code that already works, and the verified syntax is in Appendix A.
This is the phase that makes the iOS side credible.

| # | Feature | id | Kind | Command |
|---|---|---|---|---|
| 1 | App lifecycle on sims | extend `apps` | view | `listapps`, `appinfo`, `launch` (+`--terminate-running-process`, `SIMCTL_CHILD_*` env, argv), `terminate`, `uninstall` |
| 2 | Install on sims | extend `install-app` | view | `install` (`.app`; `.ipa` unpacked to `Payload/*.app`) — extends `AppPackageFormat` |
| 3 | Privacy & permissions | extend `permissions` | view | `privacy <dev> grant\|revoke\|reset <service> [bundle]` — 12 services + `all` |
| 4 | Location simulation | `location` (new) | view | `location set <lat,lon>`, `run <scenario>`, `start --speed --distance\|--interval <waypoints…>`, `clear`, `list` |
| 5 | Accessibility overrides | `accessibility` (new) | view | `ui increase_contrast`, `ui content_size` (12 categories, + increment/decrement); invert colours / grayscale / reduce motion / reduce transparency / bold text / button shapes / differentiate-without-colour / on-off labels via the sim's `com.apple.Accessibility` prefs + a change notification |
| 6 | Status bar editor | extend `demo-mode` | view | `status_bar override` — full surface: `--time`, `--dataNetwork` (10 values), `--wifiMode`/`--wifiBars`, `--cellularMode`/`--cellularBars`, `--operatorName`, `--batteryState`/`--batteryLevel`. Keeps the one-click 9:41 preset. |
| 7 | User Defaults editor | `user-defaults` (new) | view | `get_app_container <bundle> data\|groups` → read/write `Library/Preferences/*.plist`, standard + app groups |
| 8 | App container browsing | extend `sandbox-browser` | view | `get_app_container <bundle> app\|data\|groups` |
| 9 | Screen recording on sims | extend `screen-record` | view | `io recordVideo --codec h264\|hevc --mask --display` |
| 10 | Keychain actions | `sim-keychain` (new) | actions | `keychain reset`, `add-cert`, `add-root-cert` — hub members |
| 11 | Media & contacts import | drop-routed | — | `addmedia` — wired through `FileDropRouter`, so dropping a photo on a simulator Just Works |
| 12 | Pasteboard sync | `pasteboard` (new) | actions | `pbcopy`, `pbpaste`, `pbsync` |
| 13 | Simulator lifecycle | extend `emulators` | view | `create`, `clone`, `delete`, `rename`, `erase` (confirmed), `upgrade`, `runtime` — the AVD-parity set |
| 14 | Crash reports on sims | extend `crash-catcher` | view | `simctl diagnose` + `~/Library/Logs/DiagnosticReports` |
| 15 | Device info on sims | extend `device-info` | view | `getenv`, `appinfo`, runtime/device-type metadata from `list -j` |

**Services added:** `SimulatorAppService`, `SimulatorPrivacyService`,
`SimulatorLocationService`, `SimulatorAccessibilityService`,
`StatusBarOverrideBuilder` (pure), `UserDefaultsContainerService`,
`SimulatorLifecycleService`, `SimulatorKeychainService`, `SimulatorMediaService`,
`SimulatorPasteboardService`.

**Notes worth writing down now:**

- `simctl privacy`'s real service list is **12 + `all`**: calendar,
  contacts-limited, contacts, location, location-always, photos-add, photos,
  media-library, microphone, motion, reminders, siri. Camera, notifications and
  health are *not* simctl privacy services, however often they are assumed to
  be — do not spec them.
- `simctl` takes no `-s`; the UDID is positional. `SimctlClient` already
  handles this and callers pass full argument vectors.
- Every path/URL/free-text value going through `simctl spawn … sh -c` needs
  `shellQuote()`, same security boundary as adb. Argument-vector `simctl`
  calls (the common case) need no quoting — assert the exact vector in tests.
- `simctl ui content_size` accepts `increment`/`decrement` as well as the 12
  named categories; the pure builder should model all three.

**Deliverable:** iOS goes from 10 → ~25 features. Registry count bumped,
`everyIOSCapableActionResolvesToASimctlRunner` extended, parity tracker
regenerated.

---

## Phase 2 — physical iOS devices

A third platform. An iPhone is connected to the dev machine and `devicectl`
518.31 is present, so this is verifiable end to end today.

**Works on Xcode 26.5 (now):**

| Capability | Command |
|---|---|
| Discovery, pairing state | `devicectl list devices` |
| Device info | `device info details \| hardware \| lockState` |
| Install / uninstall | `device install app`, `device uninstall app` (`.ipa`) |
| Launch / terminate | `device process launch` (+`--console`), `process list`, signal |
| File transfer both ways | `device copy` → makes **File Explorer** cross-platform |
| Orientation | `device orientation` |
| Reboot | `device reboot` |
| Diagnostics | `device sysdiagnose` → makes **Bug Report** cross-platform |
| Darwin notifications | `device notification post \| observe` |
| Live device logs | `log stream --device` — spike: confirm it reaches a paired iPhone. If it does, **iOS Logs works on hardware**, which is the single highest-value item in this phase |

**Behind the capability probe:** deep links (`devicectl` on 26.5 has no
`openurl`) and location/time-zone simulation.

**Not available on hardware, and the UI must say so plainly:** push
notifications, privacy and keychain writes, User Defaults editing, network
monitoring and conditioning. These are platform limits, not gaps — the honest
empty state is the feature, the same way an Android-only feature already
explains itself when a simulator is selected.

**New invariant test:** `everyIOSDeviceCapableActionResolvesToADevicectlRunner`,
mirroring the simctl and adb versions.

---

## Phase 3 — mirroring and the visual tools

### 3a — read-only mirror (public API)

`simctl io <udid> recordVideo` → FIFO → the existing VideoToolbox decoder and
`MirrorRenderer` display layer. New transport, existing everything else.
Consequences that fall out for free: simulators appear in the **Mirror Wall**,
the pop-out mirror window works per-UDID, and `MirrorSessions`' awaited
quit-teardown already covers them.

**Traps carried over from the Android mirror, all documented in CLAUDE.md and
all applicable here:** a view-model swap must adopt the new display layer in
`updateNSView`; a moved tab keeps its session via `FeatureStateStore`; the
device claim is released in `stopBackgroundWork`, not `onDisappear`.

### 3b — interaction (private API, gated)

`dlopen` `CoreSimulator.framework` + Xcode's `SimulatorKit.framework`; resolve
the Indigo HID message symbols behind a probe. If resolution fails — a new
Xcode, a hardened path — the mirror stays read-only and says why. **Known
headwind:** the remote-automation socket that simulator accessibility and
automation depend on is reported to be restricted in Xcode 27, so Apple is
actively narrowing this. Design for the degradation, not against it.

### 3c — the overlay suite

Once a mirror surface exists these are all cheap: **design comparison** (image
overlay with opacity plus a slide/curtain compare), **grids**, **rulers**
(coordinates in points), **magnifier**, **colour picker** emitting
SwiftUI/`NSColor`/`UIColor` code (Droidective's rule is RGBA literals, so emit
those), **slow animations**, and a **VoiceOver reading-order overlay** —
numbered badges in traversal order, which needs phase 4's accessibility
snapshot and so lands after it.

### 3d — capture polish

Device **bezels** (a full set runs to well over a hundred assets, so start with
a small curated set and grow it), touch indicators, GIF export (we already
bundle ffmpeg), and a post-capture editor — which we already have twice over in
the screenshot annotator and the video editor.

---

## Phase 4 — the agent surface

The differentiator. One protocol core in ADBKit, two exposures, both platforms.

**Perception.** A snapshot is `{elements, screen}` where each element carries an
**ephemeral id** valid only within that snapshot, and the snapshot carries a
short **screen hash**. An action targeting a stale hash fails with a typed
`snapshot_changed` error rather than tapping the wrong thing — this is the
single most important property in the design, because every other failure mode
is recoverable and that one silently corrupts the run. Three verbosity modes
(`nav` for "where am I", `act` for interactive elements only, `debug` for the
full tree with traits), compact delimited rows to keep token cost down, and a
`since <hash>` read that returns an empty body when nothing moved. Metadata
rows for the cases that otherwise cause silent misbehaviour: ambiguous labels,
sparse web views, omitted zero-area elements.

**Backends:** iOS Simulator via the accessibility bridge (spike: the private
`SimulatorKit` accessibility path versus an XCUITest-hosted runner — the latter
survives Apple's private-API churn, the former needs no app install; the spike
picks one and the reason gets recorded here). Android via `uiautomator` dumps,
which existing tooling already proves out.

**Actions:** tap (coordinate *and* element), swipe, scroll, long-press with
multi-touch, type, hardware buttons, biometric match and non-match,
accessibility press (for elements that exist but are not hittable by
coordinates), focus.

**Control flow:** `wait` predicates (screen-changed, element-appeared,
keyboard-state), a batched multi-step command that re-snapshots between steps
so ids stay valid, and a typed error taxonomy where every code carries a
recovery suggestion the agent can act on.

**Exposures:** a `droidective` CLI over `droidectived` (one binary, one host
approval), and MCP tools over the same core following the `McpToolRegistry`
declarative-table pattern. Plus a skill file installed into `~/.claude/skills`
so the surface is discoverable without the user reading docs.

**Annotated screenshots:** numbered badges over the framebuffer, croppable by
label, type, ids, or rect. Needs phase 3a.

---

## Phase 5 — network

### 5a — Network Monitor

Inject a dylib into the app under debug at launch — via a hook in
`~/.lldbinit`, which Xcode's debugger sources — and intercept URLSession from
inside the process, reporting over a local socket. This requires no changes to
the user's app, which is the whole point: the alternative is asking them to add
an SDK, and adoption of that is close to zero.

For us the receiving half already exists in shape: a localhost listener
ingesting an app's traffic is precisely the Reactotron relay, and the viewer is
precisely the API Testing response pane. What is new is a shipped dylib and
writing to a file in the user's home directory — so this is **explicitly
opt-in**, installed and uninstalled from Settings, with the hook's boundaries
marked and removable. Nothing gets written to `~/.lldbinit` without a click.

### 5b — Network conditioning

Spike `dnctl`/`pfctl` dummynet first (decision 4). Profiles to cover: offline,
2G/Edge, 3G, Wi-Fi, a mixed "very bad" profile, and total packet loss, plus
latency and bandwidth as first-class knobs. If pf cannot be scoped usefully,
the fallback is a signed `NEFilter` system extension — a sub-project covering a
new target, the NetworkExtension entitlement, a provisioning profile, hardened
runtime, notarization, and a dev story that does not require disabling SIP.

---

## Phase 6 — build analytics

Xcode build-time analytics: parse `xcactivitylog`, track build durations, and
compare across a team. Sequenced last because it is the only item here that is
not device tooling — it is a different product shape sharing a window — and
because nothing else depends on it. **Recommendation: build phases 1–5, then
decide**, by which point we will know whether anyone is asking for it.

---

## Test and gate strategy

The existing gates carry most of this; what has to be added is listed per phase
above. The standing rules:

- **A parser is pure and static, and gets a test in the same change.** Split
  output on `.newlines`, never `"\n"`.
- **Every runner gets an argument-vector test** asserting the exact vector
  through `MockProcessRunner` — and the `shellQuote`d form for anything that
  reaches a device shell.
- **A cross-feature rule is a loop over `FeatureRegistry.all`**, not review
  folklore. Three new invariants across the phases (simctl extension, devicectl,
  agent-surface coverage).
- **`FixtureProcessRunner`**: record real `simctl`/`devicectl` output once via
  the harness and replay it in CI, so parsers face genuine output with no
  device. Redaction runs at record time — UDIDs and device names are scrubbed.
- **`PortabilityGuardTests`** must stay green with an empty allowlist.
- **`make verify`** tiers unchanged; `make test-emulator` gains a simulator
  equivalent (`MIRROR_LIVE_TEST=1`-style gating on a booted sim so CI skips
  cleanly).
- **Manual verification**: physical-device work, mirroring and the network
  phases each add a line to `docs/manual-verification.md`, because no agent can
  check them.

## Risk register

| Risk | Likelihood | Mitigation |
|---|---|---|
| Apple closes the private simulator automation path | **High** — a restriction is already reported for Xcode 27 | Split display (public) from input (private); probe and degrade; keep the XCUITest-runner fallback designed |
| System extension signing blocks conditioning | High | `dnctl`/`pfctl` spike first; the extension is a scoped fallback with its own signing sub-project |
| `recordVideo`-to-FIFO has unusable latency for interaction | Medium | Measure in the 3a spike before 3b is planned; fall back to the private framebuffer client |
| `log stream --device` does not reach a paired iPhone | Medium | Spike in phase 2; the feature is additive, so it drops out without affecting the rest |
| Feature count churn breaks registry tests repeatedly | Certain, and harmless | Bump per phase in the same PR; the tests exist precisely to force this |
| Scope: six phases is a lot of surface for one branch | High | Each phase is an independent PR onto this integration branch; nothing below depends on anything above it except 3b→3a and 4's badges→3a |
| The name stops matching the product | Certain | Product decision, deliberately out of scope here |

## PR sequencing

Each row is one PR onto this integration branch, green build and tests,
warning-free. The branch merges to `main` per phase or as a whole, whichever
the release cadence prefers.

| PR | Contents | Depends on |
|---|---|---|
| 1 | `DevicePlatform.iosDevice` + `DeviceCapability` + `DevicectlClient` skeleton + parser tests. No user-visible change. | — |
| 2 | Phase 1a: app lifecycle, install, container/sandbox, device info on sims | — |
| 3 | Phase 1b: privacy, location, accessibility overrides | — |
| 4 | Phase 1c: status bar editor, User Defaults, keychain, pasteboard, addmedia drop routing, sim lifecycle, screen recording, crash reports | — |
| 5 | Phase 2: physical device discovery + the Xcode-26.5 capability set | PR 1 |
| 6 | Phase 3a: read-only simulator mirror + Mirror Wall | — |
| 7 | Phase 3b: simulator input, probed and degrading | PR 6 |
| 8 | Phase 3c/3d: overlays and capture polish | PR 6 |
| 9 | Phase 4: protocol core + CLI + MCP + skill, both platforms | PR 6 for badges |
| 10 | Phase 5a: network monitor | — |
| 11 | Phase 5b: conditioning, after the spike | — |

---

## Appendix A — verified command inventory

Everything below was run against Xcode 26.5 / `devicectl` 518.31 on the dev
machine. This is the source of truth for the specs above; do not spec a flag
that is not here without re-verifying.

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

**`simctl location`** — `list`, `clear`, `set <lat,lon>`,
`run <scenario>`, `start [--speed=<m/s>] [--distance=<m>|--interval=<s>]
<lat,lon> … <latN,lonN>` (≥2 waypoints, `-` reads from stdin). Decimal `.`,
field separator `,`.

**`simctl ui`** — `appearance [light|dark]`, `increase_contrast
[enabled|disabled]`, `content_size [increment|decrement|<size>]` where size is
one of extra-small · small · medium · large · extra-large ·
extra-extra-large · extra-extra-extra-large · accessibility-medium ·
accessibility-large · accessibility-extra-large ·
accessibility-extra-extra-large · accessibility-extra-extra-extra-large. All
three also *read* current state when called with no argument.

**`simctl status_bar`** — `list | clear | override` with `--time` (ISO date
strings also set the date), `--dataNetwork hide|wifi|3g|4g|lte|lte-a|lte+|5g|
5g+|5g-uwb|5g-uc`, `--wifiMode searching|failed|active`, `--wifiBars 0-3`,
`--cellularMode notSupported|searching|failed|active`, `--cellularBars 0-4`,
`--operatorName <string>`, `--batteryState charging|charged|discharging`,
`--batteryLevel <int>`.

**`simctl io`** — `enumerate [--poll]`, `poll`, `screenshot`,
`recordVideo [--codec=h264|hevc] [--display=<display>] [--mask=ignored|black]
[--force] <file or url>`, `screenConfig power <on|off>` and
`screenConfig geometry <w>x<h>[@<scale>]`. `recordVideo` writes
`Recording started` to stderr on the first frame — that is the readiness signal.

**`simctl launch`** — `[-w] [-a arch] [--console|--console-pty]
[--stdout=<path>] [--stderr=<path>] [--terminate-running-process]
[--checked-allocations] <device> <bundle> [argv…]`. Environment variables pass
through a `SIMCTL_CHILD_` prefix on the calling environment.

**`simctl keychain`** — `add-root-cert <path>`, `add-cert <path>`, `reset`.

**`devicectl`** — top level `device · diagnose · list · manage`.
`device`: `copy · info · install · notification · orientation · process ·
reboot · sysdiagnose · uninstall`. **`--json-output <path>` is documented as
the only supported programmatic interface**; stdout is explicitly not stable.

**Environment as audited:** Xcode 26.5 (17F42), Swift 6.3.2, iOS 26.5 runtime,
4 available simulators, one connected iPhone plus two paired devices,
`xcodegen`/`adb`/`scrcpy`/`ffmpeg`/`gh`/`node 22` on PATH, and both
`CoreSimulator.framework` and Xcode's `SimulatorKit.framework` present.

## Appendix B — mechanisms for what simctl cannot reach

Four capabilities have no public `simctl` route. These are the options for
each, and what each costs. The phases above choose among them; this is the
reference for why.

**Framebuffer, HID input, accessibility reads.** Two routes. `CoreSimulator`
and Xcode's private `SimulatorKit` expose the framebuffer client and the Indigo
HID message types directly — fast, no app install, and private, so it can break
on any Xcode release. Alternatively Meta's open-source `idb`
(`FBSimulatorControl` / `FBControlCore` / `XCTestBootstrap`) wraps exactly
those private paths behind a maintained Objective-C layer, available either as
vendored frameworks or as the `idb_companion` daemon. Decision 3 takes neither
for display — public `recordVideo` covers it — and the direct `dlopen` for
input. A third route exists for accessibility specifically: host an XCUITest
runner inside the simulator, which is slower to start and needs a build, but is
public API and survives private-symbol churn.

**Physical device control.** Apple's `devicectl` (CoreDevice), shipped with
Xcode. Fully supported, no private API, and the only sanctioned route since the
older device-support daemons were retired. Its constraint is the
JSON-to-a-file interface noted in the seams table.

**Per-app network conditioning.** A `NEFilter` content-filter system extension
is the only way to condition one app's traffic while leaving the Mac's own
connection alone — and it is a signing and distribution project (decision 4).
`dnctl`/`pfctl` dummynet is the cheaper approximation, at the cost of scoping
precision.

**Network request monitoring.** Injecting a dylib into the app at launch via an
`~/.lldbinit` hook that Xcode's debugger sources, then intercepting URLSession
from inside the process. Requires no changes to the user's app, at the cost of
writing to a file in their home directory and shipping executable code into
their debug sessions — hence the opt-in treatment in phase 5a.
