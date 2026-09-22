# Next session — the prompt

Copy the block below into a fresh session. It is kept in the repo rather than
in a chat scrollback so the next run starts from the same place this one ended.

---

```
Droidective — Windows/Linux app (phase 3). Continue bringing it to macOS parity.

START FROM LATEST MAIN — always, before anything else
  cd /Users/rohindhr/Projects/Droidective
  git fetch origin --prune
  git checkout main && git merge --ff-only origin/main
  git checkout -b <new-branch>
One coherent chunk per PR. Stack only if you cannot merge; say so in the body.

  Rust is installed but NOT on PATH: export PATH="$HOME/.cargo/bin:$PATH"
  Node: source "$HOME/.nvm/nvm.sh" && nvm use 22 (system node is too old for Vite)

STATE
  The shell is done. 30 of the 32 full-screen views have a pane; the two
  without are `frida-console` (needs a rooted device) and `ios-logs` (out of
  scope — a macOS toolchain). That number was wrong in two places at once for
  a while, so recompute rather than trust it: catalogFeatureIDs filtered to
  view/system, against the desktop pane router.

  THE AUDIT IS THE MODE OF WORK, and it stands at 313 of 329. The per-feature
  checklists in `docs/desktop-parity.md` are it. A tick means the affordance
  was found in desktop/src *and read in place*.

  "What the last 16 are" in the tracker says what remains and why most of it
  should never tick. The short version: 3 out of scope, 2 need hardware this
  machine lacks, 9 are one subsystem (scrcpy's audio stream), 2 are deliberate
  divergences where the Mac's wording would be inaccurate here.

  Landed most recently (check the merged PRs before assuming):
    - #380-#383 closed the audit's buildable gaps in bulk — decompile find,
      images, exports, unsigned APKs, terminal groups.
    - #384 took it from 292 to 313: the Mac's `AlertDialog` (one OK, Return
      dismisses) and with it Reactotron's disconnect alert and intro sheet and
      API Testing's import/export failures; Custom Commands' script picker and
      `Added`; an `InstalledAppsPicker`; APK Studio's rebuilt result row;
      Apps' Explore-files sheet, Pull APK and the whole Manage section
      (`/v1/apps/lifecycle` over ADBKit's `SystemAppsService`, which the daemon
      had never exposed); Simulate's `Reset all overrides` (which needed
      `/v1/overrides/active` first); the mirror's ⋯ menu with Show touches;
      `Arrange Mirror Windows`; and the terminal strip's drag.

READ FIRST
  docs/desktop-parity.md — THE TRACKER. Read "Status today" and then the
    Backlog. Work it in order unless something has obviously changed.
  desktop/README.md — architecture and conventions.
  docs/droidectived-protocol.md §4–5 — the route and topic tables.

THE RULE THAT MATTERS MOST
  The desktop UI *is* the Mac's UI. Before building any control, open the macOS
  view that already has it (the tracker names the file) and match its wording,
  icon, confirmation shape and gesture. A double-click stays a double-click; a
  confirmationDialog stays a dialog and does not become a button that arms
  itself. If an idea is genuinely better, it goes into the Mac app FIRST.
  Two standing exceptions: a keyboard shortcut whose modifier has no
  Windows/Linux equivalent, and a label that names a platform.

THE FRAME BUG IS FIXED — and it was two bugs, neither as described
  Both of the daemon's WebSocket servers took NIO's `maxFrameSize` default of
  16,384 bytes (not ~64 KB — that was a guess from the length-encoding
  boundary), so anything past it got close 1009 and lost the connection. On the
  stream socket a ~12 KiB terminal paste would have done it, since `write`
  carries base64. Both now pass `DaemonProtocol.maxWebSocketFrameSize` = 64 MiB,
  which is the Mac's own number in `ReactotronServer`.

  The "incorrect masking" was a *separate* bug and had nothing to do with size:
  both handlers answered a ping by copying the inbound frame and flipping its
  opcode, which keeps the client's masking key on a server→client frame. Any
  conformant client closes with 1002 on sight — `websockets` pings at 20 s,
  which is why it showed up mid `--big` run and looked like one fault.
  `WebSocketFrame.pong(for:)` is the single helper both call now.

  The lesson worth carrying: the previous note's whole diagnosis came from a
  client library's error string. Capturing the daemon's own bytes off a raw
  socket settled it in minutes, and the two scripts that did it are the way to
  check anything like it again.

WHAT IS LEFT, roughly by value
  - scrcpy's AUDIO STREAM is the biggest single piece: nine of the sixteen
    remaining audit items are this one feature. The daemon's transport already
    opens the audio socket and `ScrcpyServerParams` already has `audio` and
    `audioSource`, but nothing requests it, nothing forwards the frames, and
    nothing decodes them — that last part is a WebCodecs `AudioDecoder` and a
    Web Audio graph in the page. Four layers, and only honestly verifiable
    against a real device. When it lands, the mirror's ⋯ tooltip goes back to
    the Mac's "Audio and touch options" from the "Touch options" it says today.
  - WINDOWS HAS NO RUNTIME COVERAGE, and this is the biggest exposure on the
    list even though it is not a feature. `build-windows` compiles the app;
    nothing launches it. `scripts/smoke-desktop-windows.ps1` exists but fires
    only on beta tags. `desktop-linux-smoke` found the app unusable three ways
    over on its first run — that is the class of bug Windows is currently
    blind to.
  - The welcome tour (backlog 22). The Mac's demo stage plays recordings of the
    *Mac* app, which would be the wrong chrome here, so the six drawn fallbacks
    are what to follow.
  - What's New, and the recurring capped star prompt.
  - Settings ▸ MCP — a port task of its own size: `ReactotronMCP` is
    `#if canImport(Network)`-gated end to end and taps ADBKit's Apple-only
    `ReactotronServer`, so serving it off Apple means feeding `McpCommandStore`
    from the daemon's NIO relay instead.
  - The updater (23) — blocked on a signing keypair, which is the maintainer's
    to create.
  - The QR-code tab of the wireless sheet. `QrPairing` is already portable in
    ADBKit; it needs a daemon verb (a minutes-long stream of phases, not one
    request) and a QR renderer. **It cannot be verified on an emulator** — adb
    37 dropped Bonjour and openscreen ignores same-host advertisements, so the
    last leg needs a physical phone.
  - `frida-console`, which needs a rooted device.
  - The BUNDLE MANAGER is the last half of a pair: `InstalledAppsPicker` and
    the device bar's app pill are built, so what is missing is the *store* —
    nicknamed packages, and the `Add manually / manage…` item that both the
    pill and Logcat's app bar leave out because there is nothing to manage.
  - The install inbox; the self-metrics overlay.
  - Inside screens: the File Explorer's keyboard navigation and clipboard keys,
    Install App's live stage line, Memory Usage pausing when its tab is hidden.

