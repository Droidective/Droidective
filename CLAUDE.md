# CLAUDE.md — Droidective

Native macOS app for Android/React-Native debugging over adb. A Raycast-style
command palette: searchable feature sidebar, persistent device bar, a detail
pane per feature. Swift 6 + SwiftUI, macOS 14+.

## Architecture (the load-bearing rule)

Two layers, strictly separated so a second **Apple** UI (iPad/visionOS) could
reuse ADBKit almost as-is. The Windows/Linux port is now scheduled and staged
(strategy + phases in `docs/cross-platform.md`): ADBKit compiles and runs its
whole suite on Linux (CI `test-linux`; `make test-linux` locally) and on
Windows (CI `build-windows`). The Apple-bound subsystems — the Mirror media
stack, the Network.framework servers (Reactotron, the JS-console test fake),
`NSDataDetector`, `proc_pid_rusage` — are `#if canImport`-gated out rather than
stubbed; the portable seams (`HostArchive` extraction, `FileHandleLines`,
per-OS `ToolLocator`, swift-crypto digests off-Apple) carry everything else.
Phase 2 landed `droidectived/`, a local daemon over ADBKit
(`docs/droidectived-protocol.md`); phase 3 is `desktop/`, the Tauri 2 + React
UI over it for Windows/Linux (`desktop/README.md`; the feature-by-feature
parity tracker is `docs/desktop-parity.md`). **macOS never talks to the
daemon** — the Mac app keeps linking ADBKit directly, by decision, so no daemon
or desktop work can reach the shipping Mac flow.

**The desktop UI is the Mac's UI.** The Mac app is the proven one; the point of
the port is that someone moving between the two does not have to relearn
anything. So where a control exists on both, it looks and behaves the way
`App/Sources/` makes it behave — same wording, same icon, same confirmation
shape, same gesture (a double-click to open stays a double-click; a
`confirmationDialog` stays a dialog and does not become an armed button). A
nicer idea for Windows and Linux is still a difference someone has to relearn:
if it is genuinely better it goes into the Mac app *first*, and the port
follows. Two standing exceptions, and they are named where they occur: a
keyboard shortcut whose modifier has no Windows/Linux equivalent (⌘\ became
Ctrl+\, and the split is Ctrl+\ not Ctrl+D because Ctrl+D is end-of-input in
every Linux shell), and a label that names a platform. **Every** feature is in
scope, chrome included — Settings, the notification panel, toasts, the role
picker, the catalog, the menu bar, drag and drop. Only `ios-logs` and
`push-notification` are out, and only because `xcrun simctl` is a macOS
toolchain rather than anything about a device. An iOS companion can't run
`Process` at all, so it would ride the same daemon protocol. Keep the seams (`ProcessRunning`, injected
directories) intact, and keep new ADBKit code portable — no new Apple-only
framework use outside the gated subsystems. The rule is **enforced, not just
documented**: `PortabilityGuardTests` scans ADBKit and fails on an Apple-only
import or a corelibs trap that isn't inside a matching `#if canImport(...)`
gate. Its allowlist is empty, and a companion test fails on a stale entry.

- **`ADBKit/`** — a SwiftPM package holding *all* logic. Zero UI imports
  (feature icons are SF Symbol *name strings*). Actors for stateful services,
  `Sendable` value types, strict concurrency complete. Test with
  `cd ADBKit && swift test` — no Xcode, no device needed.
- **`App/`** — thin SwiftUI shell, split in two `@Observable @MainActor` halves:
  **`AppCore`** is the app (one `adb devices` poll, tool caches, the persisted
  feature curation, the Reactotron/MCP listeners, the window registry), and
  **`AppState`** is *one window's workspace* (device, tabs, terminals, JS
  console). The app is multi-window — one window per device — and `AppState`
  forwards everything app-wide, so a feature view reads `state.devices` /
  `state.layout` without knowing which window it's in. See the multi-window
  convention below and `docs/multi-window.md`. Built via XcodeGen
  (`project.yml`) + xcodebuild; `.xcodeproj` is gitignored and regenerated.

When adding a feature: logic + a parser test go in ADBKit; the view goes in
`App/Sources/FeatureDetail/Views/`. Never put adb/Process logic in a SwiftUI view.
Follow the **Adding a feature** checklist below — a feature's `id` is a contract
spread across several files, and most omissions fail *silently* (a "Coming Soon"
screen), not loudly.

## Adding a feature — the checklist

A feature's string `id` is the contract across several files. Do these in order.
**[test]** steps fail `swift test` — or the AppTests bundle, which CI runs —
if skipped; **[silent]** steps have *no*
automated guard, so the failure mode is a non-working feature you only catch by
opening it — verify those by hand.

1. **Define it** — add a `FeatureDef` to `FeatureRegistry.all` (unique `id`,
   title, keywords, category, `kind`; set `platforms` if it works on iOS
   Simulators — the default is Android-only). **[test: `hasAll60Features` —
   bump the count; `byID` traps on a duplicate id]**
2. **If it's an action** (`.instantAction`/`.formAction`/`.toggleAction`):
   - add the runner `case` to `FeatureEngine.dispatch`,
   - add the `id` to `FeatureEngine.implementedIDs`,
   - add an arg-vector test in `FeatureEngineTests` asserting the exact adb
     arguments (and the quoted form of any user value). **[test:
     `everyImplementedActionResolvesToARunner` catches a missing dispatch case;
     `implementedIDsAreAllRealFeatures` catches a typo'd id; your arg-vector test
     catches wrong/omitted-quote arguments]**
3. **If it's a view** (`.view`/`.system`):
   - build the SwiftUI view in `App/Sources/FeatureDetail/Views/`,
   - add the `id` as a `FeatureDetailRoute` case and its view `case` to
     `FeatureDetailView.pane` (the switch is exhaustive over the enum, so a
     route with no view is a build error),
   - add the `id` to `implementedIDs`,
   - if it runs adb directly, wrap each user action in
     `CommandLog.userInitiated`,
   - fill backgrounds with the theme tokens (`.bgRoot`/`.bgSurface`) or the
     translucency modifiers — an opaque full-pane fill (raw asset Color,
     `Color.black`, default `List`/`Form` material) blocks the window-glass
     appearance (see the translucency convention). **[test:
     `implementedIDsAreAllRealFeatures` for the id; `FeatureDetailRouteTests`
     (AppTests) catches a missing route — it would render "Coming Soon" — and a
     route left pointing at a renamed id] · [silent: missing `userInitiated`
     keeps its commands out of Settings ▸ Command Log; an opaque fill only
     shows up by eye with opacity < 100%]**
4. **If it joins a hub** — add it to `FeatureRegistry.absorbedByHub` and fold its
   keywords into the hub's `keywords`. **[test: `hubsStaySearchableByTheirMembersPrimaryKeyword`]**
5. **Logic lives in ADBKit.** adb/Process/parsing go in an ADBKit service with a
   pure, static, tested parser — never `Process`/`adb` in a SwiftUI view.
   **[silent — but a review red flag]**
6. **Verify** — `cd ADBKit && swift test` green, then `make build` with zero
   warnings (warnings are errors).

## Build / test / run

```
make test          # ADBKit unit tests (cd ADBKit && swift test) — 1751 tests, keep green
make test-app      # the AppTests logic bundle — 99 tests
make verify        # tiers 0-1: warnings-as-errors + both test bundles
make test-linux    # the same suite on Linux (Apple `container` CLI; the port gate)
make test-emulator # tier 3: the device-dependent suites against a real emulator
make test-smoke    # tier 4a: launch the built app and confirm it comes up
make test-mutation # tier 6: break real code, assert the suite catches it
make build         # xcodegen generate + xcodebuild Debug
make run           # build + open the .app
make desktop-test  # the Windows/Linux app: typecheck, oxlint, vitest, clippy, cargo test
make desktop-dev   # build the daemon sidecar, then run the Tauri app
```

The agent loop I use: edit → `cd ADBKit && swift test` → `xcodegen generate` →
`xcodebuild ... build` → relaunch the .app → screenshot to verify. Build output
lands at `DerivedData/Build/Products/Debug/Droidective.app`.

`brew install xcodegen` if missing. App is ad-hoc signed, sandbox OFF (it must
spawn adb/scrcpy/emulator).

## Marketing site

`website/` is a React 19 + Vite 6 + Tailwind v4 app (shadcn/ui + react-bits
components) that renders the landing page; `site/` holds the static
passthrough — CNAME, `appcast.xml` (the release pipeline commits to it; don't
move it), sitemap, `analytics.js`, the SEO subpages, and all screenshots.
Vite's `publicDir` points at `site/`, so `npm run build` in `website/` emits
the complete deployable Pages site into `website/dist`; CI's `pages` job builds
it and injects the PostHog key into `analytics.js`. `make site-dev` /
`make site-build` wrap it. Landing-page copy lives in
`website/src/lib/content.ts`; sections are `website/src/components/site/*`.
Node 22 in CI; scroll reveals and the hero palette demo must keep their
`prefers-reduced-motion` fallbacks.

## Key types (ADBKit)

- `Exec/`: `ProcessRunning` protocol → `SystemProcessRunner` (real) +
  `MockProcessRunner` (tests). `ToolLocator` (actor) resolves adb/scrcpy/
  ffmpeg/emulator via SDK paths → the standard install prefixes → `zsh -lc`
  fallback, cached.
  `AdbClient` (structured `AdbResult`, never throws on non-zero exit, only on
  `.adbNotFound`). `SimctlClient` (AdbClient's `xcrun simctl` twin for iOS
  Simulators — same `AdbResult` shape, throws only on missing Xcode).
  `CommandLog` (actor; records only inside
  `CommandLog.$isUserInitiated.withValue(true)` — wrap view actions in
  `CommandLog.userInitiated {}`, keep background polling out — feeding the
  Settings ▸ Command Log sheet).
- `Devices/`: `DeviceMonitor` (actor, 2s poll, `AsyncStream<[Device]>`),
  `DeviceListParser`, `SimulatorMonitor`/`SimulatorListParser` (the simctl
  twins — booted iOS Simulators surface as `Device`s with
  `platform: .iosSimulator`, merged into the bar in `AppState`), `DeviceProps` (getprop), `DeviceOverview` (RAM/storage/
  battery/CPU/app counts), `DeviceDetails` (picker enrichment).
- `Features/`: `FeatureRegistry` (60 `FeatureDef`s, declarative; `absorbedByHub`
  maps a hub screen to the features it gathers, flattened to
  `absorbedFeatureIDs`; `catalogFeatureIDs` is the registry minus those),
  `FeatureModel`,
  `FeatureEngine` (runner dispatch +
  `implementedIDs` + every sub-service), `SidebarOrdering`
  (pure `reorder`/`move`/`moveToEnd` helpers for the sidebar, unit-tested
  without UI), `WorkspaceRegistry` (the multi-window model: `WorkspaceID`,
  which window owns which device, `exclusiveFeatureIDs` + the conflict
  queries behind the Focus / Take Over banner, and the window tint slot —
  nil for the first window, which keeps the app accent), `WindowEffects` (pure math for the translucent-window
  appearance — opacity clamp/range, `cardAlpha`, blur radius, grain strength;
  the App-layer plumbing is `App/Sources/Root/WindowTranslucency.swift` +
  the dynamic `.bgRoot`/`.bgSurface` tokens in `Theme.swift` — see the
  translucency convention below). The grouped sidebar uses **custom `.onDrag`/`.onDrop`** (not
  `List.onMove`, which raced the row tap gestures and dropped intermittently):
  a feature drag reorders within its group, a header drag moves the whole group,
  and `SidebarDrop` draws the insertion guideline between rows for features and
  only at group boundaries for groups. Persisted as
  `LayoutState.sidebarOrder`/`categoryOrder`/`collapsedCategories`.
- `Services/`: one per domain — TextInput, AppControl, AppInspection (perms/
  info/meminfo/sandbox), AppsExplorer, FileExplorer, Overrides, ScreenCapture,
  ScreenRecorder (records through a headless `MirrorSession` on the bundled
  scrcpy server — no desktop scrcpy; it also owns the microphone's
  per-segment lifecycle — see the recording-audio convention),
  Crash, BugReport, Connection (wireless),
  CustomCommand (one free-typed line; a leading `adb` token infers the adb
  kind → tokenized argv, never a shell; anything else — multi-line included —
  runs through `zsh -lc`, deliberately not device-scoped — `{serial}` targets
  the selection; a `runsInTerminal` command opens the in-app Terminal or the
  Mac's default terminal app via a temp `.command` script per its stored
  `terminal`), ToolDetection, AdbKeyboardInstaller, Emulator, Simulator (simctl:
  boot/shutdown, openurl, appearance, status_bar, screenshot, APNS push —
  backs the cross-platform runners and the Emulators screen's simulator
  section), AppIcon,
  Performance (per-core CPU/RAM/FPS/per-process), NetworkSpeed (`/proc/net/dev`
  throughput), VideoEditService (ffmpeg export). The **`AppBundle/`** quartet
  backs installing every Android package format (`install-app`, the drop zones,
  and the Finder-opened `apk-open` tab): `AppPackageFormat` (the one list of
  installable extensions — apk/apks/xapk/apkm — that every drop filter and open
  panel derives from), `SplitApkSelector` (pure: `DeviceSpec.parse` off getprop
  + which splits of a bundle belong on *this* device — one ABI, the nearest
  density bucket, its languages, every base/feature module), `AppBundleManifest`
  (lenient parsers for APKPure's `manifest.json` and APKMirror's `info.json`,
  with archive paths sanitised against `../` traversal — an untrusted
  `install_path` is concatenated onto a device path), and
  `AppBundleInstallService` (the orchestrator: a plain `.apk` goes straight to
  `AppInstallService`; `.apks` goes back to bundletool's `install-apks`, which
  reads the archive's own `toc.pb` targeting table — so it needs Java, and says
  so; `.xapk`/`.apkm` unpack to a temp dir, narrow to the device's splits, and
  land in one `adb install-multiple -r` transaction, then push any OBB
  expansions). The **`JSConsole/`** trio backs
  the `js-console` feature — a Hermes Chrome-DevTools-Protocol JS console for RN:
  `MetroInspector` (host-localhost `GET /json/list` + a pure `parseTargets`),
  `CDPProtocol` (pure CDP framing + `Runtime.evaluate`/`getProperties`/
  `consoleAPICalled` decoders), and `JSConsoleClient` (an actor over
  `URLSessionWebSocketTask` — id↔continuation correlation, a CDP keepalive
  that survives the proxy's ping/terminate heartbeat, takeover-aware closes,
  reconnect-friendly event stream; `ConsoleReplayGate` drops the re-replayed
  console history on reconnects). No adb path (Metro runs on the Mac); the
  device only needs `adb reverse tcp:<metroPort>` to reach the dev server.
  The **`ApiClient/`** group backs `api-client` (API Testing) — a device-free
  HTTP client: `ApiModels` (methods, six body kinds, five auth kinds,
  collections/folders/environments), `HttpRequestBuilder` +
  `HttpTransport`/`HttpClientService` (the `ProcessRunning`-style injectable
  seam is the transport protocol, so every send is testable without a
  network), `CurlParser` (flag-table driven — a value-taking flag must never
  be mistaken for the URL), `PostmanFormat` (import/export), `ApiVariables`
  (`{{var}}` resolution, unresolved ones surfaced not sent),
  `ApiAssertions`, `ApiRunner`, and `CodeGenerator` (six targets). Header
  names/values are validated (CRLF header injection through a variable is
  the boundary here, the way `shellQuote` is for adb) and query values are
  percent-encoded against RFC 3986 unreserved.
  `ScreenTools` holds the
  `ScreenRecordOptions` struct and `RecordAudioMode`/`RecordAudioOptions`. **Bundled binaries** (scrcpy-server, a static
  GPLv3 ffmpeg, and the Apache-2.0 bundletool + uber-apk-signer jars — the
  jars are factory-seeded into the managed-tool store at launch so
  Settings ▸ Tools can upgrade them) live in `App/Resources/`, resolved by the
  App-layer `BundledTools` (single version source);
  `scripts/update-bundled-tools.sh` refreshes them. The
  app needs no separate scrcpy/ffmpeg install; the Doctor only checks adb /
  emulator (pointing at the install source when one is missing — the app
  never installs tools itself).