EVERY FEATURE IS FOUR LAYERS
  1. daemon: a `DaemonProtocol.Route` case (or a `StreamProtocol.Topic`), wire
     shapes, a `DaemonBackend` method — add the default to
     `Tests/DaemonCoreTests/BackendDefaults.swift`, not to five stubs — a
     `DaemonServer` case, and tests
  2. Rust: a wire type in daemon/wire.rs, a client method, a
     #[tauri::command], registered in lib.rs
  3. TS: a lib/*.ts holding the *decisions* (tested), a hook, a thin pane
  4. route the pane in FeaturePane.tsx (via components/panes.ts)

VERIFY
  make desktop-test          # tsc + oxlint + vitest + cargo fmt/clippy/test
  make verify                # tiers 0-1: warnings-as-errors + all four bundles
  make test-linux            # the port gate: the same suite on Linux

  The whole cross-platform ladder, all of which has been run green at least
  once (2025-09-22) — times are for a warm cache:
    make verify              ~2 min
    make test-linux          ~4 min   (container system start first, once/boot)
    make test-emulator       ~1 min   (needs a device; see the disk note below)
    make test-smoke          ~2 min   (the Mac app actually launches)
    make desktop-linux       ~50 min cold, minutes warm — builds the .deb in a
                             container. The AppImage step fails locally on
                             `linuxdeploy`; the .deb, which is what the smoke
                             installs, builds fine.
    ./scripts/smoke-desktop-linux.sh <deb>   ~4 min — installs into a bare
                             ubuntu:24.04, drives the palette under Xvfb, and
                             photographs the framebuffer. Every check is fatal.

  test-emulator needs ROOM: `AppBundleInstallLiveTests` installs a second copy
  of an app, and a 6 GB AVD sitting at 96% fails it with the device's own
  "Requested internal only, but not enough space". Grow
  disk.dataPartition.size in ~/.android/avd/<name>.avd/config.ini and restart.

  Run it for real (rebuild the sidecar after ANY daemon change):
    export PATH="$HOME/.cargo/bin:$PATH"
    ./scripts/build-daemon-sidecar.sh debug
    cd desktop && npx tauri build --debug --no-bundle
    cp src-tauri/binaries/droidectived-* src-tauri/target/debug/droidectived
    pkill -f droidective-desktop; ./src-tauri/target/debug/droidective-desktop &

GOTCHAS (the ones that cost time)
  An unstructured `Task { }` does NOT inherit its parent's cancellation. A pull
    started inside one survived the unsubscribe meant to stop it, and every
    unit test passed — the 600 MB transfer went on copying after the strip had
    gone. Await cancellable work in the subscription's own task.
  The emulator's own `screenrecord` produces one-frame files with no duration.
    For a real device clip, use the app's recorder (/v1/record/start + stop).
  oxlint's max-lines (300), max-lines-per-function (100) and max-dependencies
    (10) are errors here in practice. Split early; the repo's own pattern is a
    `*Parts.tsx` sibling or a purpose-named `lib/` module re-exported from its
    barrel.
  cargo fmt is a SEPARATE gate from clippy. Run `make desktop-test`.
  build-daemon-sidecar.sh exits early with "rustc is not on PATH" — and the
    stale sidecar is then SILENT. Export PATH before running it.
  A pre-commit hook blocks any command matching `git push.*main`, including
    `gh pr create --base main`. Split the push and the PR create.

DRIVING THE UI — read this before planning to screenshot anything
  DO NOT BUDGET ON IT. Synthetic clicks into the webview work for a while and
  then stop landing — they still move the cursor and still trigger hover, but
  the click does nothing. This has now degraded mid-session three sessions
  running, and each time the recovery attempts cost more than the screenshot
  was worth. Native panels, the Mac app and the menu bar are unaffected.
  Screen Recording permission may also not be granted to the terminal:
  `screencapture` then returns a *black* image rather than failing. A black
  capture WITH permission granted usually means the window is on another Space
  — check CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly) and
  relaunch it onto the active one rather than chasing the permission.
  Keystrokes never reach the page. They do reach a native open/save panel:
  Shift-Cmd-G, a full path, Return twice — but in a SAVE panel type a bare
  filename, since a leading slash opens go-to-folder and the name becomes ".".
  What works instead, and is better anyway:
    - component tests (@testing-library/react is already a dependency, and
      `NetspeedPane.test.tsx` is the worked example) for anything on screen
    - the daemon end to end, which is the most reliable thing here and was
      what proved `/v1/apps/lifecycle`, `/v1/overrides/*` and the mirror
      stream against a live emulator. Start one yourself rather than hunting
      the app's:
        droidectived/.build/out/Products/Debug/droidectived --port 0 \
          --token-file /tmp/tok    # prints "listening 127.0.0.1:<port>"
      then POST with `Authorization: Bearer $(cat /tmp/tok)`. For the stream
      socket make a venv (`python3 -m venv`; pip is externally managed here)
      and install `websockets` — one subscribe proved mirror frames of 129 KB
      and logcat frames of 149 KB arrive intact, which is the 16 KiB frame bug
      staying fixed. ROUND-TRIP anything you change on a device and check the
      device itself afterwards, not the daemon's own read.
    - curl against the running app's own daemon for routes: read the port with
      `lsof -nP -iTCP -sTCP:LISTEN -a -p $(pgrep -f 'droidectived --port')` and
      the token from
      "$HOME/Library/Application Support/com.rohindh.droidective.desktop/droidectived.token"
    - `./scripts/reactotron-fake-client.py` — a React Native app as far as the
      relay is concerned. It answers every request the State, REPL and Commands
      screens make, and announces a custom command on connect. All three
      screens were verified with it without ever being rendered. Open
      Reactotron first or there is nothing listening on 9090, and note that
      whichever app holds 9090 is the one it talks to — with both apps running
      it is easy to test the wrong one.
  Synthetic mouse events never start an HTML5 drag in WKWebView, so every drag
  path is checked by hand — keep the *decision* a drop makes in lib/.
```