- `Persistence/`: `JSONStore<T>` (actor, atomic write, sets aside corrupt
  files as `.corrupt`), `Stores` (Bundles, DeepLinks, CustomCommands,
  LayoutState, Presets, OverridesMap, Prefs) in
  `~/Library/Application Support/Droidective/`. `LayoutState.windows`
  (`[WindowState]`) is the per-window half — device, bundle, tabs, focused
  pane, terminal-resume dirs, one entry per workspace window, restored in
  order; `adoptWindows` folds a pre-multi-window layout's single workspace
  into one entry and clears the legacy fields. Everything else on
  `LayoutState` (enabled set, order, favorites, role) is shared by every
  window.
- `Tools/` + APK services: `ManagedTool`/`ManagedToolStore` (actor) download jadx,
  apktool, uber-apk-signer, frida-server/-gadget, and a Temurin JRE from their
  GitHub releases into `Application Support/tools`, verify the asset digest,
  extract (zip/tar.gz/`.xz` via the Compression framework), version-track, and
  upgrade in place. `ApkToolchain` resolves SDK build-tools (aapt2/apksigner/
  zipalign — detected, not downloaded) + the managed tools + `java` (a system JDK
  first, else the managed Temurin). The APK features are services over the
  toolchain with arg-vector tests: `ApkInspectionService` (aapt2 badging +
  apksigner certs), `ApkSigningService` (zipalign + apksigner; keystore password
  via a 0600 temp file, never argv), `DecompileService` (jadx + apktool + a
  `FileNode` tree + `rebuild` via `apktool b`), `FridaService` (ABI→arch match +
  frida-server push/run). Downloads are point-of-use (a gate in the decompile/
  Frida views) or from Settings ▸ Tools. **APK Studio** (`apk-studio`) is a hub
  that folds the three standalone APK tools (`apk-inspector`, `apk-decompile`,
  `apk-sign`) into one workspace over a single loaded APK — Inspect · Decompile ·
  Recompile · Sign tabs (the views take an optional injected APK so they embed in
  the studio and still work standalone via hotkey).
- **`ReactotronMCP/`** — a *separate SwiftPM package* beside ADBKit (which it
  depends on by path; ADBKit's own graph stays free of swift-sdk and swift-nio,
  which is what lets `swift test` run on Windows) serving the
  Reactotron relay's data to AI agents over localhost Streamable HTTP —
  the same contract as the official Reactotron desktop's embedded MCP
  server (`claude mcp add --transport http reactotron
  http://127.0.0.1:4567/mcp`). Deps: `modelcontextprotocol/swift-sdk`
  (pinned exact) + swift-nio (listener only). Strictly downstream of the
  relay: it consumes an additive `ReactotronServer.tap()` (the UI stream is
  untouched) into `McpCommandStore` (actor; its own 500-item + 32 MiB ring
  buffer, independent of the UI timeline; event-driven `awaitCommand`
  correlation with afterMessageId markers — no polling), and its failure
  can never take the relay down. `McpToolRegistry` (declarative 10-tool
  table, FeatureRegistry-style, with invariant + golden-signature tests) →
  `McpToolHandlers`; `McpResources` (8 URIs incl. the `timeline/{type}`
  template); `McpRedaction` (default-ON at the MCP boundary only — the
  Reactotron UI is never redacted — with upstream's two-key opt-out:
  client `mcpRedaction` in `client.intro`, server permissions in
  Settings ▸ MCP); `McpHTTPListener` (NIO port of the SDK's conformance
  HTTPApp: per-session `Server`+`StatefulHTTPServerTransport` — one
  initialize per Server, SDK #144 — idle reaper, 127.0.0.1-only,
  `OriginValidator.localhost()`, optional static bearer token; never use
  the SDK's Stateless transport — concurrency bugs #254/#255);
  `McpServerController` (the facade the App layer calls). App side:
  `McpCoordinator` (@MainActor, owned by AppState) + Settings ▸ MCP —
  off by default; enabling starts the relay and keeps it alive across
  tab/window close; it never restarts a relay the user stopped (status
  goes amber, ghost clients cleared via `noteRelayStopped`).

## The 60 features

Most `.view` features are full-screen bespoke panels (file-explorer, apps,
emulators, device-info, logcat, ios-logs — the simulator unified-log twin (`SimulatorLogStreamer` over `simctl spawn <udid> log stream --style ndjson`, iOS-only, standalone), crash-catcher, sandbox-browser, performance,
network-speed, wifi, root-status, screen-record, scrcpy, reactotron, js-console,
terminal — multi-tab PTY login shells via SwiftTerm, with the device selected at
open exported as ANDROID_SERIAL; tabs split into panes (⌘D/⇧⌘D — the pure
`TerminalSplitTree` model, tested in ADBKit; ⌘W peels a pane, then the tab), a
new shell inherits the focused shell's cwd (read from the kernel via
`proc_pidinfo`, no OSC 7 needed), an *implicit* teardown (quit, the feature
tab closing, a background window close) snapshots each tab's cwd so the next
open resumes there (`TerminalResume` in ADBKit + `LayoutState.terminalResumeDirs`;
explicitly closed tabs — ⌘W/×/`exit` — are forgotten by construction), and
the tab list toggles between the left
rail and a Chrome-style top strip (`terminalTabsOnTop`) — + the
custom-commands/catalog system panels). Several are **hub** screens — `react-native`, `simulate`,
and `connection` gather related instant-/form-/toggle-actions into one scrollable
grouped `Form`; `apk-studio` is a tabbed workspace over one loaded APK (Inspect/
Decompile/Recompile/Sign). (The Apps explorer similarly covers per-app
management — its detail pane carries the old "Manage App" controls: open,
force-stop, clear cache/data, plus disable/uninstall). A hub's gathered features
(`FeatureRegistry.absorbedByHub` → `absorbedFeatureIDs`) are managed only from
the hub: the display layer filters `FeatureDef.isAbsorbedByHub` out of the
catalog, the sidebar (`AppState.enabledFeatures`), and search
(`disabledMatches` + the ⌘K palette), so they never appear as standalone rows or
"disabled" search hits. Discoverability is preserved by folding each member's
keywords into its hub (a test enforces the hub matches each member's primary
keyword), so searching e.g. "battery" or "force stop" surfaces the Simulate /
Apps hub. They stay hotkey-able (every feature registers a shortcut; the Hotkeys
tab lists bound members under "Hidden features"). This is a pure display filter —
no persisted migration — so it also covers a hub that grows later. The rest are generic instant-/form-/toggle-actions
driven by the registry. The catalog and Home's "All N features" count use
`catalogFeatureIDs` (38). **Every feature is enabled by default**
(`defaultEnabledIDs == catalogFeatureIDs`); the catalog (Manage features) is for
turning OFF the ones you don't want, not opting in — there's no Restore button.
`LayoutState.adoptAllEnabled()` is a one-time migration that turns everything on
for existing layouts; `adoptNewDefaults()` still auto-enables a newly-shipped
feature for existing users via `knownIds`. **Platforms:** `FeatureDef.platforms`
says which toolchain a feature works against (default Android-only). Booted iOS
Simulators sit in the same device bar; cross-platform ids (screenshot,
dark-mode, demo-mode, fake-battery, deep-link) dispatch to simctl runners via
`FeatureEngine.dispatchIOS`, `push-notification` is iOS-only (absorbed by the
Simulate hub, which adapts its sections per platform; iOS-only *actions* must
be hub members — `iosOnlyActionsAreHubMembers` — while iOS-only *views* like
`ios-logs` may stand alone), and everything else
shows a "works with Android devices" state with a switch-device button when a
simulator is selected. New cross-platform features add a `dispatchIOS` case +
an arg-vector test; `everyIOSCapableActionResolvesToASimctlRunner` catches a
platforms annotation without a runner.

## Reactotron MCP — syncing with upstream

The MCP surface mirrors `infinitered/reactotron`'s `lib/reactotron-mcp` at
the commit pinned in `scripts/reactotron-upstream.lock`. When Reactotron
changes (new tools, new command types, new redaction rules), the upgrade is
mechanical — follow this recipe:

1. **Detect**: `./scripts/check-reactotron-upstream.sh` (run before releases).
   It diffs the contract-defining upstream files against the pinned commit and
   checks the `reactotron-mcp` npm version. "✓ in sync" means stop here.
2. **Locate**: the target layout mirrors upstream file-for-file, so the
   script's diff tells you exactly which Swift file to touch —
   `tools.ts` → `McpToolRegistry.swift` + `McpToolHandlers.swift`;
   `resources.ts` → `McpResources.swift`; `redaction.ts` →
   `McpRedaction.swift` (rule lists ported verbatim); `serialization.ts` →
   `McpSerialization.swift` + `McpConstants.swift` (caps keep upstream's
   names: `BUFFER_SIZE`→`bufferSize`, `MAX_RESPONSE_CHARS`→
   `maxResponseChars`, …); `mcp-server.ts` → `McpHTTPListener.swift` +
   `McpCommandStore.swift`; `reactotron-core-contract/command.ts` →
   ADBKit's `ReactotronProtocol.swift`.
3. **Port**: a new *tool* is one `McpToolDef` table entry + one handler case
   + a contract test (the invariant tests fail on a missing handler or a
   schema that doesn't decode). A new *resource* is a `staticResources`
   entry + a `read` case. A new *wire command type* needs **zero** MCP code
   for visibility — raw commands flow into `reactotron://timeline` and
   `timeline/{type}` automatically (the type list is derived from the
   buffer) — add the `ReactotronCommandType` case + parser case + test only
   for typed conveniences.
4. **Re-pin**: update `McpGoldenContractTests`' golden signature (the test
   failure prints the actual — the diff IS the contract change, reviewable
   in the PR), bump `scripts/reactotron-upstream.lock`, `swift test`.
5. **SDK bumps** (`modelcontextprotocol/swift-sdk` is pinned exact in
   `ADBKit/Package.swift`): treat as a deliberate change — bump, re-run the
   `McpHTTPListenerTests` socket suite, and re-check the two known traps:
   per-session `Server` instances (#144) and never the Stateless transport
   (#254/#255).
6. The npm `reactotron-mcp` package is a *different* surface (a standalone
   stdio proxy on port 9091, `get_*`-style tools + 5 prompts) — not what we
   mirror, but new capabilities there are candidates to adopt as extensions.

The full design analysis (upstream ground truth, decisions, failure-mode
table) is in `docs/reactotron-mcp-analysis.md`.

## Conventions / gotchas learned the hard way

- **Multi-window: a workspace becomes real only when an `NSWindow` binds to
  it.** One window per device; `AppCore` owns the workspaces, `AppState` is
  one of them. Rules for new code:
  - **App-wide state goes on `AppCore`, per-window state on `AppState`**, with
    a forwarding property so views keep reading `state.…`. Getting this wrong
    is silent: a per-window concept written to the shared `layout` (the
    terminal-resume directories did exactly this) gets clobbered by the other
    window.
  - **Never trust SwiftUI's presented `WorkspaceID` as window identity.**
    `WindowGroup(for:)` persists presented values across launches, re-presents
    stale ones *into an existing window*, and asks for content for windows it
    never shows — and a *closing* window re-renders too. So
    `workspace(claiming:)` hands back a **provisional** workspace that owns
    nothing (no registry entry, no restore, no write), and `AppCore.bind`
    promotes it, or has the window adopt one that's waiting for a window
    (launch restore, or a workspace parked by a background-mode close).
    `bind` also enforces one-NSWindow-one-workspace and refuses a closing one.
    AppKit's own restoration is off (`window.isRestorable = false`) —
    Droidective restores from `LayoutState.windows` and two restorers fight.
  - **App-wide singletons must track *every* window.** `WindowMinSizeGuard`
    and `ResizeActivity` used to re-point at the newest window on each attach,
    which silently dropped the size floor and the resize-freeze for the
    others. Observe with `object: nil` and keep a set.
  - **Anything "the app" does needs a window**: menu bar, global hotkeys,
    Finder opens and update toasts route through `AppCore.frontmost` (the last
    key window). Poll-rate activation comes from `NSApplication`, never a
    per-window `scenePhase` — those fire independently and fight.
  - **A left-aligned window title in a dev build is the SDK, not a bug.**
    macOS 26 moves titles beside the traffic lights for apps linked against
    the macOS 26 SDK; Xcode 26 links local builds that way, CI's `macos-15`
    runner doesn't, so shipped builds stay centered (`otool -l`: v3.8 release
    = `sdk 15.5`, local debug = `sdk 26.2`). Don't chase it in app code —
    `.navigationTitle` adds a *second* leading item, a toolbar principal item
    gets macOS 26's glass capsule (removable only via the macOS 26-only
    `sharedBackgroundVisibility`), and titlebar content via
    `.fullSizeContentView` or `NSTitlebarAccessoryViewController` is collapsed
    or clipped. All four were tried.
  - **Only the windows after the first tint their device icon**
    (`DeviceTint`); the app keeps one accent.
  - **A feature that can't run twice on one device** goes in
    `WorkspaceRegistry.exclusiveFeatureIDs` (scrcpy/screen-record share the
    encoder, `js-console` loses the CDP target to the newest client,
    `frida-console` owns a port). It then gets the Focus / Take Over banner
    instead of racing. A test asserts every id there is a real feature.

- **Process runner must never block a cooperative thread.** `SystemProcessRunner`
  uses `terminationHandler` + `readabilityHandler`, not `waitUntilExit`. A
  blocking design starved the async pool and froze the whole app. There's a
  16-concurrent-process canary test guarding this — don't regress it.
- **`"\r\n"` is ONE Swift Character.** Splitting adb/emu console output on
  `"\n"` silently fails on CRLF. Use `.components(separatedBy: .newlines)`.
- **Device-side shell quoting is the security boundary.** Anything going through
  `adb shell` is joined with spaces and run by the device's `sh`, so EVERY
  user-controlled value (path, URL, SSID, hostname, proxy, locale, free text)
  must be wrapped with `shellQuote()` — never rely on caller-side validation to
  reject metacharacters (an engine `host:port` check is UX, not security).
  `adb push`/`pull`/`exec-out` use the sync protocol — no shell, no quoting.
  There's no linter for this; a missing `shellQuote` is command injection, so
  add an arg-vector test asserting the quoted form (see `OverridesServiceTests`).
- **Cancellation kills the child.** `SystemProcessRunner.run` wraps its body in
  `withTaskCancellationHandler`, so cancelling the calling `.task` (navigation, a
  `.task(id:)` re-key) terminates the adb child instead of orphaning it until its
  timeout. Keep long-running adb work in a cancellable `Task` so this fires.
- **Pull progress** is the destination file's on-disk size polled against the
  known source size (real %). Screenshots/recordings/dir pulls stay
  indeterminate (no reliable total). The progress strip lives in RootView's
  safe-area inset, not inside DeviceBarView.
- **`.task(id:)` keys must include readiness** (`targetSerials.first`), not just
  serial — a device authorizing keeps the same serial and the view must reload.
  Guard `!Task.isCancelled` before writing fetched results into @State.
- **Drops route by geometry, not type — and drags need declared UTIs.** SwiftUI
  hands a drop to the *deepest* drop region under the cursor even when that
  target's `onDrop(of:)` types don't match the drag (no fallthrough to
  ancestors), and hidden keep-alive tabs (`opacity(0)` +
  `allowsHitTesting(false)`) still register their drop regions — so a
  whole-view `.onDrop` inside a feature silently kills the pane's tab drops
  whenever that tab is merely open (this broke drop-to-split from v2.8.1 until
  the Terminal's catch-all was removed). Never attach a feature-wide `.onDrop`;
  scope targets tightly and let `RootView.installDragJanitor` clear abandoned
  drag state (normal mouse events don't flow during a drag session, so the
  first one that arrives with drag state set means the drag ended dropless).
  In-app drags ride private UTIs (`DragTypes.swift`) that must be declared in
  `UTExportedTypeDeclarations` (project.yml) — macOS won't put an undeclared
  UTI on the drag pasteboard, which kills the drag *silently*.
- **Empty states under a toolbar must `.frame(maxWidth/maxHeight: .infinity)`** —
  otherwise the whole VStack centers and the toolbar floats mid-window.
- **`scrollPosition(id:)` read-back can't drive a follow/freeze decision under
  streaming load** — it fires late and points at stale rows for the view's own
  programmatic pins, so "did the user scroll up?" inferred from it flickers.
  `SimulatorLogsView` freezes on the real gesture instead (a local
  `.scrollWheel` NSEvent monitor) and uses the read-back only to detect the
  user returning to the tail.
- **`HSplitView` ignores SwiftUI safe-area insets** (it's NSSplitView-backed) —
  content renders under the device bar. Use a plain HStack split.
- **The Command Log records only wrapped calls.** A view-feature that runs adb
  directly (logcat, device-info, file-explorer…) must wrap its user-initiated
  calls in `CommandLog.userInitiated {}` or they never reach the Settings ▸
  Command Log sheet. Keep background polling OUT (don't wrap it).
- **Window translucency is token-driven — never paint an opaque full-pane
  fill.** Settings ▸ Appearance ▸ Window has Opacity (10–100%) / Blur / Grain
  sliders. `.bgRoot` / `.bgSurface` are *environment-resolving ShapeStyles*
  (Theme.swift), not Colors: they derive alpha from `\.windowOpacity`
  (injected by RootView; the math is `WindowEffects` in ADBKit, unit-tested,
  1.0 ⇒ exactly the old opaque rendering). Rules for new UI: fill with the
  tokens (a raw `Color("BgRoot")` or `Color.black` full-pane fill blocks the
  glass); `List`s / grouped `Form`s get `.translucentListBackground()`; feeds
  sitting on the system `.background` material get
  `.translucentFeedBackground()`; cards add NO extra washes — they stack on
  the one root wash (RootView paints it under the whole window) at
  `WindowEffects.cardAlpha`, the contrast-step alpha that avoids compounding
  to solid. Terminal gotcha: SwiftTerm paints its background twice (whole
  frame + per default-bg run), so any partial alpha compounds — under glass
  the shell paints alpha-0 (`DroidTerminalView.applyBackgroundAlpha`) and the
  pane underlay carries the single tint. Blur is the window server's
  `CGSSetWindowBackgroundBlurRadius` (dlsym'd, no public radius API; no-op if
  the symbol vanishes); grain is a Metal `colorEffect` (`Grain.metal`)
  overlaid OUTSIDE the ⌘= zoom scale so zoom never magnifies specks.
  `\.windowOpacity` is declared in Theme.swift because the AppTests logic
  bundle compiles that file standalone (and links ADBKit for it). JS Console
  keeps its Chrome-dark hue at the card step; CodeMirror webviews stay opaque.
- **Recording audio is one AAC track fed by up to two sources.** A recording
  captures the device's audio, the Mac's microphone, both, or neither —
  `RecordAudioOptions`/`DeviceAudioSource` in ScreenTools, persisted by the
  App-layer `RecordAudioPreference` (`recDeviceAudio`/`recHostMic`/
  `recMicInput`, with migrations from the superseded `recCaptureAudio` and
  `recAudioMode`). The device side is **playback *or* its own microphone, never
  both**: scrcpy carries one device stream per session
  (`ScrcpyServerParams.audioSource` → `audio_source=mic`), so the two
  checkboxes are mutually exclusive and say so in a line of text rather than
  silently ignoring one. The same three controls — Device audio, Device
  microphone, Mac microphone (Off / System default / a named input) — appear on
  the Screen Record screen inline and in the mirror's `RecordAudioSheet`, which
  the chevron beside the mirror's record button opens: set the combination,
  hear the mic on the level meter, and Start Recording from the sheet. Mid-take
  the mirror bar shows a mute menu and the Screen Record screen its two mute
  chips.
  - **Two Picker traps live here.** A `Divider()` inside a `Picker` breaks tag
    matching and SwiftUI then *writes back* a coerced selection — that silently
    switched the microphone on at launch. And Core Audio's scratch devices
    (`CADefaultDeviceAggregate-…`, tap aggregates) show up in
    `AVCaptureDevice.DiscoverySession` and must be filtered out
    (`RecordAudioInputs.isSelectable`) or they appear as pickable "microphones".
  Both sources land in **one** track, never two: players (QuickTime, browsers,
  chat apps) play only the first audio track, so a second one is silently lost
  for whoever the clip is sent to. With one source the samples go straight to
  the writer exactly as before; with two they meet in `PCMMixdown` (pure,
  portable, tested) on a shared timeline, because the device stamps its audio
  in the device clock and the mic in the host clock — `AudioTimeline` anchors
  the two at the frame the file opens on, or narration drifts over a long take.
  Mute writes *silence* rather than dropping samples, so the track keeps one
  continuous timeline and unmuting is instant. `MicrophoneCapture` (Apple-gated, its own file) requests access
  itself when the status is undetermined — recordings start from several places
  and only one has a picker — and a mic that won't start is surfaced through
  `ScreenRecorder.audioStatus()` while the recording keeps going: losing the
  narration beats losing the take.
- **Sparkle never starts in Debug builds** (`SparkleUpdater.updaterAllowed`).
  Silent staging + install-on-quit replaces the bundle at the app's own path —
  a dev build sharing the release bundle id gets the RELEASE app installed
  over `DerivedData/…/Droidective.app` the moment it quits. Symptoms of a
  regression: days-old binary mtimes, no `Droidective.debug.dylib` in
  MacOS/, EPERM re-copy build failures. Debug string-probes go against the
  `.debug.dylib`, never the stub executable.
- **RootView's `body` chain sits near the type-checker's time limit on CI's
  Xcode** (local passes, CI fails with "unable to type-check in reasonable
  time"). Add cross-cutting concerns as ONE `.modifier(...)` link (see
  `WindowTranslucencyModifier`), never several inline links.
- **⌘=/⌘- font zoom is a `scaleEffect` on RootView, not dynamic type.** macOS
  ignores SwiftUI `dynamicTypeSize` for rendering, so the content is laid out at
  `size/scale` and scaled up. It's bypassed entirely at 1.0× because the
  transform breaks `.help` tooltips (and `chartXSelection`/hover) underneath it.
- Every pull asks for a save location (`askSaveLocation`/`askSaveFolder`);
  defaults to `~/Downloads/Droidective`.
- **Screenshot is a capture-and-annotate editor.** The Screenshot *view*
  captures into `ScreenshotEditorView` (pen/highlighter/shapes/arrow/text/redact
  + zoom + crop) and writes nothing until you Save/Copy — `captureForEditor`
  returns the PNG bytes (`ScreenCaptureService.captureScreenshotData`), not a
  file. The quick paths (sidebar ⏎, global hotkey, menu bar) call `runScreenshot`,
  which now grabs and saves straight to the capture folder with no dialog.
  Annotations are normalized (0…1) points so the on-screen canvas and the
  full-resolution export share `ScreenshotMarkup.draw`; export/crop flatten via
  `ImageRenderer`. Redact has two styles: solid (drawn in the canvas) and blur
  (a blurred copy of the base image masked to the regions — `RedactBlurLayer`,
  layered under the canvas in both the editor and the export). Undo/redo
  (⌘Z / ⇧⌘Z) is snapshot-based (full image+annotations) and reaches the editor
  via `CommandGroup(replacing: .undoRedo)` + a `focusedSceneValue` — nil'd while
  typing a text label so ⌘Z falls through to the text field.
- **Background mode & the Quick Actions panel.** With Settings ▸ General ▸
  "Keep running in the background" on (the default), closing the main window
  stops the kept-alive sessions (`AppState.enterBackground` — terminal shells,
  Reactotron, JS-console tunnels; view-owned work dies with its view), widens
  both device polls, and drops the Dock icon (`.accessory` — see
  `AppDelegate.windowWillClose`, guarded by `isQuitting` so quit teardown isn't
  mistaken for a window close). The app stays resident for the menu bar, the
  per-feature hotkeys, and `QuickActionsPanel` — a **non-activating**
  `FloatingPanelController` panel (global hotkey in Settings ▸ Hotkeys; the
  welcome tour ends on two Quick Actions pages — record the hotkey (Next gated
  until one is set, ⇧⌘Space recommended), then a try-it finale whose keycap
  animation invites the real press: opening the panel fires the confetti,
  `AppState.noteQuickActionsOpened`, but Skip/Finish/Esc also end the tour,
  `AppState.endTour`) that is
  a small push-navigation mini app. The root is a *grid* of everything
  runnable in place — saved custom commands (pinnable, stored on the
  command), every *enabled* implemented
  instant/toggle/form action minus the panel-hidden set
  (`LayoutState.quickPanelHiddenIds` — a tile's right-click Hide, managed in
  Settings ▸ General ▸ Quick Actions)
  (mirrors the app's role/catalog curation; hub
  members ride their hub's enabledness, pinned features lead — ⌘P toggles,
  shared with the app's favorites; `PaletteSearch.quickActions`, tested),
  Manage Apps / Emulators / Install APK — with an "Open in Droidective" list
  below for the enabled full-app view screens. Form actions render their
  registry `FieldDef`s in-panel (`QuickActionFormView`); app verbs come from
  `AppControlService.AppAction` (destructive ones need a second ⏎). With >1
  device connected, every device-scoped action pushes a pick-device
  interstitial; ⌘⏎ there runs on all devices (offered and applied only for
  `supportsRunAll` features — parity with the main window). Targets
  always ride explicitly through `run(on:)` — never the device-bar
  selection, whose run-on-all state belongs to the hidden window.
  ←→/↑↓ navigate the root grid even while a query is typed. Esc (or the
  header's ‹ button) pops a screen and closes at the root, and a closed panel
  resumes its screen + device choice when reopened within Settings ▸ Quick
  Actions' window (`QuickPanelMemory`, default 5 min). Reopening the app goes
  through `activateMainWindow` (flips the policy back to `.regular`, then
  fronts the window on the next runloop turn; the main window is tracked by
  reference in `AppState.mainWindow` — identifiers don't survive a close).
- UI automation for verification: prefer AX element refs over coordinate
  clicks; the user works on the Mac alongside you (see memory).

## Standards

The bar: every change ships with tests, leaves the build warning-free, and keeps
the ADBKit/App boundary intact. The architecture exists to make bugs *fail at
compile or test time* — lean on it instead of manual vigilance.

### Development

- **Logic in ADBKit, UI in App.** A new capability is an ADBKit service (a small
  `Sendable` struct/actor over `AdbClient`) plus a pure parser; the view only
  renders and calls it. If a view reaches for `Process`/`adb`/parsing, stop —
  move it down. The boundary is what keeps logic testable without a device.
- **Parsers are pure and static.** `static func parseX(_:) -> …` with no I/O, so
  it's tested directly. Split adb output on `.newlines`, never `"\n"` (CRLF).
- **Quote every device-shell value with `shellQuote()`** (see Conventions). It's
  the security boundary, not caller validation.
- **Long-running work goes in a cancellable `Task`**; `.task(id:)` keys include
  device readiness; guard `!Task.isCancelled` before writing `@State`.
- **No new dependency without a reason.** Each is attack surface + maintenance.
- **Replace, don't deprecate.** Delete dead code in the same change; no shims or
  unused fields (a test like `everyImplementedActionResolvesToARunner` is cheaper
  than a stale parallel list).
- **Keep files focused.** `AppState` and the largest views are already big — put
  a new feature's glue in its own type/extension, not the nearest god-object.

### Testing

- **Test behavior, not implementation** — assert observable output and the exact
  adb argument vector (via `MockProcessRunner`), never private state. A
  behavior-preserving refactor must not break tests.
- **Cover edges and errors, not just the happy path** — empty input, CRLF,
  malformed/partial output, non-zero exit, the failure branch. Mock only the
  boundary (`ProcessRunning`, the filesystem via temp dirs), never logic.
- **Every new parser/runner gets a test in the same change.** For anything taking
  user input that hits `adb shell`, assert the `shellQuote`d form appears in
  `runner.invocations`.
- **Registry invariants are tests, not review folklore** — when you add a
  cross-feature rule, add a loop over `FeatureRegistry.all` that enforces it (the
  `everyFeature*` / `*ResolvesToARunner` tests are the pattern to copy).
- Device-dependent checks are `@Test(.enabled(if:))` gated on `MIRROR_LIVE_TEST=1`
  so they skip cleanly in CI.

### Review (in order: architecture → correctness → tests → quality)

- **Architecture:** does ADBKit stay UI-free? Any `Process`/`adb` in a view? Is
  the new logic in a testable service?
- **Correctness:** every device-shell value `shellQuote`d? output split on
  `.newlines`? `.task(id:)` readiness + `!Task.isCancelled` guard present?
  failure paths handled (not optimistic success)?
- **Tests:** parser + arg-vector tests present and meaningful (would they fail if
  the code broke)? edges covered?
- **Quality:** dead code removed, file not bloated, names clear, zero warnings.
- Adversarially verify a finding before acting on it — read the cited code; many
  plausible findings misread it (a refactor that "removes dead code" can delete a
  live path). Sync to `origin` first.

### Bug-prevention gates (already wired — keep them green)

- `swift test -Xswiftc -warnings-as-errors` (CI) and
  `SWIFT_TREAT_WARNINGS_AS_ERRORS` on the App target — warnings are build errors.
- Swift 6 complete strict concurrency (pinned in `Package.swift` and project.yml)
  — data races fail the build.
- The 16-process starvation canary, the feature-dispatch consistency tests, and
  the registry-invariant tests guard the highest-risk seams. Don't regress them.
- **`make verify`** is the tiered gate (`scripts/verify.sh`): tier 0 compiles
  ADBKit warnings-as-errors, tier 1 runs both test bundles. Both bundles are
  swift-testing-only, so `xcodebuild test` reports them through XCTest as
  "Executed 0 tests … TEST SUCCEEDED" — every tier therefore asserts a non-zero
  count from swift-testing's own summary, and `make verify-self` tests those
  assertions. Above that: `make test-emulator` (real device), `make test-smoke`
  (the app actually launches), `make test-mutation` (the suite goes red when code
  breaks), `make test-linux` (the same suite on Linux).
- **Real device output is a fixture, not a guess.** `RecordingProcessRunner`
  captures genuine adb output once (`scripts/emulator-harness.sh --record`) and
  `FixtureProcessRunner` replays it
  with no device, so parsers face real `getprop`/`ls -la`/threadtime `logcat` in
  CI. Redaction runs at record time — IPs, MACs, serials and the host home
  directory are scrubbed and credential-bearing commands are never recorded — so
  regenerate with `--record` and review the JSON diff rather than editing it.

### Git / contributing

- Work on a feature branch; open a PR to `main`. `swift test` green and the build
  warning-free before pushing.
- Commits are imperative-mood, one logical change each. PR descriptions state
  what the diff does in plain, factual language — no "critical/comprehensive".
- Never commit secrets (gitleaks runs pre-commit); telemetry keys are build-time
  injected, never committed.
- **This branch tracks main by rebase** — sync with the `rebase-cross-platform`
  skill: `git rebase origin/main`, resolve the known conflict spots (CLAUDE.md,
  Package.swift, the gated/seam files), audit main's new ADBKit code for
  Apple-only imports and corelibs traps, then `swift test` + `make test-linux`
  green before `git push --force-with-lease`.

## Release channels

Two channels from one `main`, decided by the tag: **`vX.Y.Z` is stable and
macOS-only**; **`vX.Y.Z-beta.N` is beta and additionally carries the Windows
and Linux builds**. A standing arrangement, not a pre-release cycle — the
ports are expected to sit on beta for a long time, and the public macOS
release never ships from a beta tag. The policy, the artifact matrix, the
per-channel version touchpoints, and the staged rollout are in
`docs/release-channels.md`; `scripts/release-channel.sh` is the single
resolver and `scripts/test-release-channel.sh` (in `make verify-self` and CI)
keeps it honest — notably that a stable release can never attach a Windows or
Linux artifact. Notes are picked by tag (`scripts/extract-notes.sh`), not by
position in `RELEASE_NOTES.md`.

## Status

Feature-complete across all planned milestones plus several UX rounds.
(Latest release: **v3.8.2** — JS Console split-pane fixes. A row's height was
grown against a baseline that was still moving, so a wrapped message drew past
the height its row reported; the arithmetic is now `ConsoleRowLayout` in ADBKit,
pure and tested, where a line's baseline settles before anything is positioned
against it. And the pane refused to shrink: `targetPicker`'s `.fixedSize()` made
a long target label the minimum width for the connection bar, and so for the
whole pane, so every row was laid out wider than the pane and cut off by its
clip — which reads as the tab beside it overlapping. Nothing in that bar may
demand more width than the pane it sits in. A `console.table` scrolls inside its
own row rather than sizing the feed, and the source location is an icon in the
row's hover controls beside the copy buttons.) Before that,
**v3.8.1** — the **JS Console rebuilt against Chrome
DevTools**. The value layer is now Chrome's: a top-level `console.log` string
argument prints bare, nested strings single-quote and escape their newlines,
an array leads with `(n)`, a nested plain object is `{…}`, and a collapsed
node inside an expanded value previews its own first properties instead of a
key count (`RemoteObjectDisplay`, `SnapNodeDisplay`, both pure). Four things
the console had no model for: `ConsoleANSI` (React Native's dev-server notices
arrive coloured for a terminal), `ConsoleGrouping` (`console.group` depth and
the id path a collapsed header hides by — `groupEnd` shows no row, which is
where the trailing blank rows came from), `ConsoleTable` (the
`console.table` grid, built from the snapshot the expandable rows already
fetch), and `MetroSymbolicator` (a call's bundle coordinates back to the
developer's file through Metro's `/symbolicate` — lines cross the wire
1-based, and the frame shown is the first the app owns, skipping Metro's
`collapse` flag and `node_modules` the way Chrome ignore-lists them; cached
per stack, coalesced, circuit-broken). The row is `JSConsoleRow.swift`: a
wrapping `ConsoleFlowLayout` puts the whole argument list on one line with
each object an inline disclosure, the source label sits at the right edge and
opens the symbolicated stack, group blocks indent under a rule and fold from
their header, and only errors and warnings get a glyph. Two behaviours worth
keeping: a row's click sits *behind* its content (so the copy buttons, source
link, and nested disclosures always win) and only ever *opens* the first
object — it used to toggle, so clicking a nested leaf folded the whole value;
and copying a log resolves its objects to real JSON, because `{…}` is the one
part of a pasted row nobody can act on.) Before that, **v3.8.0** — **API
Testing** (the 60th feature: `api-client`,
a device-free HTTP client — seven methods, six body kinds, five auth kinds,
Postman collections/environments in and out, nested folders,
`{{variable}}` scopes with unresolved ones flagged pre-send, assertions on
status/timing/body/header/JSON-path, a collection runner, code generation to
six targets, and a cURL paste that parses back; response pane with pretty/raw
body, image preview, cookies, timing breakdown and redirect chain, JSON in
the server's key order), **microphone recording** (the Mac's mic alongside
the device's audio — mutually exclusive with the device's *own* mic since
scrcpy carries one device stream — mixed to a single AAC track via
`PCMMixdown`/`AudioTimeline`, level meter in `RecordAudioSheet`, per-source
mute writing silence; see the recording-audio convention), **terminal
scrolling in full-screen and streaming programs** (the wheel is reported to a
mouse-taking program — or sent as alternate-scroll cursor keys by the event's
own delta — through ONE shared local monitor for every mounted terminal, since
SwiftTerm seals `scrollWheel`/`keyDown` as public not open; `TerminalCompat`
repairs the alternate screen's right margin, which SwiftTerm leaves at 0 so
`cmdScrollDown` copied one column per row and interleaved two frames, tested
against real SwiftTerm so a dependency bump surfaces there; `TerminalScrollPin`
in ADBKit carries the `userScrolling` state — and follows scrollback trims — so
streaming output no longer snaps the view to the newest line), and four
main-thread hang fixes from Sentry (`FontCatalog` off the main actor via Core
Text, the log tail scrolling to document height with non-contiguous layout
instead of typesetting the buffer, Settings ▸ General's launchd round-trip
off-main, and `PaneFreezePolicy`/`ResizeActivity` pinning hidden keep-alive
tabs during live resizes) plus ffmpeg's real error surfacing through
`VideoEditing.stderrTail`. Under the hood: the portable ADBKit core (Linux +
Windows suites in CI, `PortabilityGuardTests`), the `ReactotronMCP` package
split, the tiered `make verify` harness with a mutation gate, and the
release-channel split above. Before that,
**v3.7.1** — the **Developer Settings feature** (the 59th:
`dev-settings`, a `DeveloperSettingsService` declarative toggle table over
`settings put`/`setprop` + the SYSPROPS poke — no force-RTL toggle; the
adb-reachable writes are only Developer Options' persistence, verified
ineffective live), a **mirror Show touches option** behind a new ⋯ options
menu (scrcpy's `show_touches` start option per (re)connect — its CleanUp
restores the device's own value — plus live `ShowTouches` writes only for
mid-session flips; persisted as `mirrorShowTouches`), **emulator Wipe Data
and Relaunch as separate actions** (`EmulatorService.wipeData` deletes the
Android-Studio wipe set in place, resolving the data dir from the AVD's
`.ini` `path=` line; Relaunch = console stop → port-free wait → boot),
**collapsed-rail tab badges** (`TerminalText.railBadge`) and **file drops
that type quoted paths into the shell** (`TerminalText.droppedPathsInsertion`;
AppKit-level `.fileURL`-only registration gated to the visible tab), and
fixes: welcome-tour paging clamped (double-activation crash), the update
pill recovering from an interrupted install, and the JS console feed paced
against chatty Metro streams (`ConsoleRateBucket`). Before that,
**v3.7.0** — the **universal (arm64 + x86_64) build**
(app + bundled ffmpeg lipo'd from per-slice SHA-pinned downloads;
`scripts/unpack-ffmpeg.sh` inflates the committed `ffmpeg.zip` before
generate — `make generate` and CI run it; `package-dmg.sh` refuses a DMG
missing a slice), **Reactotron MCP support** (Settings ▸ MCP: an embedded
localhost Streamable-HTTP MCP server with upstream Reactotron's exact
10-tool/8-resource contract and default-on redaction — see the "Reactotron
MCP" bullet and sync recipe above; `ReactotronMCP` target, ~100 new tests
incl. real-socket and golden-contract suites), **terminal session resume**
(implicit teardowns — quit, feature-tab close, background window close —
snapshot each tab's cwd via `TerminalResume` +
`LayoutState.terminalResumeDirs`; explicitly closed tabs are forgotten),
**per-pane Reactotron sort order** (`reactotronPane<n>NewestFirst`), a
**clear-data restart variant** on both consoles (`RestartClearScope`,
confirmed, beside the bounded cache clear; Reactotron gains the split
button), the **mirror grace window** (a hidden mirror stays live 2 min and
resumes in place; returning re-targets after a device switch —
`MirrorTabPolicy`, pinned in AppTests), a **redesigned What's New sheet**
(theme-resolved colors/size injected into the notes CSS,
`ReleaseNotesStyler` tested), and a **recurring, capped GitHub-star nudge**
(ask recorded at presentation so a quit can't replay it;
`LaunchPrompt.nextAskLaunch`). Before that, **v3.6.1** — a
resize-performance fix: `LogScrollView`
applies the log document width only after a drag rests (autoresizing
re-wrapped the whole buffer per tick — a pegged core while dragging with
Mirror Screen and log tabs open), and the logcat/iOS-logs stream flush
cadence went 120→300 ms. Before that, **v3.6.0** — the **JS Console and
Reactotron rework**
(filter-aware JSON export to file/clipboard via `ConsoleExport`,
find-in-object with clickable results — `SnapNode.findMatches`/`TreeMatch`
+ `JSONSearch` — a split-button Restart with a bounded
`pm clear --cache-only`, automatic `adb reverse` with capped retries,
connection self-heal, view refcounting across pane moves, and two-scan
auto-connect via `TargetStabilityTracker`), **logcat restyled as aligned
columns** (tid capture, `ps`-snapshot process naming, level chips, hashed
tag colors, click-holds-tail, chunked single-transaction ring trim),
**emulators named by their AVD** everywhere devices are listed, a
device-bar **Mirror Screen shortcut**, the **React Native role spanning
Android and iOS Simulators**, a **custom window background & text color**
(luminance-following scheme, low-contrast warning), grain independent of
opacity, a redesigned What's New sheet, auto-hiding succeeded install rows,
and the **mirror video re-fitting its pane on split resizes**
(`MirrorLayerNSView.setFrameSize`). Before that, **v3.5.0** — the
**translucent window appearance** (Settings ▸ Appearance ▸ Window —
Opacity/Blur/Grain sliders; dynamic `.bgRoot`/`.bgSurface` tokens put every
pane, card, bar, and the terminal on the glass; `WindowEffects` pure-tested
in ADBKit), **Sparkle disabled in Debug builds** (it was silently replacing
dev builds with the release on quit), the **feature notes system removed**
(the ⓘ strip, its Settings toggle, and ADBKit's `FeatureNotes` are gone), a
**Send Text redesign** (two hub sections — the send flow with its
failed-result inline, one recency-ranked snippet list, click-to-append
`{clipboard}`/`{ip}` chips, Return sends), **Reactotron filter persistence
and per-pane clear**, and a wider Settings window (640×540). Before that,
**v3.4.0** — an **AAB to APK converter** (the 58th feature: bundletool
universal APK with optional release-keystore signing; bundletool +
uber-apk-signer factory-seeded from `App/Resources`; double-clicked
`.aab`/`.apk` files open in-window — the `apk-open` workspace tab — with
background installs that survive navigation and post notifications),
**silent updates** (a custom `SPUUserDriver` — background download/stage, a
"Relaunch to update" sidebar pill, a What's New sheet on first launch of a
new version, `UpdatePolicy` pure-tested in ADBKit), the **Crash Catcher
rebuilt as a multi-crash browser** (`CrashParser` splits Java/native/RN/ANR
crashes; watch mode; 16 MB fetch cap), **Send Text snippets reworked** (one
creator, recent tags, a searchable library), **wireless pairing
auto-connect** (mDNS `adb mdns services` discovery after pairing; bare
connect IPs default to :5555), **split panes clamped to 30–70%**
(`PaneSplit`) with every feature adapted to narrow panes, a skippable
welcome tour, and a drop-to-split fix (tab drags ride a topmost overlay
target past full-pane URL drop regions). Before that,
**v3.3.x** — **iOS Logs rebuilt** around the unified log (app-scoped stream,
freeze-on-scroll with an "N new" pill, Xcode-style rows, error/fault
counters), ⌘F routed to the active tab's find/filter, a **JS console that
stays connected** (proxy-heartbeat keepalive, relaunch/sleep/Metro-restart
reconnects), the **mirror session leak fixed** (no more runaway CPU),
logcat Filter/Find split, and a Sparkle **beta update channel**. Before that,
**v3.2.0** — **wireless pair & connect from the device dropdown**: a
"Wireless debugging" menu section opens `WirelessConnectSheet`, a guided
three-tab sheet (Android 11+ pairing-code steps, direct `ip:port` connect,
one-click USB→Wi-Fi tcpip bootstrap) over the existing `ConnectionService`,
with pasted endpoints parsed by the pure `ConnectionService.parseEndpoint`
(tested, IPv6 included) gating the buttons, adb's reason shown inline on
failure, and a successful connect auto-selecting the device. Before that,
**v3.1.0** — **custom commands reworked** (one free-typed multi-line box, adb
inferred from the leading token, per-command choice of the in-app Terminal or
the Mac's default terminal), a **curatable Quick Actions panel** (pin custom
commands, hide actions, a pick-an-app interstitial for `{bundleId}` runs),
**twice-daily update checks** with a launch reminder for a dismissed update,
an app **Restart verb** everywhere apps are managed (with launching by
resolved activity, fixing stub-`monkey` devices), **no more Homebrew
installs** (the Doctor links to install sources instead),
and a **two-page tour finale** (record the hotkey, then press it for real —
confetti on completion; terminal tabs now default to the top strip). Before
that,
**v3.0.0** — **terminal split panes** (⌘D/⇧⌘D via the tested `TerminalSplitTree`,
cwd inheritance into new tabs/panes, a Chrome-style top tab strip option), an
**onboarding tour rebuilt around recordings of the real app**, redesigned
**React Native and Connection hubs** (described action cards, a Metro port
field, the device's live Wi-Fi network + IP), **custom commands through the
login shell** (rc aliases resolve; optionally typed into a Terminal tab), JS
Console **Reload JS / Restart app**, and a **Pinned section on Home** with a
permanent Home icon leading the tab strip. Before that,
**v2.9.0** — **background mode** (closing the main window keeps Droidective
resident in the menu bar, drops the Dock icon, and stops kept-alive sessions;
⌘Q still quits) with a global **Quick Actions panel** (a non-activating
Raycast-style mini app on a global hotkey: instant/toggle/form actions, custom
commands, Manage Apps, Emulators, and Install APK, with per-action device
targeting, run-on-all, and Finder APK routing — see `QuickActionsView` and the
tested `PanelTargeting`), plus a **terminal tab rail** with a find bar (⌘F,
⌘G / ⇧⌘G) and a Dock-style **auto-hiding sidebar**; before that a native
multi-tab **Terminal** feature (PTY login shells via SwiftTerm,
ANDROID_SERIAL-scoped) and shell-kind custom commands through `zsh -lc`. Before
that, **v2.7.0** — a full APK toolchain (APK Studio: inspect, decompile via
jadx/apktool, recompile, and sign — with keystore creation) plus Frida setup, a
custom accent color, launching emulators from the device bar, per-feature
connect-a-device empty states, a live-preview hotkey recorder, and a Settings
split into Appearance/Privacy; managed tools download from GitHub releases into
Application Support and are sized/removable in Settings); 1503 ADBKit + 99
AppTests green (macOS — the suite also runs on Linux in CI, minus the
Darwin-gated files);
builds clean with zero warnings (enforced as errors in CI). Verified live against a
physical device and an Android emulator. Release builds are Developer ID-signed +
notarized and bundle scrcpy/ffmpeg (see `RELEASING.md`). Open gaps: the Apps
list/detail divider isn't drag-resizable.
